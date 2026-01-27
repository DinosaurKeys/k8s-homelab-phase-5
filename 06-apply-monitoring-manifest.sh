#!/bin/bash

echo "=== Applying monitoring stack (main manifests) ==="
kubectl apply -f manifests/prometheus/manifests/

echo ""
echo "=== Waiting for base deployment (60 seconds) ==="
sleep 60
