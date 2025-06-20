#!/bin/bash
set -euo pipefail

# Validate health check behavior with dependency failures

echo "=== Validating Health Check Behavior ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

NAMESPACE=${NAMESPACE:-dev}
REGION=${REGION:-eu-south-1}

# Function to check health endpoints
check_health() {
  local pod=$1
  local endpoint=$2
  local response=$(kubectl exec -n $NAMESPACE $pod -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/$endpoint 2>/dev/null || echo "error")
  echo "$response"
}

# Function to get endpoint addresses
get_endpoint_count() {
  local service=$1
  kubectl get endpoints -n $NAMESPACE $service -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w | xargs
}

echo -e "\n📊 Health Check Comparison:"
echo "Pod | /healthz | /readyz | In Endpoints | Status"
echo "----|----------|---------|--------------|--------"

# Check all joke-server pods
for pod in $(kubectl get pods -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[*].metadata.name}'); do
  HEALTHZ=$(check_health $pod "healthz")
  READYZ=$(check_health $pod "readyz")
  
  # Check if pod is in endpoints
  POD_IP=$(kubectl get pod -n $NAMESPACE $pod -o jsonpath='{.status.podIP}')
  IN_ENDPOINTS="No"
  if kubectl get endpoints -n $NAMESPACE joke-server -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q "$POD_IP"; then
    IN_ENDPOINTS="Yes"
  fi
  
  # Determine status
  if [ "$READYZ" == "200" ]; then
    STATUS="✅ Healthy"
  elif [ "$HEALTHZ" == "200" ] && [ "$READYZ" != "200" ]; then
    STATUS="⚠️  Degraded"
  else
    STATUS="❌ Failed"
  fi
  
  printf "%-20s | %8s | %7s | %12s | %s\n" "${pod:0:20}" "$HEALTHZ" "$READYZ" "$IN_ENDPOINTS" "$STATUS"
done

# Check dependency status
echo -e "\n🔍 Dependency Health Checks:"

# MongoDB
MONGO_POD=$(kubectl get pod -n $NAMESPACE -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MONGO_POD" ]; then
  MONGO_STATUS=$(kubectl exec -n $NAMESPACE $MONGO_POD -- mongosh --quiet --eval "db.adminCommand('ping')" 2>/dev/null | grep -q "1" && echo "✅ Healthy" || echo "❌ Failed")
  echo "MongoDB: $MONGO_STATUS"
else
  echo "MongoDB: ❌ Not found"
fi

# Redis
REDIS_POD=$(kubectl get pod -n $NAMESPACE -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$REDIS_POD" ]; then
  REDIS_STATUS=$(kubectl exec -n $NAMESPACE $REDIS_POD -- redis-cli ping 2>/dev/null | grep -q "PONG" && echo "✅ Healthy" || echo "❌ Failed")
  echo "Redis: $REDIS_STATUS"
else
  echo "Redis: ❌ Not found"
fi

# Check Global Accelerator health (if configured)
echo -e "\n🌐 Global Accelerator Health:"
ACCELERATOR_ARN=$(aws globalaccelerator list-accelerators --query 'Accelerators[0].AcceleratorArn' --output text 2>/dev/null || echo "")
if [ -n "$ACCELERATOR_ARN" ] && [ "$ACCELERATOR_ARN" != "None" ]; then
  LISTENER_ARN=$(aws globalaccelerator list-listeners --accelerator-arn "$ACCELERATOR_ARN" --query 'Listeners[0].ListenerArn' --output text)
  
  aws globalaccelerator list-endpoint-groups --listener-arn "$LISTENER_ARN" \
    --query 'EndpointGroups[*].{Region:EndpointGroupRegion,HealthCheckPath:HealthCheckPath,ThresholdCount:ThresholdCount}' \
    --output table
else
  echo "❌ No Global Accelerator configured"
fi

# Check for 5xx errors
echo -e "\n📈 Error Metrics:"
for pod in $(kubectl get pods -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[*].metadata.name}'); do
  echo -n "Pod $pod - 5xx errors: "
  kubectl exec -n $NAMESPACE $pod -- curl -s localhost:9090/metrics 2>/dev/null | grep 'http_requests_total.*status="5' | awk '{sum+=$NF} END {print sum+0}' || echo "0"
done

# Chaos Mesh status (if any experiments running)
echo -e "\n🎭 Active Chaos Experiments:"
kubectl get chaos -n $NAMESPACE 2>/dev/null || echo "No Chaos Mesh experiments active"

# Generate report
echo -e "\n📋 Health Check Analysis:"

# Count healthy vs unhealthy pods
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=joke-server --no-headers | wc -l)
READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)

echo "Total pods: $TOTAL_PODS"
echo "Ready pods: $READY_PODS"
echo "Endpoint members: $(get_endpoint_count joke-server)"

# Acceptance criteria
echo -e "\n✅ Acceptance Criteria:"
if kubectl exec -n $NAMESPACE deployment/joke-server -- curl -s localhost:8080/healthz | grep -q "ok"; then
  echo "✓ /healthz returns 200 even with dependency failures"
else
  echo "✗ /healthz not returning 200"
fi

if kubectl exec -n $NAMESPACE deployment/joke-server -- curl -s -o /dev/null -w "%{http_code}" localhost:8080/readyz | grep -q "503"; then
  echo "✓ /readyz returns 503 with dependency failures"
else
  echo "✗ /readyz not detecting dependency failures"
fi

if [ "$(get_endpoint_count joke-server)" -lt "$TOTAL_PODS" ]; then
  echo "✓ Unhealthy pods removed from endpoints"
else
  echo "✗ All pods still in endpoints despite failures"
fi

echo -e "\nEnd time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 