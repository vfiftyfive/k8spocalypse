#!/usr/bin/env fish

# Master deployment script for K8spocalypse
# This script runs all deployment steps in the correct order

echo "🚀 K8spocalypse Complete Deployment"
echo "==================================="
echo ""
echo "This script will:"
echo "  1. Deploy infrastructure (EKS clusters, networking, etc.)"
echo "  2. Deploy applications to both regions"
echo "  3. Configure Global Accelerator"
echo "  4. Set up MongoDB multi-region"
echo "  5. Verify everything is working"
echo ""
echo "Total estimated time: 45-60 minutes"
echo ""
echo -n "Continue? (y/N): "
read -l response
if test "$response" != "y"
    echo "Deployment cancelled."
    exit 0
end

# Function to run a step
function run_step
    set -l step_name $argv[1]
    set -l command $argv[2..-1]
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶️  $step_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    eval $command
    if test $status -ne 0
        echo ""
        echo "❌ Step failed: $step_name"
        echo "Please fix the issue and run the failed command manually:"
        echo "   $command"
        exit 1
    end
    
    echo ""
    echo "✅ $step_name completed successfully"
end

# Start deployment
set -l start_time (date +%s)

# Step 1: Deploy infrastructure
run_step "Deploy Infrastructure" "./scripts/deploy-infrastructure.fish"

# Step 2: Deploy applications to Milan
run_step "Deploy Applications to Milan" "./scripts/deploy-app-with-region.fish milan"

# Step 3: Deploy applications to Dublin
run_step "Deploy Applications to Dublin" "./scripts/deploy-app-with-region.fish dublin"

# Step 4: Wait for ALBs to be ready
echo ""
echo "⏳ Waiting for ALBs to be ready (this may take 2-3 minutes)..."
sleep 120

# Step 5: Check deployment status
run_step "Check Deployment Status" "./scripts/check-deployment-status.fish"

# Step 6: Deploy Global Accelerator
run_step "Deploy Global Accelerator" "./scripts/deploy-global-accelerator.fish"

# Step 7: Configure MongoDB multi-region
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶️  MongoDB Multi-Region Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  This step requires manual intervention after the script runs."
echo "The script will create NLBs and DNS records, but you'll need to"
echo "manually redeploy MongoDB with the multi-region configuration."
echo ""
./scripts/complete-mongodb-multiregion.fish

# Step 8: Final verification
echo ""
echo "⏳ Waiting for all services to stabilize..."
sleep 30

run_step "Final Deployment Check" "./scripts/check-deployment-status.fish"

# Calculate total time
set -l end_time (date +%s)
set -l duration (math $end_time - $start_time)
set -l minutes (math $duration / 60)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total deployment time: $minutes minutes"
echo ""
echo "✅ What's been deployed:"
echo "  • 2 EKS clusters (Milan & Dublin)"
echo "  • VPC peering and private DNS"
echo "  • Applications in both regions"
echo "  • ALBs for external access"
echo "  • Global Accelerator"
echo "  • MongoDB NLBs (multi-region pending)"
echo "  • Velero backup system"
echo ""
echo "⚠️  IMPORTANT: MongoDB Multi-Region"
echo "To complete MongoDB multi-region setup:"
echo "  1. kubectl delete mongodbcommunity mongodb -n dev"
echo "  2. cd applications/dadjokes/deploy/devspace"
echo "  3. REGION=milan devspace deploy -n dev"
echo "  4. cd ../../../.."
echo "  5. ./scripts/verify-dr-readiness.fish"
echo ""
echo "📊 Access Points:"
set -l ga_dns (aws globalaccelerator list-accelerators --region us-west-2 --query 'Accelerators[0].DnsName' --output text 2>/dev/null)
if test -n "$ga_dns"
    echo "  • Global Accelerator: http://$ga_dns/joke"
end
echo ""
echo "🧪 Ready to test disaster recovery scenarios!"
echo "  See: scenarios/ directory" 