#!/bin/bash
set -euo pipefail

# Inject MongoDB connection pool exhaustion

echo "=== Injecting MongoDB Connection Pool Exhaustion ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

NAMESPACE=${NAMESPACE:-dev}
JOKE_SERVER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[0].metadata.name}')

if [ -z "$JOKE_SERVER_POD" ]; then
  echo "❌ No joke-server pod found"
  exit 1
fi

echo "Target pod: $JOKE_SERVER_POD"

# Inject MongoDB pool exhaustion fault
echo "Injecting MongoDB connection pool exhaustion..."
kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -X POST http://localhost:8080/inject/fault \
  -H "Content-Type: application/json" \
  -d '{
    "component": "mongodb",
    "failureMode": "pool-exhausted",
    "duration": "5m",
    "details": {
      "message": "Connection pool exhausted - simulating too many concurrent connections"
    }
  }'

echo -e "\n✅ MongoDB pool exhaustion injected"
echo "Expected behavior:"
echo "- /healthz endpoint: Still returns 200 (naive check)"
echo "- /readyz endpoint: Should return 503 (dependency-aware)"
echo "- Pod should be removed from service endpoints"

echo -e "\nTo verify, run:"
echo "kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -s localhost:8080/healthz"
echo "kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -s localhost:8080/readyz"
echo "kubectl get endpoints -n $NAMESPACE" 