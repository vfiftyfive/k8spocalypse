#!/usr/bin/env fish

# Deploy application with proper region configuration
function deploy_app_with_region
    set -l region_name $argv[1]
    
    if test -z "$region_name"
        echo "Usage: deploy_app_with_region <region_name>"
        echo "Example: deploy_app_with_region milan"
        return 1
    end
    
    # Map region to full kubectl context
    switch $region_name
        case milan
            set -l context_name "arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan"
        case dublin
            set -l context_name "arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin"
        case '*'
            echo "❌ Invalid region: $region_name"
            echo "Available regions: milan, dublin"
            return 1
    end
    
    echo "🚀 Deploying to $region_name region..."
    
    # Set REGION environment variable for DevSpace
    set -x REGION $region_name
    
    # Navigate to DevSpace directory
    cd applications/dadjokes/deploy/devspace
    
    # Deploy with DevSpace using correct context
    devspace deploy --namespace dev --no-warn --kube-context "$context_name"
    
    echo "✅ Deployment complete for $region_name"
    
    # Return to original directory
    cd -
end

# Main execution
if test (count $argv) -eq 1
    deploy_app_with_region $argv[1]
else
    echo "Usage: $argv[0] <region_name>"
    echo "Example: $argv[0] milan"
end 