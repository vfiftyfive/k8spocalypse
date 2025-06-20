#!/bin/bash
set -euo pipefail

# Inject OpenAI API 429 (Rate Limit) errors

echo "=== Injecting OpenAI API Rate Limit (429) Errors ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

NAMESPACE=${NAMESPACE:-dev}
JOKE_WORKER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-worker -o jsonpath='{.items[0].metadata.name}')

if [ -z "$JOKE_WORKER_POD" ]; then
  echo "❌ No joke-worker pod found"
  exit 1
fi

echo "Target pod: $JOKE_WORKER_POD"

# Inject OpenAI 429 fault
echo "Injecting OpenAI rate limit errors..."
kubectl exec -n $NAMESPACE $JOKE_WORKER_POD -- curl -X POST http://localhost:8080/inject/fault \
  -H "Content-Type: application/json" \
  -d '{
    "component": "openai",
    "failureMode": "rate-limit",
    "duration": "5m",
    "details": {
      "statusCode": 429,
      "message": "Rate limit exceeded. Please try again later.",
      "retryAfter": 60
    }
  }'

echo -e "\n✅ OpenAI rate limit errors injected"
echo "Expected behavior:"
echo "- Joke generation will fail with 429 errors"
echo "- Worker should implement exponential backoff"
echo "- /readyz should detect OpenAI unavailability"

# Alternative: Use Chaos Mesh for DNS failures
echo -e "\n💡 Alternative: Block OpenAI at DNS level with Chaos Mesh:"
echo "kubectl apply -f inject-openai-dns.yaml" 