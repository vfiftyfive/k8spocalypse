#!/opt/homebrew/bin/fish

# Deploy Dublin DR Infrastructure
echo "🚀 Deploying Dublin (DR) Infrastructure..."
echo "================================================"

# Set the passphrase
set -x PULUMI_CONFIG_PASSPHRASE "k8spocalypse2024"

# Deploy the Dublin stack
echo "📦 Running Pulumi deployment for Dublin stack..."
pulumi up -s dublin --yes

# Check the exit code
if test $status -eq 0
    echo "✅ Dublin infrastructure deployed successfully!"
    echo ""
    echo "📊 Stack outputs:"
    pulumi stack output -s dublin
else
    echo "❌ Deployment failed. Please check the errors above."
    exit 1
end 