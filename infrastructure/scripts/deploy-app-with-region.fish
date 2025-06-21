#!/usr/bin/env fish

# Deploy application with proper region configuration
function deploy_app_with_region
    set -l cluster_name $argv[1]
    set -l region_name $argv[2]
    
    if test -z "$cluster_name" -o -z "$region_name"
        echo "Usage: deploy_app_with_region <cluster_name> <region_name>"
        echo "Example: deploy_app_with_region k8s-dr-milan milan"
        return 1
    end
    
    echo "🚀 Deploying to $cluster_name with region: $region_name"
    
    # Set REGION environment variable
    set -x REGION $region_name
    
    # Navigate to DevSpace directory
    cd applications/dadjokes/deploy/devspace
    
    # Deploy with DevSpace
    devspace deploy --namespace dev --no-warn --kube-context $cluster_name
    
    # Apply custom resources that fix service issues
    kubectl apply -f custom-resources/ -n dev
    
    # Patch the deployment to ensure REGION is set correctly
    kubectl patch deployment joke-server -n dev --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/env/3/value\", \"value\": \"$region_name\"}]"
    
    echo "✅ Deployment complete for $region_name"
    
    # Return to original directory
    cd -
end

# Main execution
if test (count $argv) -eq 2
    deploy_app_with_region $argv[1] $argv[2]
else
    echo "Usage: $argv[0] <cluster_name> <region_name>"
    echo "Example: $argv[0] k8s-dr-milan milan"
end 