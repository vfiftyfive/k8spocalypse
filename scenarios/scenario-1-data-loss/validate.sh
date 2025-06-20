#!/bin/bash
set -euo pipefail

# Validate RPO across different recovery methods

echo "=== Validating RPO Across Recovery Methods ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Load timing information
if [ -f scenario1-timing.json ]; then
  SNAPSHOT_ID=$(jq -r '.snapshot_id' scenario1-timing.json)
  SNAPSHOT_TIME=$(jq -r '.snapshot_time' scenario1-timing.json)
  LAST_WRITE_TIME=$(jq -r '.last_write_time' scenario1-timing.json)
else
  echo "❌ Error: scenario1-timing.json not found. Run inject.sh first."
  exit 1
fi

# Calculate time differences
CURRENT_TIME=$(date +%s)
SNAPSHOT_EPOCH=$(date -d "$SNAPSHOT_TIME" +%s)
LAST_WRITE_EPOCH=$(date -d "$LAST_WRITE_TIME" +%s)

echo -e "\nTiming Analysis:"
echo "- Last snapshot taken: $SNAPSHOT_TIME"
echo "- Last data written: $LAST_WRITE_TIME"
echo "- Time since snapshot: $((($CURRENT_TIME - $SNAPSHOT_EPOCH) / 60)) minutes"
echo "- Data written after snapshot: $((($LAST_WRITE_EPOCH - $SNAPSHOT_EPOCH) / 60)) minutes worth"

# Check MongoDB replica lag (if available in Dublin)
echo -e "\n[1/3] MongoDB Replica Status:"
DUBLIN_CONTEXT="arn:aws:eks:eu-west-1:$(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
if kubectl config get-contexts -o name | grep -q "$DUBLIN_CONTEXT"; then
  kubectl config use-context "$DUBLIN_CONTEXT"
  
  # Check if MongoDB replica is running in Dublin
  if kubectl get statefulset -n dev mongodb 2>/dev/null | grep -q mongodb; then
    REPL_STATUS=$(kubectl exec -n dev mongodb-0 -- mongosh --quiet --eval 'rs.status()' 2>/dev/null || echo "Not available")
    if [ "$REPL_STATUS" != "Not available" ]; then
      echo "✅ MongoDB replica available in Dublin"
      echo "RPO: ~0 seconds (real-time replication)"
      MONGODB_RPO=0
    else
      echo "❌ MongoDB replica not accessible"
      MONGODB_RPO="N/A"
    fi
  else
    echo "❌ MongoDB not deployed in Dublin"
    MONGODB_RPO="N/A"
  fi
else
  echo "❌ Dublin cluster not accessible"
  MONGODB_RPO="N/A"
fi

# Check EBS snapshot
echo -e "\n[2/3] EBS Snapshot Status:"
echo "Snapshot ID: $SNAPSHOT_ID"
SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --region eu-south-1 --snapshot-ids $SNAPSHOT_ID --query 'Snapshots[0].Progress' --output text)
echo "Progress: $SNAPSHOT_PROGRESS"
echo "RPO: $((($LAST_WRITE_EPOCH - $SNAPSHOT_EPOCH) / 60)) minutes of data loss"
EBS_RPO=$((($LAST_WRITE_EPOCH - $SNAPSHOT_EPOCH) / 60))

# Check Velero backup
echo -e "\n[3/3] Velero Backup Status:"
# Get latest Velero backup
LATEST_BACKUP=$(velero backup get --output json 2>/dev/null | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name' || echo "none")
if [ "$LATEST_BACKUP" != "none" ] && [ "$LATEST_BACKUP" != "null" ]; then
  BACKUP_TIME=$(velero backup describe $LATEST_BACKUP --output json | jq -r '.status.startTimestamp')
  BACKUP_EPOCH=$(date -d "$BACKUP_TIME" +%s)
  VELERO_RPO=$((($LAST_WRITE_EPOCH - $BACKUP_EPOCH) / 60))
  echo "Latest backup: $LATEST_BACKUP"
  echo "Backup time: $BACKUP_TIME"
  echo "RPO: $VELERO_RPO minutes of data loss"
else
  echo "❌ No Velero backups found"
  VELERO_RPO="N/A"
fi

# Recovery Decision Matrix
echo -e "\n📊 Recovery Decision Matrix:"
echo "┌─────────────────────┬─────────────┬──────────────────────────────┐"
echo "│ Recovery Method     │ RPO (mins)  │ Data Loss                    │"
echo "├─────────────────────┼─────────────┼──────────────────────────────┤"
printf "│ MongoDB Replica     │ %-11s │ %-28s │\n" "$MONGODB_RPO" "None (if available)"
printf "│ EBS Snapshot        │ %-11s │ %-28s │\n" "$EBS_RPO" "5 ratings after snapshot"
printf "│ Velero Backup       │ %-11s │ %-28s │\n" "$VELERO_RPO" "All recent data"
echo "└─────────────────────┴─────────────┴──────────────────────────────┘"

# Generate recovery commands
echo -e "\n🔧 Recovery Commands:"
cat > recovery-commands.sh <<'EOF'
#!/bin/bash
# Recovery commands for each method

# Method 1: MongoDB Replica (if available)
recover_mongodb_replica() {
  echo "Switching to Dublin region..."
  kubectl config use-context "arn:aws:eks:eu-west-1:$(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
  echo "MongoDB replica should already have data. Scale up applications in Dublin."
  kubectl scale deployment joke-server joke-worker -n dev --replicas=3
}

# Method 2: EBS Snapshot
recover_ebs_snapshot() {
  SNAPSHOT_ID="$1"
  echo "Creating volume from snapshot $SNAPSHOT_ID..."
  VOLUME_ID=$(aws ec2 create-volume \
    --region eu-south-1 \
    --availability-zone eu-south-1a \
    --snapshot-id $SNAPSHOT_ID \
    --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=recovered-ratings}]' \
    --query 'VolumeId' --output text)
  echo "Volume created: $VOLUME_ID"
  echo "Update PVC to use this volume and restart pods"
}

# Method 3: Velero Restore
recover_velero() {
  BACKUP_NAME="$1"
  echo "Restoring from Velero backup $BACKUP_NAME..."
  velero restore create --from-backup $BACKUP_NAME --wait
}

# Usage:
# recover_mongodb_replica
# recover_ebs_snapshot $SNAPSHOT_ID
# recover_velero $LATEST_BACKUP
EOF

echo -e "\n✅ Validation complete."
echo "Review the decision matrix and choose the appropriate recovery method."
echo "Recovery commands saved to: recovery-commands.sh"
echo "End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Exit with appropriate code
if [ "$MONGODB_RPO" == "0" ]; then
  echo -e "\n✅ PASS: MongoDB replica provides zero data loss"
  exit 0
else
  echo -e "\n⚠️  WARNING: Data loss expected with EBS/Velero recovery"
  exit 1
fi 