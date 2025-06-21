#!/usr/bin/env fish

echo "🔧 MongoDB Cross-Region Replica Set Configuration"
echo "================================================"
echo ""

# Function to check command success
function check_status
    if test $status -eq 0
        echo "✅ $argv[1]"
        return 0
    else
        echo "❌ $argv[1] - Failed"
        return 1
    end
end

# Step 1: Initialize replica set in Milan (primary)
echo "1️⃣ Initializing replica set in Milan..."
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan

# Get Milan MongoDB pod
set -l milan_pod (kubectl get pods -n dev -l app=mongodb-svc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if test -z "$milan_pod"
    echo "❌ Milan MongoDB pod not found"
    exit 1
end

# Initialize replica set with external hostname
echo "Initializing replica set on $milan_pod..."
kubectl exec -n dev $milan_pod -c mongod -- mongosh -u demo -p spectrocloud --authenticationDatabase admin --quiet --eval "
rs.initiate({
  _id: 'mongodb',
  members: [
    {
      _id: 0,
      host: 'mongodb-0.mongodb-svc.dev.svc.cluster.local:27017',
      priority: 2
    }
  ]
})
" 2>/dev/null
check_status "Milan replica set initialized"

# Wait for primary to be ready
echo "Waiting for primary to be ready..."
sleep 10

# Step 2: Add Dublin as secondary member
echo ""
echo "2️⃣ Adding Dublin as secondary member..."

# Add Dublin member using cross-region DNS
kubectl exec -n dev $milan_pod -c mongod -- mongosh -u demo -p spectrocloud --authenticationDatabase admin --quiet --eval "
rs.add({
  host: 'mongodb-dublin.internal.k8sdr.com:27017',
  priority: 1,
  votes: 1
})
" 2>/dev/null
check_status "Dublin member added to replica set"

# Step 3: Verify replica set status
echo ""
echo "3️⃣ Verifying replica set configuration..."
sleep 5

kubectl exec -n dev $milan_pod -c mongod -- mongosh -u demo -p spectrocloud --authenticationDatabase admin --quiet --eval "rs.status()" | grep -E "(name|stateStr|health)" | head -20

echo ""
echo "📝 Configuration Summary:"
echo "  • Milan: Primary (priority 2)"
echo "  • Dublin: Secondary (priority 1)"
echo "  • Replica set name: mongodb"
echo ""
echo "To verify cross-region replication:"
echo "  1. Insert data in Milan:"
echo "     kubectl exec -it $milan_pod -n dev -c mongod -- mongosh"
echo "     use test"
echo "     db.messages.insertOne({message: 'Hello from Milan', timestamp: new Date()})"
echo ""
echo "  2. Check replication in Dublin:"
echo "     kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin"
echo "     kubectl exec -it mongodb-0 -n dev -c mongod -- mongosh"
echo "     use test"
echo "     db.messages.find()" 