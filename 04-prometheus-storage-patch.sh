
#!/bin/bash

# Create a patch for Prometheus to use Longhorn with correct permissions
cat > prometheus-storage-patch.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: k8s
  namespace: monitoring
spec:
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
  resources:
    requests:
      memory: 400Mi
    limits:
      memory: 2Gi
  securityContext:
    fsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
EOF
