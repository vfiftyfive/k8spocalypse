#!/bin/bash
set -euo pipefail

# Scenario 2: Internet-Facing Failover
# This script induces ALB health check failures to trigger failover

echo "=== Scenario 2: Internet-Facing Failover ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Set environment
REGION=${REGION:-eu-south-1}
CLUSTER=${CLUSTER:-k8s-dr-milan}
NAMESPACE=${NAMESPACE:-dev}
ALB_NAME=${ALB_NAME:-k8s-dr-milan-alb}

echo "Target region: $REGION"
echo "Target cluster: $CLUSTER"

# Ensure we're in the right context
kubectl config use-context "arn:aws:eks:${REGION}:$(aws sts get-caller-identity --query Account --output text):cluster/${CLUSTER}"

# Method 1: Application-level failure injection
echo -e "\n[Method 1] Application-level health check failure"
echo "Injecting fault via DadJokes /inject/fault endpoint..."

JOKE_SERVER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
if [ -n "$JOKE_SERVER_POD" ]; then
  kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -X POST http://localhost:8080/inject/fault \
    -H "Content-Type: application/json" \
    -d '{"component": "health", "duration": "10m", "failureMode": "500"}'
  echo "✅ Health check fault injected - will return 500 errors"
else
  echo "❌ No joke-server pod found"
fi

# Method 2: Network-level failure (Security Group)
echo -e "\n[Method 2] Network-level failure (optional)"
echo "To simulate network failure, modify ALB security group:"

# Get ALB security groups
ALB_ARN=$(aws elbv2 describe-load-balancers --region $REGION \
  --query "LoadBalancers[?contains(LoadBalancerName, '$ALB_NAME')].LoadBalancerArn" \
  --output text)

if [ -n "$ALB_ARN" ]; then
  ALB_SG=$(aws elbv2 describe-load-balancers --region $REGION \
    --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].SecurityGroups[0]' --output text)
  
  echo "ALB Security Group: $ALB_SG"
  echo "To black-hole traffic, run:"
  echo "aws ec2 revoke-security-group-ingress --region $REGION --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0"
else
  echo "❌ ALB not found"
fi

# Record injection details
cat > scenario2-injection.json <<EOF
{
  "scenario": "internet-facing-failover",
  "injection_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "method": "application-health-failure",
  "expected_failover_time": "30-60 seconds",
  "primary_region": "$REGION",
  "alb_arn": "$ALB_ARN"
}
EOF

echo -e "\n📊 Monitoring failover:"
echo "1. Check Route53 health checks:"
echo "   aws route53 list-health-checks --query 'HealthChecks[?HealthCheckConfig.FullyQualifiedDomainName==\`$ALB_NAME\`]'"
echo ""
echo "2. Check Global Accelerator health:"
echo "   aws globalaccelerator list-accelerators"
echo ""
echo "3. Monitor application availability:"
echo "   while true; do curl -s -o /dev/null -w '%{http_code}' https://api.dadjokes.global/health; echo; sleep 5; done"

echo -e "\n✅ Injection complete. Health checks should start failing within 30 seconds."
echo "Run ./validate.sh to monitor failover progress."
echo "End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 