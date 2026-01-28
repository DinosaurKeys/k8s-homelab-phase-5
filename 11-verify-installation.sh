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
