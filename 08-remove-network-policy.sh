
#!/bin/bash
echo "=== Removing NetworkPolicies (homelab simplification) ==="
kubectl -n monitoring delete networkpolicy --all
echo "NetworkPolicies removed"
