# Scenario 2: Internet-Facing Failover

This scenario demonstrates automatic failover of internet-facing traffic from the primary region (Milan) to the secondary region (Dublin) using Route53 health checks and AWS Global Accelerator.

## Overview

We simulate an application failure in the primary region and verify that:
- Route53 health checks detect the failure within 30 seconds
- Global Accelerator shifts traffic to the healthy secondary region
- Total failover time is under 60 seconds
- 5xx errors vanish once traffic shifts to Dublin

## Prerequisites

- Both Milan and Dublin EKS clusters with DadJokes deployed
- ALB configured in both regions
- Route53 hosted zone configured with health checks
- Global Accelerator configured (optional but recommended)
- `dig` command for DNS resolution testing

## Execution Steps

### 1. Inject Health Check Failure

```bash
./inject.sh
```

This script offers two methods to induce failure:

**Method 1: Application-level failure (Recommended)**
- Uses the `/inject/fault` endpoint to make health checks return 500 errors
- Clean and reversible
- Tests the full health check chain

**Method 2: Network-level failure (Optional)**
- Modifies ALB security group to block traffic
- More disruptive but tests network-layer failures

**Expected output:**
```
=== Scenario 2: Internet-Facing Failover ===
[Method 1] Application-level health check failure
✅ Health check fault injected - will return 500 errors
```

### 2. Validate Failover

```bash
./validate.sh
```

This script:
- Monitors health check status for both regions
- Tracks DNS resolution changes
- Measures failover time
- Validates that traffic shifts to the secondary region

**Expected output:**
```
=== Validating Internet-Facing Failover ===

📊 Monitoring failover progress...
Time | Primary Health | Secondary Health | DNS Target | Status
-----|----------------|------------------|------------|--------
  5s |            500 |              200 | 10.0.1.5... | ⚠️  Primary Down
 10s |            500 |              200 | 10.0.1.5... | ⚠️  Primary Down
 35s |            500 |              200 | 10.1.1.8... | ✅ FAILOVER

📋 Failover Report:
✅ PASS: Failover completed successfully
- Failover time: 35s
- Acceptance criteria: < 60s failover ✓
```

## Manual Testing

### Test DNS Resolution
```bash
# Watch DNS changes
watch -n 5 'dig +short api.dadjokes.global'

# Test endpoint availability
while true; do 
  curl -s -o /dev/null -w "Status: %{http_code} - Time: $(date)\n" https://api.dadjokes.global/health
  sleep 5
done
```

### Check Route53 Health
```bash
# List health checks
aws route53 list-health-checks \
  --query 'HealthChecks[*].[Id,HealthCheckConfig.FullyQualifiedDomainName]' \
  --output table

# Get health check status
aws route53 get-health-check-status --health-check-id <HEALTH_CHECK_ID>
```

### Check Global Accelerator
```bash
# List accelerators
aws globalaccelerator list-accelerators

# Check endpoint health
aws globalaccelerator describe-accelerator \
  --accelerator-arn <ACCELERATOR_ARN> \
  --query 'Accelerator.{Status:Status,DnsName:DnsName}'
```

## Recovery

To restore normal operations after the test:

```bash
# Method 1: Clear application fault
kubectl exec -n dev deployment/joke-server -- \
  curl -X POST http://localhost:8080/inject/restore

# Method 2: Restore security group (if modified)
aws ec2 authorize-security-group-ingress \
  --region eu-south-1 \
  --group-id <ALB_SG> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

## Key Metrics

- **RTO (Recovery Time Objective)**: < 60 seconds
- **Health Check Interval**: 30 seconds
- **Health Check Threshold**: 3 consecutive failures
- **DNS TTL**: 30 seconds

## Troubleshooting

### Failover Not Occurring
1. Verify health check configuration in Route53
2. Check ALB target health in both regions
3. Ensure DNS TTL is set to 30 seconds
4. Verify Global Accelerator endpoint configuration

### Slow Failover
1. Check health check interval settings
2. Verify DNS propagation with multiple DNS servers
3. Check client-side DNS caching

## Acceptance Criteria

- ✅ Primary region health checks fail within 30 seconds
- ✅ DNS resolution switches to secondary region
- ✅ Total failover time < 60 seconds
- ✅ No 5xx errors after failover completes
- ✅ Secondary region handles traffic successfully 