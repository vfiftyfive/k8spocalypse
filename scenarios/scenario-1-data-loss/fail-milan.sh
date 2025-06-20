#!/bin/bash
set -euo pipefail

# Simulate Milan region failure

echo "=== Simulating Milan Region Failure ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Set environment
REGION=${REGION:-eu-south-1}
CLUSTER=${CLUSTER:-k8s-dr-milan}
NAMESPACE=${NAMESPACE:-dev}

# Step 1: Inject fault via our endpoint (graceful app failure)
echo -e "\n[1/3] Injecting application fault..."
JOKE_SERVER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -X POST http://localhost:8080/inject/fault \
  -H "Content-Type: application/json" \
  -d '{"component": "all", "duration": "permanent"}'

# Step 2: Scale down all workloads to simulate complete failure
echo -e "\n[2/3] Scaling down Milan workloads..."
kubectl scale deployment --all -n $NAMESPACE --replicas=0
kubectl scale statefulset --all -n $NAMESPACE --replicas=0

# Step 3: Wait for pods to terminate
echo -e "\n[3/3] Waiting for pods to terminate..."
while kubectl get pods -n $NAMESPACE --no-headers | grep -v Completed | grep -q .; do
  echo "Pods still terminating..."
  kubectl get pods -n $NAMESPACE --no-headers | grep -v Completed
  sleep 5
done

echo -e "\n✅ Milan region failure simulation complete."
echo "All workloads have been terminated."
echo "End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Show current state
echo -e "\nCurrent state:"
echo "Pods in $NAMESPACE namespace:"
kubectl get pods -n $NAMESPACE

echo -e "\nNext steps:"
echo "1. Run ./validate.sh to check RPO across different recovery methods"
echo "2. Choose recovery method based on RPO requirements"
echo "3. Execute recovery using the appropriate method" 