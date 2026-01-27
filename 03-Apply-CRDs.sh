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
