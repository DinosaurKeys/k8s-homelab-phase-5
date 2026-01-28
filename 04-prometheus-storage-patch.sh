
#!/bin/bash

# Create a patch for Prometheus to use Longhorn with correct permissions
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
