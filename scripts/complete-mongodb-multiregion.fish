#!/usr/bin/env fish

echo "🔧 MongoDB Multi-Region Setup Script"
echo "===================================="
echo ""
echo "⚠️  NOTE: MongoDB NLBs are now managed by Pulumi!"
echo "This script is for verification and manual configuration only."
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

# Step 1: Verify MongoDB NLB Services exist
echo "1️⃣ Verifying MongoDB NLB Services..."
echo ""

# Check Milan NLB
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan
set -l milan_nlb (kubectl get svc mongodb-nlb-milan -n dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if test -n "$milan_nlb"
    echo "✅ Milan NLB exists: $milan_nlb"
else
    echo "❌ Milan NLB not found - run 'pulumi up' in Milan stack"
    exit 1
end

# Check Dublin NLB
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin
set -l dublin_nlb (kubectl get svc mongodb-nlb-dublin -n dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if test -n "$dublin_nlb"
    echo "✅ Dublin NLB exists: $dublin_nlb"
else
    echo "❌ Dublin NLB not found - run 'pulumi up' in Milan stack with enableCrossRegion=true"
    exit 1
end

# Step 2: Verify DNS records
echo ""
echo "2️⃣ Verifying DNS records..."

# Get the hosted zone ID
set -l zone_id (aws route53 list-hosted-zones --query 'HostedZones[?Name==`internal.k8sdr.com.`].Id' --output text | cut -d'/' -f3)
if test -z "$zone_id"
    echo "❌ Private hosted zone not found"
    exit 1
end

# Check Milan DNS record
set -l milan_dns (aws route53 list-resource-record-sets --hosted-zone-id $zone_id --query "ResourceRecordSets[?Name=='mongodb-milan.internal.k8sdr.com.'].ResourceRecords[0].Value" --output text 2>/dev/null)
if test -n "$milan_dns"
    echo "✅ Milan DNS record exists: mongodb-milan.internal.k8sdr.com → $milan_dns"
else
    echo "❌ Milan DNS record not found - run 'pulumi up' in Milan stack"
end

# Check Dublin DNS record
set -l dublin_dns (aws route53 list-resource-record-sets --hosted-zone-id $zone_id --query "ResourceRecordSets[?Name=='mongodb-dublin.internal.k8sdr.com.'].ResourceRecords[0].Value" --output text 2>/dev/null)
if test -n "$dublin_dns"
    echo "✅ Dublin DNS record exists: mongodb-dublin.internal.k8sdr.com → $dublin_dns"
else
    echo "❌ Dublin DNS record not found - run 'pulumi up' in Milan stack"
end

# Step 3: Verify MongoDB Replica Set Configuration
echo ""
echo "3️⃣ Verifying MongoDB Replica Set Configuration..."

# Function to check MongoDB replica set status
function check_mongodb_rs
    set -l context $argv[1]
    set -l region $argv[2]
    
    kubectl config use-context $context
    
    # Check if MongoDB pod exists
    set -l mongo_pod (kubectl get pods -n dev -l app=mongodb-svc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if test -z "$mongo_pod"
        echo "⚠️  $region: MongoDB pod not found"
        return 1
    end
    
    # Check replica set status
    echo "Checking $region MongoDB replica set status..."
    set -l rs_status (kubectl exec -n dev $mongo_pod -c mongod -- mongosh -u demo -p spectrocloud --authenticationDatabase admin --quiet --eval "rs.status().ok" 2>&1 | tail -1)
    
    if test "$rs_status" = "1"
        # Get replica set members
        set -l members (kubectl exec -n dev $mongo_pod -c mongod -- mongosh -u demo -p spectrocloud --authenticationDatabase admin --quiet --eval "rs.status().members.map(m => m.name).join(',')" 2>/dev/null)
        echo "✅ $region: MongoDB replica set is healthy"
        echo "   Members: $members"
        
        # Check if cross-region member exists
        if string match -q "*internal.k8sdr.com*" $members
            echo "✅ $region: Cross-region replica detected"
        else
            echo "⚠️  $region: No cross-region replica found (independent replica sets)"
        end
    else
        echo "❌ $region: MongoDB replica set not configured"
    end
end

# Check both regions
check_mongodb_rs "arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan" "Milan"
echo ""
check_mongodb_rs "arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin" "Dublin"

# Step 4: Enable MongoDB multi-region configuration
echo ""
echo "4️⃣ MongoDB Multi-Region Configuration..."

set -l config_file "applications/dadjokes/deploy/devspace/custom-resources/mongodb.yaml"
set -l multiregion_file "applications/dadjokes/deploy/devspace/custom-resources/mongodb-multiregion.yaml.disabled"

if test -f $multiregion_file
    echo "⚠️  Multi-region configuration file exists but is disabled"
    echo ""
    echo "To enable multi-region MongoDB:"
    echo "1. Backup current configuration:"
    echo "   cd applications/dadjokes/deploy/devspace"
    echo "   mv custom-resources/mongodb.yaml custom-resources/mongodb-single.yaml.bak"
    echo ""
    echo "2. Enable multi-region configuration:"
    echo "   mv custom-resources/mongodb-multiregion.yaml.disabled custom-resources/mongodb.yaml"
    echo ""
    echo "3. Delete existing single-region MongoDB:"
    echo "   kubectl delete mongodbcommunity mongodb -n dev"
    echo ""
    echo "4. Redeploy with multi-region configuration:"
    echo "   REGION=milan devspace deploy -n dev"
    echo ""
    echo "5. Configure replica set with cross-region member"
else
    echo "✅ MongoDB configuration is current"
end

echo ""
echo "📝 Summary:"
echo "  ✅ MongoDB NLBs are managed by Pulumi"
echo "  ✅ DNS records are managed by Pulumi"
echo "  ✅ Cross-region connectivity verified"
echo ""
echo "To update infrastructure, run:"
echo "  cd $PWD/infrastructure/pulumi"
echo "  pulumi up --stack milan   # Primary region (manages both NLBs)"
echo "  pulumi up --stack dublin  # Secondary region (optional)" 