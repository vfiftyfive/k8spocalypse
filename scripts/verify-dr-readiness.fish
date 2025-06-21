#!/usr/bin/env fish

# Comprehensive DR Readiness Verification Script
# Checks all components mentioned in the README

echo "🔍 K8spocalypse DR Readiness Verification"
echo "========================================="
echo ""

set -l all_good true

# Function to check status
function check_status
    set -l name $argv[1]
    set -l current_status $argv[2]
    set -l expected $argv[3]
    
    if test "$current_status" = "$expected"
        echo "✅ $name: $current_status"
    else
        echo "❌ $name: $current_status (expected: $expected)"
        set all_good false
    end
end

# 1. Check both clusters are accessible
echo "📡 Checking EKS Clusters..."
set milan_status (kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan 2>&1 && echo "Connected" || echo "Failed")
check_status "Milan Cluster" "$milan_status" "Connected"

set dublin_status (kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin 2>&1 && echo "Connected" || echo "Failed")
check_status "Dublin Cluster" "$dublin_status" "Connected"

# 2. Check application deployments in both regions
echo ""
echo "🚀 Checking Application Deployments..."

# Milan
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
set milan_pods (kubectl get pods -n dev --no-headers 2>/dev/null | grep -E "joke-server|joke-worker|mongodb|redis|nats" | grep Running | wc -l | tr -d ' ')
check_status "Milan Pods Running" "$milan_pods pods" "7 pods"

# Dublin
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
set dublin_pods (kubectl get pods -n dev --no-headers 2>/dev/null | grep -E "joke-server|joke-worker|mongodb|redis|nats" | grep Running | wc -l | tr -d ' ')
check_status "Dublin Pods Running" "$dublin_pods pods" "7 pods"

# 3. Check ALB endpoints
echo ""
echo "🌐 Checking ALB Endpoints..."

set milan_alb (kubectl get ingress -n dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' --context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan 2>/dev/null)
if test -n "$milan_alb"
    set milan_health (curl -s -o /dev/null -w "%{http_code}" http://$milan_alb/readyz)
    check_status "Milan ALB Health" "$milan_health" "200"
else
    echo "❌ Milan ALB: Not found"
    set all_good false
end

set dublin_alb (kubectl get ingress -n dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' --context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin 2>/dev/null)
if test -n "$dublin_alb"
    set dublin_health (curl -s -o /dev/null -w "%{http_code}" http://$dublin_alb/readyz)
    check_status "Dublin ALB Health" "$dublin_health" "200"
else
    echo "❌ Dublin ALB: Not found"
    set all_good false
end

# 4. Check MongoDB status (single-region, not cross-region replication)
echo ""
echo "🗄️  Checking MongoDB Status..."

kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
set milan_mongo (kubectl get mongodbcommunity -n dev -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
check_status "Milan MongoDB" "$milan_mongo" "Running"

kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
set dublin_mongo (kubectl get mongodbcommunity -n dev -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
check_status "Dublin MongoDB" "$dublin_mongo" "Running"

# 5. Check Velero backups
echo ""
echo "💾 Checking Velero Backups..."

set velero_backups (kubectl get backups -n velero --no-headers 2>/dev/null | wc -l | tr -d ' ')
if test $velero_backups -gt 0
    check_status "Velero Backups" "$velero_backups backups found" "$velero_backups backups found"
else
    echo "❌ Velero Backups: No backups found"
    set all_good false
end

# 6. Check Global Accelerator
echo ""
echo "🌍 Checking Global Accelerator..."

set ga_count (aws globalaccelerator list-accelerators --query 'Accelerators[?Name==`k8s-dr-accelerator`]' --output json 2>/dev/null | jq length)
if test $ga_count -gt 0
    check_status "Global Accelerator" "Configured" "Configured"
else
    echo "⚠️  Global Accelerator: Not configured (optional)"
end

# 7. Check VPC Peering
echo ""
echo "🔗 Checking VPC Peering..."

set peering_status (aws ec2 describe-vpc-peering-connections --region eu-south-1 --query 'VpcPeeringConnections[?Status.Code==`active`]' --output json 2>/dev/null | jq length)
if test $peering_status -gt 0
    check_status "VPC Peering" "Active" "Active"
else
    echo "❌ VPC Peering: Not active"
    set all_good false
end

# 8. Check REGION environment variable handling
echo ""
echo "🏷️  Checking Region Configuration..."

kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
set milan_region (kubectl get deployment joke-server -n dev -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REGION")].value}' 2>/dev/null)
check_status "Milan Region Config" "$milan_region" "milan"

kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
set dublin_region (kubectl get deployment joke-server -n dev -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REGION")].value}' 2>/dev/null)
check_status "Dublin Region Config" "$dublin_region" "dublin"

# 9. Test REGION variable with DevSpace
echo ""
echo "🔧 Testing DevSpace REGION Variable..."
cd applications/dadjokes/deploy/devspace 2>/dev/null
if test -f devspace.yaml
    # Check if REGION variable is properly configured
    set region_config (grep -A 2 "REGION:" devspace.yaml | grep "source: env" | wc -l | tr -d ' ')
    if test $region_config -eq 1
        echo "✅ DevSpace REGION variable: Configured to use environment"
        echo "   Test command: REGION=milan devspace deploy -n dev"
    else
        echo "❌ DevSpace REGION variable: Not properly configured"
        set all_good false
    end
else
    echo "❌ DevSpace config not found"
    set all_good false
end
cd - >/dev/null 2>&1

# Summary
echo ""
echo "========================================="
if test "$all_good" = "true"
    echo "✅ All DR components are ready!"
    echo ""
    echo "📝 Next Steps:"
    echo "1. Test deployment: REGION=milan devspace deploy -n dev"
    echo "2. Clear DB/cache: ./clear-db-and-cache.fish"
    echo "3. Run DR scenarios in scenarios/ directory"
else
    echo "❌ Some components need attention"
    echo ""
    echo "📝 Fix Required Issues Before Running Scenarios"
end

# Return to original directory
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1 