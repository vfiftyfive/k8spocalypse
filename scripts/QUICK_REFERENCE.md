# K8spocalypse Scripts - Quick Reference

## 🚀 For New Deployments

```bash
# Option 1: Deploy everything automatically
./scripts/deploy-all.fish

# Option 2: Deploy step by step
./scripts/setup.sh                           # Install tools (one-time)
./scripts/deploy-infrastructure.fish         # Deploy EKS clusters
./scripts/deploy-app-with-region.fish milan  # Deploy apps to Milan
./scripts/deploy-app-with-region.fish dublin # Deploy apps to Dublin
./scripts/deploy-global-accelerator.fish     # Create Global Accelerator
./scripts/complete-mongodb-multiregion.fish  # Configure MongoDB
```

## 📊 Status Checks

```bash
# Quick status check
./scripts/check-deployment-status.fish

# Comprehensive DR readiness check
./scripts/verify-dr-readiness.fish

# Load helper functions for detailed checks
source scripts/k8s-dr-helpers.fish
dr-health  # Quick health check
dr-status  # Detailed status
```

## 🔧 Daily Operations

```bash
# Load helper functions first
source scripts/k8s-dr-helpers.fish

# Switch between regions
use-milan
use-dublin

# Common operations
dr-backup my-backup         # Create backup
dr-restore my-backup        # Restore from backup
dr-snapshot                 # Create EBS snapshots
dr-fault mongodb            # Inject fault
dr-list-backups            # List all backups
```

## 🚨 Troubleshooting

```bash
# AWS credentials expired
aws sso login
yawsso --default-only

# Check what's deployed
./scripts/check-deployment-status.fish

# Redeploy applications
cd applications/dadjokes/deploy/devspace
devspace purge -n dev
REGION=milan devspace deploy -n dev
```

## 📝 Script Purposes

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `setup.sh` | Install tools | Once, before first deployment |
| `deploy-infrastructure.fish` | Deploy EKS clusters | New infrastructure deployment |
| `deploy-app-with-region.fish` | Deploy applications | After infrastructure is ready |
| `deploy-global-accelerator.fish` | Create Global Accelerator | After ALBs are ready |
| `complete-mongodb-multiregion.fish` | Configure MongoDB multi-region | After apps are deployed |
| `check-deployment-status.fish` | Check current state | Anytime to verify status |
| `verify-dr-readiness.fish` | Final DR check | Before running scenarios |
| `k8s-dr-helpers.fish` | DR operations | Source for daily operations |
| `deploy-all.fish` | Complete deployment | New full deployment |

## 🎯 Current Status

Based on your deployment:
- ✅ Infrastructure: Deployed
- ✅ Applications: Running
- ✅ ALBs: Working
- ✅ Global Accelerator: Deployed
- ✅ CoreDNS: Configured
- ✅ Velero: v1.16.1
- ❌ MongoDB Multi-Region: Pending
- ❌ MongoDB NLBs: Not created

## 🚀 Next Steps

1. Complete MongoDB multi-region:
   ```bash
   ./scripts/complete-mongodb-multiregion.fish
   ```

2. After script completes, redeploy MongoDB:
   ```bash
   kubectl delete mongodbcommunity mongodb -n dev
   cd applications/dadjokes/deploy/devspace
   REGION=milan devspace deploy -n dev
   ```

3. Verify everything:
   ```bash
   ./scripts/check-deployment-status.fish
   ```

4. Test the setup:
   ```bash
   # Test Global Accelerator
   curl http://ab21a9efe84ecf5a8.awsglobalaccelerator.com/joke
   ``` 