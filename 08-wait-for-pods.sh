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
