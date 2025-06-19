# Troubleshooting Guide

## Common Deployment Issues

### VPC Endpoint Errors

**Error**: `InvalidRouteTableId.Malformed: Invalid Id: 'subnet-xxx'`

**Cause**: The S3 VPC endpoint is trying to use subnet IDs instead of route table IDs.

**Solution**: Fixed in the networking component to properly query route table IDs.

### AWS Credentials Issues

**Error**: `Invalid credentials configured`

**Solutions**:
1. For AWS SSO:
   ```bash
   aws sso login
   yawsso
   ```

2. Set AWS profile:
   ```bash
   set -x AWS_PROFILE "your-profile"
   pulumi config set aws:profile your-profile -s milan
   ```

### gRPC Connection Errors

**Error**: `Channel has been shut down` or `connection refused`

**Cause**: Usually happens when Pulumi process crashes or times out.

**Solutions**:
1. Clean up and retry:
   ```bash
   pulumi cancel -s milan
   pulumi refresh -s milan
   pulumi up -s milan
   ```

2. If persistent, try with verbose logging:
   ```bash
   pulumi up -s milan --logtostderr -v=9 2> pulumi-debug.log
   ```

### EKS Node Group Issues

**Error**: Nodes not joining cluster

**Common Causes**:
1. Security group rules blocking communication
2. IAM role missing required policies
3. Subnet routing issues

**Debugging Steps**:
```bash
# Check node group status
aws eks describe-nodegroup --cluster-name k8s-dr-milan --nodegroup-name k8s-dr-milan-nodes --region eu-south-1

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=k8s-dr-milan" --region eu-south-1

# Check system logs (if using SSM)
aws ssm start-session --target i-xxxxx --region eu-south-1
```

### Storage Class Issues

**Error**: EBS CSI driver not working

**Check**:
```bash
# Verify addon status
aws eks describe-addon --cluster-name k8s-dr-milan --addon-name aws-ebs-csi-driver --region eu-south-1

# Check pods
kubectl get pods -n kube-system | grep ebs-csi

# Check IRSA
kubectl describe sa ebs-csi-controller-sa -n kube-system
```

### Region-Specific Issues

**Error**: Service not available in region

**Common Services Not Available in All Regions**:
- Some instance types
- Certain EKS addon versions
- Specific VPC endpoint services

**Solution**: Check service availability:
```bash
# Check instance types
aws ec2 describe-instance-types --filters "Name=instance-type,Values=t3.large" --region eu-south-1

# Check EKS addon versions
aws eks describe-addon-versions --addon-name aws-ebs-csi-driver --region eu-south-1
```

## Recovery Procedures

### Failed Deployment Recovery

1. **Cancel any running operations**:
   ```bash
   pulumi cancel -s milan
   ```

2. **Refresh state**:
   ```bash
   pulumi refresh -s milan
   ```

3. **Check what exists**:
   ```bash
   pulumi stack export -s milan > milan-state.json
   ```

4. **Retry deployment**:
   ```bash
   pulumi up -s milan
   ```

### Partial Deployment Cleanup

If you need to start over:

```bash
# Destroy everything
pulumi destroy -s milan

# Or destroy specific resources
pulumi destroy -s milan --target "awsx:ec2:Vpc::main-vpc"
```

## Useful Commands

### State Management
```bash
# View current state
pulumi stack -s milan

# View detailed outputs
pulumi stack output --show-secrets -s milan

# Export state for backup
pulumi stack export -s milan > backup-milan-$(date +%Y%m%d).json
```

### AWS Debugging
```bash
# Check CloudFormation stacks (if any)
aws cloudformation list-stacks --region eu-south-1

# Check CloudTrail for API errors
aws cloudtrail lookup-events --region eu-south-1 --max-results 10

# Check VPC resources
aws ec2 describe-vpcs --region eu-south-1 --filters "Name=tag:Project,Values=k8s-multi-region-dr"
``` 