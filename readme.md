# Install Prometheus and Grafana (No Helm)

## What You're Building

```
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
│  │   - Stores time-series data in Longhorn PVC                        │   │
│  │   - Evaluates alerting rules                                        │   │
│  │   - Exposes PromQL query interface                                  │   │
│  │                                                                      │   │
│  └──────────────────────────────────┬──────────────────────────────────┘   │
│                                     │                                      │
│                    ┌────────────────┼────────────────┐                     │
│                    ▼                ▼                ▼                     │
│  ┌──────────────────────┐  ┌──────────────────┐  ┌──────────────────┐     │
│  │    GRAFANA           │  │  ALERTMANAGER    │  │  PROMETHEUS UI   │     │
│  │                      │  │                  │  │                  │     │
│  │ - Visualizations     │  │ - Routes alerts  │  │ - PromQL queries │     │
│  │ - Dashboards         │  │ - Deduplication  │  │ - Target status  │     │
│  │ - Alerts overview    │  │ - Email/Slack    │  │ - Config view    │     │
│  │                      │  │                  │  │                  │     │
│  │ grafana.local        │  │                  │  │ prometheus.local │     │
│  └──────────────────────┘  └──────────────────┘  └──────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Script 01: Download kube-prometheus

`01-download-bits.sh`:

```bash
#!/bin/bash

mkdir -p manifests/prometheus
git clone --depth 1 --branch v0.13.0 \
  https://github.com/prometheus-operator/kube-prometheus.git \
  manifests/prometheus
```

---

## Script 02: Review Manifests

`02-Review-Manifest.sh`:

```bash
#!/bin/bash

echo "=== Manifest directories ==="
ls manifests/prometheus/manifests/

echo ""
echo "=== Setup manifests (CRDs) ==="
ls manifests/prometheus/manifests/setup/
```

---

## Script 03: Apply CRDs

`03-Apply-CRDs.sh`:

```bash
#!/bin/bash

# Apply CRDs and namespace first
echo "=== Applying CRDs and namespace ==="
kubectl apply --server-side -f manifests/prometheus/manifests/setup/

# Wait for CRDs to be established
echo "=== Waiting for CRDs ==="
kubectl wait \
  --for condition=Established \
  --all CustomResourceDefinition \
  --namespace=monitoring \
  --timeout=120s
```

---


Without fsGroup:
┌─────────────────────────────────┐
│ /prometheus volume              │
│ Owner: root:root (0:0)          │
│ Prometheus user: 1000           │
│ Result: PERMISSION DENIED       │
└─────────────────────────────────┘

With fsGroup: 2000:
┌─────────────────────────────────┐
│ /prometheus volume              │
│ Owner: root:2000                │
│ Prometheus user: 1000           │
│ Prometheus group: 2000          │
│ Result: CAN WRITE ✓             │
└─────────────────────────────────┘



## Script 04: Create Prometheus Storage Patch

`04-prometheus-storage-patch.sh`:

#!/bin/bash
kubectl apply -f - <<'EOF'
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
  # THIS IS WHAT WAS MISSING - tells Prometheus to watch ALL ServiceMonitors
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
  podMonitorSelector: {}
  podMonitorNamespaceSelector: {}

  # Pod labels for service discovery
  podMetadata:
    labels:
      app.kubernetes.io/component: prometheus
      app.kubernetes.io/part-of: kube-prometheus

  # Storage on Longhorn
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: longhorn
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi

  # Other settings
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

  # Required references
  alerting:
    alertmanagers:
    - namespace: monitoring
      name: alertmanager-main
      port: web

  serviceAccountName: prometheus-k8s
  ruleSelector: {}
  ruleNamespaceSelector: {}
EOF


---

## Script 05: Create Grafana PVC (CORRECTED)

`05-grafana-pvc.sh`:

```bash
#!/bin/bash

# Create ONLY the PVC file (NOT a partial Deployment - that doesn't work!)
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

**Why this is different:** You cannot apply a partial Deployment (missing selector, labels, image). Instead, we create just the PVC, then use `kubectl patch` to modify the existing Deployment.


---

##REMOVE all Policy

