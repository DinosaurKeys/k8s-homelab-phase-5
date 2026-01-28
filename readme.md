# Install Prometheus + Grafana

This installs the upstream **kube-prometheus** stack (Prometheus, Alertmanager, Grafana, exporters) using raw manifests — no Helm.

## What you're building

<details>
<summary>Architecture diagram (click to expand)</summary>

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MONITORING STACK ARCHITECTURE                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         DATA SOURCES                                 │   │
│  │                                                                      │   │
│  │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │   │
│  │   │ kube-state   │  │ node         │  │ Your Apps    │             │   │
│  │   │ -metrics     │  │ -exporter    │  │ /metrics     │             │   │
│  │   │              │  │              │  │              │             │   │
│  │   │ K8s object   │  │ CPU, memory  │  │ App-specific │             │   │
│  │   │ states       │  │ disk, net    │  │ metrics      │             │   │
│  │   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘             │   │
│  │          │                 │                 │                      │   │
│  └──────────┼─────────────────┼─────────────────┼──────────────────────┘   │
│             │                 │                 │                          │
│             └─────────────────┼─────────────────┘                          │
│                               ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        PROMETHEUS                                   │   │
│  │                                                                      │   │
│  │   - Scrapes /metrics endpoints every 30s                            │   │
│  │   - Stores time-series data in Longhorn PVC                         │   │
│  │   - Evaluates alerting rules                                        │   │
│  │   - Exposes PromQL query interface                                  │   │
│  │                                                                      │   │
│  └──────────────────────────────────┬──────────────────────────────────┘   │
│                                     │                                      │
│                    ┌────────────────┼────────────────┐                     │
│                    ▼                ▼                ▼                     │
│  ┌──────────────────────┐  ┌──────────────────┐  ┌──────────────────┐     │
│  │    GRAFANA           │  │  ALERTMANAGER    │  │  PROMETHEUS UI    │     │
│  │                      │  │                  │  │                  │     │
│  │ - Visualizations     │  │ - Routes alerts  │  │ - PromQL queries  │     │
│  │ - Dashboards         │  │ - Deduplication  │  │ - Target status   │     │
│  │ - Alerts overview    │  │ - Email/Slack    │  │ - Config view     │     │
│  │                      │  │                  │  │                  │     │
│  │ grafana.local        │  │                  │  │ prometheus.local  │     │
│  └──────────────────────┘  └──────────────────┘  └──────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

</details>

---

## Prereqs

- Kubernetes cluster is working (`kubectl get nodes`)
- Longhorn installed (for PVCs)
- Ingress-NGINX installed (Ingress controller)
- cert-manager + issuer named `homelab-ca-issuer` (only needed for TLS Ingress examples)

---

## Script 01: Download kube-prometheus

`01-download-bits.sh`:

```bash
#!/bin/bash
set -e

mkdir -p manifests/prometheus
git clone --depth 1 --branch v0.13.0   https://github.com/prometheus-operator/kube-prometheus.git   manifests/prometheus
```

---

## Script 02: Review manifests

`02-review-manifests.sh`:

```bash
#!/bin/bash
set -e

echo "=== Manifest directories ==="
ls manifests/prometheus/manifests/

echo ""
echo "=== Setup manifests (CRDs, namespace) ==="
ls manifests/prometheus/manifests/setup/
```

---

## Script 03: Apply CRDs

`03-apply-crds.sh`:

```bash
#!/bin/bash
set -e

echo "=== Applying CRDs + namespace (server-side) ==="
kubectl apply --server-side -f manifests/prometheus/manifests/setup/

echo ""
echo "=== Waiting for CRDs to be Established ==="
kubectl wait   --for=condition=Established   --all CustomResourceDefinition   --timeout=120s
```

---

## Why `fsGroup` matters (Prometheus + PVC)

Prometheus runs as a non-root user. If the volume is mounted as `root:root`, Prometheus can't write.

| Setting | Volume owner | Prometheus can write? |
|---|---|---|
| **No `fsGroup`** | `root:root (0:0)` | ❌ Permission denied |
| **With `fsGroup: 2000`** | `root:2000` | ✅ Works |

---

## Script 04: Create Prometheus storage patch (Longhorn + fsGroup)

`04-prometheus-storage-patch.sh` (creates `prometheus-storage-patch.yaml`):

```bash
#!/bin/bash
set -e

cat > prometheus-storage-patch.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: k8s
  namespace: monitoring
  labels:
    app.kubernetes.io/component: prometheus
    app.kubernetes.io/instance: k8s
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: kube-prometheus
    app.kubernetes.io/version: 2.45.0
spec:
  # Watch ALL ServiceMonitors/PodMonitors (useful for homelab)
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
  podMonitorSelector: {}
  podMonitorNamespaceSelector: {}

  podMetadata:
    labels:
      app.kubernetes.io/component: prometheus
      app.kubernetes.io/part-of: kube-prometheus

  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: longhorn
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi

  retention: 15d
  replicas: 1

  resources:
    requests:
      memory: 400Mi
    limits:
      memory: 2Gi

  securityContext:
    fsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000

  alerting:
    alertmanagers:
      - namespace: monitoring
        name: alertmanager-main
        port: web

  serviceAccountName: prometheus-k8s
  ruleSelector: {}
  ruleNamespaceSelector: {}
EOF

echo "Created prometheus-storage-patch.yaml"
```

