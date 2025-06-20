#!/bin/bash
set -euo pipefail

# Inject Redis OOM (Out of Memory) condition

echo "=== Injecting Redis OOM Condition ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

NAMESPACE=${NAMESPACE:-dev}
JOKE_SERVER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[0].metadata.name}')

if [ -z "$JOKE_SERVER_POD" ]; then
  echo "❌ No joke-server pod found"
  exit 1
fi

echo "Target pod: $JOKE_SERVER_POD"

# Inject Redis OOM fault
echo "Injecting Redis OOM condition..."
kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -X POST http://localhost:8080/inject/fault \
  -H "Content-Type: application/json" \
  -d '{
    "component": "redis",
    "failureMode": "oom",
    "duration": "5m",
    "details": {
      "message": "OOM command not allowed when used memory > maxmemory"
    }
  }'

echo -e "\n✅ Redis OOM condition injected"
echo "Expected behavior:"
echo "- /healthz endpoint: Still returns 200 (naive check)"
echo "- /readyz endpoint: Should return 503 (dependency-aware)"
echo "- Cache operations will fail with OOM errors"

# Alternative: Use Chaos Mesh for real memory pressure
echo -e "\n💡 Alternative: Apply real memory pressure with Chaos Mesh:"
echo "kubectl apply -f inject-redis-stress.yaml" 