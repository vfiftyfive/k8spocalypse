# Multi-Region Kubernetes Disaster Recovery Infrastructure

This Pulumi TypeScript project sets up a complete multi-region disaster recovery infrastructure for a stateful microservice (DadJokes app with MongoDB) across AWS regions eu-west-1 (Dublin) and eu-south-1 (Milan).

## Features

### 🌐 DNS Failover with Route53
- Public hosted zone with automatic failover routing
- Primary region: eu-west-1 (Dublin)
- Secondary region: eu-south-1 (Milan)
- Health checks on `/health` endpoint (30-second TTL)

### 🚀 Global Accelerator
- Static anycast IP addresses
- Automatic traffic failover
- Health-check based routing
- Listeners on ports 80 and 443

### 💾 EBS Snapshot Automation
- Automated snapshots every 6 hours
- 7-day retention policy
- Cross-region replication
- DLM (Data Lifecycle Manager) policies

### 🛡️ Velero Backup Integration
- S3-backed cluster backups
- Scheduled backups every 6 hours
- Namespace and label-based selection
- Cross-region restore capability

### ⚙️ AWS Load Balancer Controller
- Automatic ALB provisioning
- Ingress controller support
- Target group management

## Prerequisites

- AWS CLI configured with appropriate credentials
- Pulumi CLI installed
- Node.js 18+ and npm
- kubectl configured
- Domain name for Route53 (optional)

## Installation

1. Install dependencies:
```bash
npm install
```

2. Configure AWS credentials:
```bash
aws configure --profile k8s-dr
export AWS_PROFILE=k8s-dr
```

3. Initialize Pulumi stacks:
```bash
# Milan (Primary)
pulumi stack init milan --secrets-provider=passphrase
pulumi config set aws:region eu-south-1 --stack milan
pulumi config set projectName k8s-dr --stack milan
pulumi config set environment milan --stack milan
pulumi config set vpcCidr 10.0.0.0/16 --stack milan
pulumi config set clusterName k8s-dr-milan --stack milan
pulumi config set nodeInstanceType t3.large --stack milan
pulumi config set desiredCapacity 3 --stack milan
pulumi config set minSize 1 --stack milan
pulumi config set maxSize 5 --stack milan

# Dublin (Secondary)
pulumi stack init dublin --secrets-provider=passphrase
pulumi config set aws:region eu-west-1 --stack dublin
pulumi config set projectName k8s-dr --stack dublin
pulumi config set environment dublin --stack dublin
pulumi config set vpcCidr 10.1.0.0/16 --stack dublin
pulumi config set clusterName k8s-dr-dublin --stack dublin
pulumi config set nodeInstanceType t3.large --stack dublin
pulumi config set desiredCapacity 3 --stack dublin
pulumi config set minSize 1 --stack dublin
pulumi config set maxSize 5 --stack dublin
```

## Deployment

### Deploy Milan (Primary) Region

```bash
pulumi stack select milan
pulumi up
```

### Deploy Dublin (Secondary) Region

```bash
pulumi stack select dublin
pulumi up
```

### Configure Cross-Region Components

After both regions are deployed, configure DNS and Global Accelerator:

```bash
# Add to your main index.ts after getting ALB outputs from both regions
```

## Verification Commands

### Check EKS Cluster Access
```bash
# Milan
aws eks update-kubeconfig --region eu-south-1 --name k8s-dr-milan
kubectl get nodes

# Dublin
aws eks update-kubeconfig --region eu-west-1 --name k8s-dr-dublin
kubectl get nodes
```

### Verify AWS Load Balancer Controller
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Check Velero Installation
```bash
kubectl get pods -n velero
velero backup-location get
velero schedule get
```

### Verify EBS Snapshots
```bash
# List DLM policies
aws dlm get-lifecycle-policies --region eu-south-1

# List snapshots
aws ec2 describe-snapshots --region eu-south-1 --owner-ids self \
  --filters "Name=tag:Type,Values=DLM-Snapshot"
```

### Test DNS Failover
```bash
# Check Route53 health checks
aws route53 list-health-checks

# Test DNS resolution
dig dadjokes.app
```

### Global Accelerator Status
```bash
# List accelerators
aws globalaccelerator list-accelerators

# Get accelerator details
aws globalaccelerator describe-accelerator --accelerator-arn <ARN>
```

## Backup and Restore

### Manual Velero Backup
```bash
velero backup create manual-backup --include-namespaces dev
```

### Restore from Backup
```bash
# List backups
velero backup get

# Restore
velero restore create --from-backup manual-backup
```

### EBS Snapshot Restore
```bash
# List snapshots
aws ec2 describe-snapshots --region eu-south-1 \
  --filters "Name=tag:app,Values=dadjokes-db"

# Create volume from snapshot
aws ec2 create-volume --region eu-south-1 \
  --snapshot-id snap-xxxxx \
  --availability-zone eu-south-1a
```

## Disaster Recovery Procedures

### Failover to Secondary Region

1. **Automatic Failover**: Route53 and Global Accelerator will automatically route traffic when health checks fail

2. **Manual Failover**: Update Route53 weighted routing or Global Accelerator traffic dial

3. **Data Recovery**:
   - Option 1: Restore from Velero backup
   - Option 2: Restore from EBS snapshot
   - Option 3: Use MongoDB replica (if configured)

## Resource Outputs

After deployment, Pulumi will output:

- VPC IDs and subnet IDs
- EKS cluster endpoints and names
- ALB DNS names and ARNs
- Velero bucket names
- IAM role ARNs
- Route53 hosted zone ID
- Global Accelerator IPs and DNS

## Cost Optimization

- Use spot instances for non-critical workloads
- Adjust snapshot retention policies
- Configure S3 lifecycle policies
- Use single NAT gateway per region for dev/test

## Troubleshooting

### EKS Add-on Issues
```bash
aws eks describe-addon --cluster-name k8s-dr-milan --addon-name vpc-cni
```

### Velero Backup Failures
```bash
velero backup logs <backup-name>
kubectl logs -n velero deployment/velero
```

### ALB Controller Issues
```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

## Clean Up

To destroy resources:

```bash
# Dublin
pulumi stack select dublin
pulumi destroy

# Milan
pulumi stack select milan
pulumi destroy
```

**Note**: Ensure all LoadBalancers created by Kubernetes are deleted before destroying the infrastructure. 