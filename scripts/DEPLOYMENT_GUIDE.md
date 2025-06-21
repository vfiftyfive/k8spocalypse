# K8spocalypse Scripts - Complete Deployment Guide

## 🎯 Script Organization & Purpose

### Core Scripts Overview

1. **setup.sh** - Initial environment setup (install tools)
2. **deploy-complete-solution.fish** - Deploy infrastructure with Pulumi
3. **deploy-app-with-region.fish** - Deploy applications to specific region
4. **deploy-global-accelerator.fish** - Create AWS Global Accelerator
5. **complete-mongodb-multiregion.fish** - Configure MongoDB for multi-region
6. **check-deployment-status.fish** - Verify current deployment state
7. **verify-dr-readiness.fish** - Final DR readiness check
8. **k8s-dr-helpers.fish** - DR operation functions (source this)
9. **snapshot-management.sh** - EBS snapshot operations

## 📋 Correct Deployment Order

### Phase 1: Initial Setup (One-time only)
```bash
# 1. Install required tools
./scripts/setup.sh
```

### Phase 2: Infrastructure Deployment
```bash
# 2. Deploy both EKS clusters with Pulumi
cd infrastructure/pulumi
pulumi up --stack milan --yes
pulumi up --stack dublin --yes
cd ../..
```

### Phase 3: Application Deployment
```bash
# 3. Deploy applications to both regions
./scripts/deploy-app-with-region.fish milan
./scripts/deploy-app-with-region.fish dublin

# 4. Check deployment status
./scripts/check-deployment-status.fish
```

### Phase 4: Global Accelerator Setup
```bash
# 5. Deploy Global Accelerator (requires ALBs to be ready)
./scripts/deploy-global-accelerator.fish
```

### Phase 5: MongoDB Multi-Region Configuration
```bash
# 6. Verify MongoDB infrastructure (NLBs and DNS are now managed by Pulumi)
./scripts/complete-mongodb-multiregion.fish

# 7. If multi-region MongoDB is needed, enable the configuration:
cd applications/dadjokes/deploy/devspace
mv custom-resources/mongodb.yaml custom-resources/mongodb-single.yaml.bak
mv custom-resources/mongodb-multiregion.yaml.disabled custom-resources/mongodb.yaml

# 8. Delete and redeploy MongoDB:
kubectl delete mongodbcommunity mongodb -n dev
REGION=milan devspace deploy -n dev
cd ../../../..
```

### Phase 6: Final Verification
```bash
# 8. Check final deployment status
./scripts/check-deployment-status.fish

# 9. Verify DR readiness
./scripts/verify-dr-readiness.fish
```

## 🛠️ Daily Operations

### Load DR Helper Functions
```bash
# Source the helper functions
source scripts/k8s-dr-helpers.fish

# Available functions:
dr-help              # Show all available commands
use-milan           # Switch to Milan cluster
use-dublin          # Switch to Dublin cluster
dr-status           # Show detailed cluster status
dr-health           # Quick health check of both regions
dr-backup           # Trigger manual Velero backup
dr-restore          # Restore from backup
dr-snapshot         # Create EBS snapshots
dr-fault <component> # Inject faults (mongodb, redis, etc.)
```

### Common Operations
```bash
# Switch between regions
use-milan
kubectl get pods -n dev

use-dublin
kubectl get pods -n dev

# Check both regions health
dr-health

# Create manual backup
dr-backup my-backup-name

# Check detailed status
dr-status
```

## 🚨 Troubleshooting

### If Scripts Fail

1. **AWS Credentials**
   ```bash
   aws sso login
   yawsso --default-only
   ```

2. **Wrong kubectl context**
   ```bash
   source scripts/k8s-dr-helpers.fish
   use-milan  # or use-dublin
   ```

3. **DevSpace issues**
   ```bash
   cd applications/dadjokes/deploy/devspace
   devspace purge -n dev
   REGION=milan devspace deploy -n dev
   ```

4. **MongoDB not starting**
   - Check if old MongoDB exists: `kubectl get mongodbcommunity -n dev`
   - Delete if needed: `kubectl delete mongodbcommunity mongodb -n dev`
   - Redeploy: `REGION=milan devspace deploy -n dev`

## 📊 Expected Final State

After all scripts complete successfully:

✅ **Infrastructure**
- 2 EKS clusters (Milan & Dublin)
- VPC peering active
- Private hosted zone configured
- CoreDNS patched in both regions

✅ **Applications**
- joke-server, joke-worker running
- MongoDB with multi-region config
- Redis, NATS operational
- Registry deployed

✅ **Load Balancers**
- ALBs for joke-server in both regions
- NLBs for MongoDB cross-region access (managed by Pulumi)
- Global Accelerator with static IPs

✅ **DNS**
- mongodb-milan.internal.k8sdr.com (managed by Pulumi)
- mongodb-dublin.internal.k8sdr.com (managed by Pulumi)

✅ **Backup**
- Velero scheduled backups running
- EBS snapshots configured

## 🧪 Testing the Setup

### Test Global Accelerator
```bash
# Get Global Accelerator DNS
GA_DNS=$(aws globalaccelerator list-accelerators --region us-west-2 --query 'Accelerators[0].DnsName' --output text)
curl http://$GA_DNS/joke
```

### Test Direct ALB Access
```bash
# Milan
MILAN_ALB=$(kubectl get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' --context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan)
curl http://$MILAN_ALB/joke

# Dublin
DUBLIN_ALB=$(kubectl get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' --context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin)
curl http://$DUBLIN_ALB/joke
```

### Test MongoDB Cross-Region
```bash
# From Milan pod
kubectl exec -it mongodb-0 -n dev -c mongod -- mongosh --eval "rs.status()"

# Test DNS resolution
kubectl exec -it nats-box-* -n dev -- nslookup mongodb-dublin.internal.k8sdr.com
```

## 🎮 Ready for Scenarios

Once all checks pass, run disaster recovery scenarios:

```bash
# Scenario 1: Data Loss
cd scenarios/scenario-1-data-loss
./inject.sh
./validate.sh

# Scenario 2: Failover
cd ../scenario-2-failover
./inject.sh
./validate.sh

# Scenario 3: Health Checks
cd ../scenario-3-health-checks
./inject-mongo-network.yaml
./validate.sh
``` 