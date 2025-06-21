#!/usr/bin/env fish

# Deploy K8spocalypse infrastructure using Pulumi
# This script deploys both Milan and Dublin EKS clusters

echo "🚀 K8spocalypse Infrastructure Deployment"
echo "========================================"
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

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check AWS CLI
if not command -v aws >/dev/null 2>&1
    echo "❌ AWS CLI not found. Please run ./scripts/setup.sh first"
    exit 1
end

# Check Pulumi
if not command -v pulumi >/dev/null 2>&1
    echo "❌ Pulumi not found. Please run ./scripts/setup.sh first"
    exit 1
end

# Check AWS credentials
aws sts get-caller-identity >/dev/null 2>&1
if test $status -ne 0
    echo "❌ AWS credentials not configured. Please run:"
    echo "   aws sso login"
    echo "   yawsso --default-only"
    exit 1
end

echo "✅ All prerequisites met"
echo ""

# Deploy infrastructure
echo "🏗️  Deploying infrastructure with Pulumi..."
echo ""

# Navigate to Pulumi directory
cd infrastructure/pulumi
if test $status -ne 0
    echo "❌ Failed to navigate to infrastructure/pulumi directory"
    exit 1
end

# Deploy Milan stack
echo "1️⃣ Deploying Milan (eu-south-1) stack..."
echo "This will take approximately 15-20 minutes..."
pulumi up --stack milan --yes
check_status "Milan stack deployed"
if test $status -ne 0
    echo "❌ Milan deployment failed. Check Pulumi output above."
    exit 1
end

echo ""

# Deploy Dublin stack
echo "2️⃣ Deploying Dublin (eu-west-1) stack..."
echo "This will take approximately 15-20 minutes..."
pulumi up --stack dublin --yes
check_status "Dublin stack deployed"
if test $status -ne 0
    echo "❌ Dublin deployment failed. Check Pulumi output above."
    exit 1
end

# Return to project root
cd ../..

echo ""
echo "✅ Infrastructure deployment complete!"
echo ""
echo "📊 Deployed components:"
echo "  • Milan EKS cluster (eu-south-1)"
echo "  • Dublin EKS cluster (eu-west-1)"
echo "  • VPC peering between regions"
echo "  • Private hosted zone (internal.k8sdr.com)"
echo "  • ALB controllers in both regions"
echo "  • Velero backup system"
echo "  • CoreDNS custom configuration"
echo ""
echo "🚀 Next steps:"
echo "  1. Deploy applications: ./scripts/deploy-app-with-region.fish milan"
echo "  2. Deploy applications: ./scripts/deploy-app-with-region.fish dublin"
echo "  3. Check status: ./scripts/check-deployment-status.fish" 