---

## Script 05: Create Grafana PVC

`05-grafana-pvc.sh` (creates `grafana-pvc.yaml`):

```bash
#!/bin/bash
set -e

cat > grafana-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: monitoring
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

echo "Created grafana-pvc.yaml"
```

> Note: Don’t try to `kubectl apply` a “partial Deployment” to add storage — it fails because required fields (selector, labels, image, etc.) are missing. Create the PVC, then **patch** the existing Deployment.

---

## Optional: Remove NetworkPolicies (homelab simplification)

`remove-networkpolicies.sh`:

```bash
#!/bin/bash
set -e

echo "=== Removing NetworkPolicies (monitoring namespace) ==="
kubectl -n monitoring delete networkpolicy --all
echo "NetworkPolicies removed"
```

---

## Script 06: Apply monitoring stack

`06-apply-monitoring-manifests.sh`:

```bash
#!/bin/bash
set -e

echo "=== Applying kube-prometheus main manifests ==="
kubectl apply -f manifests/prometheus/manifests/

echo ""
echo "=== Waiting 60 seconds for pods to start ==="
sleep 60
```

---

## Script 07: Apply storage patches

`07-apply-storage-patches.sh`:

```bash
#!/bin/bash
set -e

echo "=== Applying Prometheus storage patch ==="
kubectl apply -f prometheus-storage-patch.yaml

echo ""
echo "=== Applying Grafana PVC ==="
kubectl apply -f grafana-pvc.yaml

echo ""
echo "=== Waiting for Grafana PVC to bind ==="
kubectl -n monitoring wait --for=jsonpath='{.status.phase}'=Bound pvc/grafana-storage --timeout=120s

echo ""
echo "=== Patching Grafana Deployment to use the PVC ==="
kubectl -n monitoring patch deployment grafana --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "grafana-storage",
        "persistentVolumeClaim": {
          "claimName": "grafana-storage"
        }
      }
    ]
  }
]'

echo ""
echo "=== Storage patches applied ==="
echo "Grafana will restart with persistent storage."
```

---

## Script 08: Wait for pods

`08-wait-for-pods.sh`:

```bash
#!/bin/bash
set -e

echo "=== Waiting for monitoring pods (3-5 minutes) ==="
echo "Checking every 30 seconds..."

while true; do
  NOT_READY=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
  TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
  RUNNING=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep "Running" | wc -l)

  echo "$(date +%H:%M:%S) - Running: $RUNNING | Not Ready: $NOT_READY | Total: $TOTAL"

  if [ "$NOT_READY" -eq 0 ] && [ "$TOTAL" -gt 10 ]; then
    echo ""
    echo "All pods ready!"
    break
  fi

  sleep 30
done
```

---

## Script 09: Create Ingresses (TLS)

`09-create-ingresses.sh`:

```bash
#!/bin/bash
set -e

echo "=== Creating Grafana Ingress ==="
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "homelab-ca-issuer"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.local
      secretName: grafana-tls
  rules:
    - host: grafana.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
EOF

echo ""
echo "=== Creating Prometheus Ingress ==="
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "homelab-ca-issuer"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - prometheus.local
      secretName: prometheus-tls
  rules:
    - host: prometheus.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prometheus-k8s
                port:
                  number: 9090
EOF

echo ""
echo "=== Ingresses created ==="
kubectl get ingress -n monitoring
```

---

## Script 10: Verify installation

`10-verify-installation.sh`:

```bash
#!/bin/bash
set -e

echo "=== Prometheus pods ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

echo ""
echo "=== Grafana pod ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

echo ""
echo "=== Alertmanager pods ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager

echo ""
echo "=== Node Exporter (one per node) ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=node-exporter -o wide

echo ""
echo "=== kube-state-metrics ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=kube-state-metrics

echo ""
echo "=== Persistent Volume Claims ==="
kubectl get pvc -n monitoring

echo ""
echo "=== Ingresses ==="
kubectl get ingress -n monitoring

echo ""
echo "============================================"
echo "Access Grafana at: https://grafana.local"
echo "Access Prometheus at: https://prometheus.local"
echo "Default Grafana credentials: admin / admin"
echo "============================================"
```

---

## Access services

Add to your laptop `/etc/hosts`:

```text
192.168.0.240  grafana.local prometheus.local
```

Default Grafana credentials:

- URL: `https://grafana.local`
- Username: `admin`
- Password: `admin`

---

## Troubleshooting

### Grafana PVC stuck in Pending?

```bash
kubectl describe pvc grafana-storage -n monitoring
kubectl get volumes.longhorn.io -n longhorn-system
```

### Grafana pod crashing after patch?

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50
kubectl describe pod -n monitoring -l app.kubernetes.io/name=grafana | grep -A10 "Volumes:"
```

### Prometheus not scraping targets?

```bash
kubectl get servicemonitors -n monitoring
```

Prometheus UI: `https://prometheus.local` → **Status → Targets**

---

## Verify storage is on the dedicated Longhorn disk

```bash
echo "=== Checking Longhorn volumes ==="
kubectl get volumes.longhorn.io -n longhorn-system

echo ""
echo "=== Checking data location on workers ==="
for worker in worker-1 worker-2 worker-3; do
  echo "--- $worker ---"
  ssh $worker "du -sh /mnt/longhorn/replicas/ 2>/dev/null"
done
```
