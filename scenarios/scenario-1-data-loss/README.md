# Scenario 1: Stale Data / Multi-Layer RPO Paradox

This scenario demonstrates the different Recovery Point Objectives (RPO) across multiple backup strategies and helps teams understand the trade-offs between data freshness and recovery complexity.

## Overview

We simulate a catastrophic failure in Milan (primary region) after creating new data, then compare recovery options:
- **MongoDB Replica**: RPO ≈ 0 seconds (if configured)
- **EBS Snapshot**: RPO ≈ 5-10 minutes (snapshot lag)
- **Velero Backup**: RPO ≈ 4-6 hours (scheduled backup interval)

## Prerequisites

- Both Milan and Dublin EKS clusters deployed
- DadJokes application running in Milan
- AWS CLI and kubectl configured
- jq installed for JSON parsing
- Appropriate IAM permissions for EBS snapshots

## Execution Steps

### 1. Inject Test Data

```bash
./inject.sh
```

This script:
- Creates initial rating in MongoDB
- Triggers a manual EBS snapshot
- Waits for snapshot completion
- Creates 5 additional ratings AFTER the snapshot
- Records timing information in `scenario1-timing.json`

**Expected output:**
```
=== Scenario 1: Stale Data / RPO Paradox ===
[1/5] Creating initial rating in MongoDB...
[2/5] Triggering manual EBS snapshot...
[3/5] Creating post-snapshot ratings (will be lost in EBS restore)...
[4/5] Current data state before failure...
[5/5] Recording timing information...
✅ Injection complete. Ready to simulate Milan failure.
```

### 2. Simulate Milan Failure

```bash
./fail-milan.sh
```

This script:
- Injects application-level fault via `/inject/fault` endpoint
- Scales down all deployments and statefulsets to 0
- Waits for all pods to terminate

**Expected output:**
```
=== Simulating Milan Region Failure ===
[1/3] Injecting application fault...
[2/3] Scaling down Milan workloads...
[3/3] Waiting for pods to terminate...
✅ Milan region failure simulation complete.
```

### 3. Validate Recovery Options

```bash
./validate.sh
```

This script:
- Analyzes timing differences between backups
- Checks MongoDB replica status in Dublin
- Calculates RPO for each recovery method
- Generates a recovery decision matrix
- Creates `recovery-commands.sh` with specific recovery procedures

**Expected output:**
```
=== Validating RPO Across Recovery Methods ===

📊 Recovery Decision Matrix:
┌─────────────────────┬─────────────┬──────────────────────────────┐
│ Recovery Method     │ RPO (mins)  │ Data Loss                    │
├─────────────────────┼─────────────┼──────────────────────────────┤
│ MongoDB Replica     │ 0           │ None (if available)          │
│ EBS Snapshot        │ 5           │ 5 ratings after snapshot     │
│ Velero Backup       │ 240         │ All recent data              │
└─────────────────────┴─────────────┴──────────────────────────────┘
```

## Recovery Procedures

Based on the validation results, choose your recovery method:

### Option 1: MongoDB Replica (Preferred - Zero Data Loss)
```bash
# Switch to Dublin
kubectl config use-context "arn:aws:eks:eu-west-1:$(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"

# Scale up applications
kubectl scale deployment joke-server joke-worker -n dev --replicas=3
```

### Option 2: EBS Snapshot (5-10 minutes data loss)
```bash
# Create volume from snapshot
VOLUME_ID=$(aws ec2 create-volume \
  --region eu-south-1 \
  --availability-zone eu-south-1a \
  --snapshot-id <SNAPSHOT_ID> \
  --query 'VolumeId' --output text)

# Update PVC and restart pods
# Note: Requires manual PV/PVC reconfiguration
```

### Option 3: Velero Restore (4-6 hours data loss)
```bash
# List available backups
velero backup get

# Restore from backup
velero restore create --from-backup <BACKUP_NAME> --wait
```

## Key Learnings

1. **RPO Varies by Method**: Different backup strategies have vastly different RPOs
2. **Cost vs. Recovery Time**: MongoDB replicas cost more but provide instant recovery
3. **Automation Matters**: Manual snapshots can reduce RPO but require automation
4. **Testing is Critical**: Regular DR testing reveals gaps in backup strategies

## Cleanup

To reset the environment after the scenario:

```bash
# Scale Milan back up
kubectl config use-context "arn:aws:eks:eu-south-1:$(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
kubectl scale deployment joke-server joke-worker -n dev --replicas=3
kubectl scale statefulset mongodb redis -n dev --replicas=1

# Remove test data
rm -f scenario1-timing.json recovery-commands.sh
```

## Acceptance Criteria

- ✅ Successfully demonstrate different RPOs across backup methods
- ✅ Validate that post-snapshot data is lost with EBS restore
- ✅ Show MongoDB replica has zero data loss (if configured)
- ✅ Generate clear decision matrix for recovery options
- ✅ Provide executable recovery commands 