#!/bin/bash
echo "=== Removing NetworkPolicies (homelab simplification) ==="
kubectl -n monitoring delete networkpolicy --all
echo "NetworkPolicies removed"






## Script 06: Apply Monitoring Stack

`06-apply-monitoring-manifest.sh`:

```bash
#!/bin/bash

echo "=== Applying monitoring stack (main manifests) ==="
kubectl apply -f manifests/prometheus/manifests/

echo ""
echo "=== Waiting for base deployment (60 seconds) ==="
sleep 60
```

---

## Script 07: Apply Storage Patches (CORRECTED)

`07-apply-storage-patches.sh`:

```bash
#!/bin/bash

echo "=== Applying Prometheus storage patch ==="
kubectl apply -f prometheus-storage-patch.yaml

echo ""
echo "=== Applying Grafana PVC ==="
kubectl apply -f grafana-pvc.yaml

echo ""
echo "=== Waiting for Grafana PVC to bind ==="
kubectl -n monitoring wait --for=jsonpath='{.status.phase}'=Bound pvc/grafana-storage --timeout=120s

echo ""
echo "=== Patching Grafana Deployment to use PVC ==="
# This patches the EXISTING Grafana deployment to use our PVC
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
echo "Grafana will restart with persistent storage"
```

**What this does:**
1. Applies Prometheus storage (this merges with existing Prometheus CR)
2. Creates Grafana PVC
3. Waits for PVC to bind (Longhorn creates the volume)
4. Patches the EXISTING Grafana Deployment to use the PVC

---

## Script 08: Wait for Pods

`08-wait-for-pods.sh`:

```bash
#!/bin/bash

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

## Script 09: Create Ingresses

`09-create-ingresses.sh`:

```bash
#!/bin/bash

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

## Script 10: Verify Installation

`10-verify-installation.sh`:

```bash
#!/bin/bash

echo "=== Prometheus pods ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

echo ""
echo "=== Grafana pod ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

echo ""
echo "=== AlertManager pods ==="
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

## Access Services

Add to your laptop's `/etc/hosts`:
```
192.168.0.240  grafana.local prometheus.local
```

**Default Grafana credentials:**
- URL: https://grafana.local
- Username: `admin`
- Password: `admin`

---

## What Was Wrong With Your Original Script 05

```
YOUR ORIGINAL 05-grafana-storage-patch.sh:
┌─────────────────────────────────────────────────────────────────────────────┐
│ apiVersion: apps/v1                                                         │
│ kind: Deployment            ← This is a PARTIAL Deployment                  │
│ metadata:                                                                   │
│   name: grafana                                                             │
│ spec:                                                                       │
│   template:                 ← Missing: selector, labels                     │
│     spec:                                                                   │
│       containers:                                                           │
│       - name: grafana       ← Missing: image (REQUIRED!)                    │
│                                                                             │
│ ERROR: "spec.selector: Required value"                                      │
│ ERROR: "spec.template.spec.containers[0].image: Required value"             │
└─────────────────────────────────────────────────────────────────────────────┘

CORRECTED APPROACH:
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Create just the PVC (complete resource, works fine)                     │
│ 2. Apply main manifests (creates Grafana Deployment)                       │
│ 3. Use kubectl patch to MODIFY the existing Deployment                     │
│                                                                             │
│ kubectl patch deployment grafana --type='json' -p='[...]'                  │
│                                                                             │
│ This MODIFIES the existing Deployment, keeping all its fields intact       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### Grafana PVC stuck in Pending?

```bash
# Check PVC status
kubectl describe pvc grafana-storage -n monitoring

# Check Longhorn
kubectl get volumes.longhorn.io -n longhorn-system
```

### Grafana pod crashing after patch?

```bash
# Check pod logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50

# Check if volume is mounted correctly
kubectl describe pod -n monitoring -l app.kubernetes.io/name=grafana | grep -A10 "Volumes:"
```

### Prometheus not scraping targets?

```bash
# Check service monitors
kubectl get servicemonitors -n monitoring

# Check Prometheus targets in UI
# https://prometheus.local → Status → Targets
```

---

## Verify Storage is on Dedicated Disk

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

