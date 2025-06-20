#!/bin/bash
set -euo pipefail

# Scenario 1: Stale Data / Multi-Layer RPO Paradox
# This script injects last-minute data changes before simulating Milan failure

echo "=== Scenario 1: Stale Data / RPO Paradox ==="
echo "Start time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Set environment
REGION=${REGION:-eu-south-1}
CLUSTER=${CLUSTER:-k8s-dr-milan}
NAMESPACE=${NAMESPACE:-dev}

echo "Target region: $REGION"
echo "Target cluster: $CLUSTER"

# Ensure we're in the right context
kubectl config use-context "arn:aws:eks:${REGION}:$(aws sts get-caller-identity --query Account --output text):cluster/${CLUSTER}"

# Step 1: Create initial data point
echo -e "\n[1/5] Creating initial rating in MongoDB..."
JOKE_SERVER_POD=$(kubectl get pod -n $NAMESPACE -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
INITIAL_RATING=$(kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -s -X POST http://localhost:8080/rating \
  -H "Content-Type: application/json" \
  -d '{"jokeId": "test-joke-001", "rating": 5, "comment": "Initial rating before snapshot"}')
echo "Initial rating created: $INITIAL_RATING"

# Step 2: Force an EBS snapshot (manual trigger)
echo -e "\n[2/5] Triggering manual EBS snapshot..."
VOLUME_ID=$(kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.name=="ratings-pvc") | .spec.csi.volumeHandle')
SNAPSHOT_ID=$(aws ec2 create-snapshot --region $REGION --volume-id $VOLUME_ID \
  --description "Manual snapshot before fault injection" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Type,Value=Manual-DR-Test},{Key=Scenario,Value=stale-data}]" \
  --query 'SnapshotId' --output text)
echo "Snapshot initiated: $SNAPSHOT_ID"

# Wait for snapshot to complete
echo "Waiting for snapshot to complete..."
aws ec2 wait snapshot-completed --region $REGION --snapshot-ids $SNAPSHOT_ID
echo "Snapshot completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Step 3: Create additional ratings AFTER snapshot (these will be lost with EBS restore)
echo -e "\n[3/5] Creating post-snapshot ratings (will be lost in EBS restore)..."
for i in {1..5}; do
  kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -s -X POST http://localhost:8080/rating \
    -H "Content-Type: application/json" \
    -d "{\"jokeId\": \"test-joke-00$i\", \"rating\": $i, \"comment\": \"Rating $i - Created AFTER snapshot at $(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > /dev/null
  echo "Created rating $i (after snapshot)"
  sleep 2
done

# Step 4: Get current data state
echo -e "\n[4/5] Current data state before failure:"
echo "MongoDB document count:"
kubectl exec -n $NAMESPACE deployment/mongodb -- mongosh --quiet --eval 'db.ratings.countDocuments()'

echo "Latest ratings:"
kubectl exec -n $NAMESPACE $JOKE_SERVER_POD -- curl -s http://localhost:8080/ratings/top | jq '.[0:3]'

# Step 5: Record timing information
echo -e "\n[5/5] Recording timing information..."
cat > scenario1-timing.json <<EOF
{
  "scenario": "stale-data",
  "snapshot_id": "$SNAPSHOT_ID",
  "snapshot_time": "$(aws ec2 describe-snapshots --region $REGION --snapshot-ids $SNAPSHOT_ID --query 'Snapshots[0].StartTime' --output text)",
  "last_write_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data_created_after_snapshot": 5,
  "expected_data_loss": "5 ratings created after snapshot"
}
EOF

echo -e "\n✅ Injection complete. Ready to simulate Milan failure."
echo "Run ./fail-milan.sh to proceed with the failure simulation."
echo "End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 