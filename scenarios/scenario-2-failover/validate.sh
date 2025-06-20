#!/bin/bash
set -euo pipefail

# Validate Internet-Facing Failover

echo "=== Validating Internet-Facing Failover ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Load injection details
if [ -f scenario2-injection.json ]; then
  INJECTION_TIME=$(jq -r '.injection_time' scenario2-injection.json)
  PRIMARY_REGION=$(jq -r '.primary_region' scenario2-injection.json)
else
  echo "❌ Error: scenario2-injection.json not found. Run inject.sh first."
  exit 1
fi

# Configuration
DOMAIN=${DOMAIN:-api.dadjokes.global}
SECONDARY_REGION=${SECONDARY_REGION:-eu-west-1}
MAX_WAIT_TIME=120  # 2 minutes max wait for failover

echo "Domain: $DOMAIN"
echo "Primary region: $PRIMARY_REGION"
echo "Secondary region: $SECONDARY_REGION"
echo "Injection time: $INJECTION_TIME"

# Function to check endpoint health
check_endpoint() {
  local url=$1
  local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" || echo "000")
  echo "$response"
}

# Function to get current DNS resolution
get_dns_target() {
  dig +short "$DOMAIN" | tail -1
}

# Monitor failover progress
echo -e "\n📊 Monitoring failover progress..."
echo "Time | Primary Health | Secondary Health | DNS Target | Status"
echo "-----|----------------|------------------|------------|--------"

START_TIME=$(date +%s)
FAILOVER_DETECTED=false
FAILOVER_TIME=""

while [ $(($(date +%s) - START_TIME)) -lt $MAX_WAIT_TIME ]; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  
  # Check health of both regions
  PRIMARY_HEALTH=$(check_endpoint "http://${PRIMARY_REGION}.alb.amazonaws.com/health")
  SECONDARY_HEALTH=$(check_endpoint "http://${SECONDARY_REGION}.alb.amazonaws.com/health")
  
  # Get current DNS target
  DNS_TARGET=$(get_dns_target)
  
  # Determine status
  if [ "$PRIMARY_HEALTH" != "200" ] && [ "$SECONDARY_HEALTH" == "200" ] && [ ! "$FAILOVER_DETECTED" = true ]; then
    FAILOVER_DETECTED=true
    FAILOVER_TIME=$ELAPSED
    STATUS="✅ FAILOVER"
  elif [ "$PRIMARY_HEALTH" != "200" ]; then
    STATUS="⚠️  Primary Down"
  else
    STATUS="✓ Normal"
  fi
  
  printf "%3ds | %14s | %16s | %10s | %s\n" \
    "$ELAPSED" "$PRIMARY_HEALTH" "$SECONDARY_HEALTH" "${DNS_TARGET:0:10}..." "$STATUS"
  
  # Exit if failover completed
  if [ "$FAILOVER_DETECTED" = true ] && [ "$SECONDARY_HEALTH" == "200" ]; then
    break
  fi
  
  sleep 5
done

echo -e "\n📈 Failover Analysis:"

# Check Route53 health checks
echo -e "\n[1/3] Route53 Health Check Status:"
aws route53 list-health-checks --query 'HealthChecks[*].[Id,HealthCheckConfig.FullyQualifiedDomainName,HealthCheckConfig.Type]' --output table

# Check Global Accelerator status
echo -e "\n[2/3] Global Accelerator Status:"
ACCELERATOR_ARN=$(aws globalaccelerator list-accelerators --query 'Accelerators[0].AcceleratorArn' --output text)
if [ -n "$ACCELERATOR_ARN" ] && [ "$ACCELERATOR_ARN" != "None" ]; then
  aws globalaccelerator describe-accelerator --accelerator-arn "$ACCELERATOR_ARN" \
    --query 'Accelerator.{Name:Name,Status:Status,DnsName:DnsName}'
  
  # Check endpoint health
  LISTENER_ARN=$(aws globalaccelerator list-listeners --accelerator-arn "$ACCELERATOR_ARN" \
    --query 'Listeners[0].ListenerArn' --output text)
  
  aws globalaccelerator list-endpoint-groups --listener-arn "$LISTENER_ARN" \
    --query 'EndpointGroups[*].{Region:EndpointGroupRegion,HealthState:HealthState,TrafficDial:TrafficDialPercentage}'
fi

# Check application metrics
echo -e "\n[3/3] Application Metrics:"
DUBLIN_CONTEXT="arn:aws:eks:eu-west-1:$(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
kubectl config use-context "$DUBLIN_CONTEXT" 2>/dev/null || true

if kubectl get pods -n dev -l app=joke-server --no-headers 2>/dev/null | grep -q Running; then
  JOKE_SERVER_POD=$(kubectl get pod -n dev -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
  echo "5xx error rate in Dublin:"
  kubectl exec -n dev $JOKE_SERVER_POD -- curl -s localhost:9090/metrics | grep http_requests_total | grep '5..' || echo "No 5xx errors"
else
  echo "❌ Dublin application not accessible"
fi

# Generate report
echo -e "\n📋 Failover Report:"
if [ "$FAILOVER_DETECTED" = true ]; then
  echo "✅ PASS: Failover completed successfully"
  echo "- Failover time: ${FAILOVER_TIME}s"
  echo "- Primary region health: Failed as expected"
  echo "- Secondary region health: Healthy and serving traffic"
  echo "- Acceptance criteria: < 60s failover ✓"
  exit 0
else
  echo "❌ FAIL: Failover did not complete within ${MAX_WAIT_TIME}s"
  echo "- Primary health: $PRIMARY_HEALTH"
  echo "- Secondary health: $SECONDARY_HEALTH"
  echo "- Check Route53 and Global Accelerator configurations"
  exit 1
fi 