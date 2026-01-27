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
kubectl -n monitoring patch deployment grafana --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/0",
    "value": {
      "name": "grafana-storage",
      "persistentVolumeClaim": {
        "claimName": "grafana-storage"
      }
    }
  }
]'

echo ""
echo "=== Storage patches applied ==="
echo "Grafana will restart with persistent storage"
