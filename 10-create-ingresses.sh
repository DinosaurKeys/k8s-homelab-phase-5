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
