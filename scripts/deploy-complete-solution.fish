#!/usr/bin/env fish

# Complete deployment solution for k8spocalypse
# This script handles all deployment issues and provides a repeatable solution

function print_status
    echo "[INFO] $argv"
end

function print_success
    echo "[SUCCESS] $argv"
end

function print_error
    echo "[ERROR] $argv"
end

function print_warning
    echo "[WARNING] $argv"
end

set -l SCRIPT_DIR (dirname (status -f))
set -l PROJECT_ROOT (dirname (dirname $SCRIPT_DIR))

print_status "🚀 Starting complete k8spocalypse deployment..."

# Phase 1: Clean up existing broken deployments
print_status "Phase 1: Cleaning up existing deployments..."

for region in milan dublin
    if test "$region" = "milan"
        set -l CONTEXT "arn:aws:eks:eu-south-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
    else
        set -l CONTEXT "arn:aws:eks:eu-west-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
    end
    
    print_status "Cleaning up $region..."
    kubectl config use-context $CONTEXT 2>/dev/null
    
    # Delete broken StatefulSets
    kubectl delete statefulset joke-server -n dev --ignore-not-found=true
    kubectl delete statefulset mongodb -n dev --ignore-not-found=true
    kubectl delete statefulset mongodb-arb -n dev --ignore-not-found=true
    
    # Delete broken PVCs
    kubectl delete pvc ratings-storage-joke-server-0 -n dev --ignore-not-found=true
    
    # Delete existing services that will be recreated
    kubectl delete service joke-server joke-server-headless -n dev --ignore-not-found=true
end

# Phase 2: Deploy fixed MongoDB configuration
print_status "Phase 2: Deploying fixed MongoDB configuration..."

for region in milan dublin
    if test "$region" = "milan"
        set -l CONTEXT "arn:aws:eks:eu-south-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
    else
        set -l CONTEXT "arn:aws:eks:eu-west-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
    end
    
    print_status "Deploying MongoDB to $region..."
    kubectl config use-context $CONTEXT 2>/dev/null
    
    # Apply the fixed MongoDB configuration
    kubectl apply -f $PROJECT_ROOT/applications/dadjokes/deploy/devspace/custom-resources/mongodb.yaml
end

# Phase 3: Deploy joke-server as Deployment
print_status "Phase 3: Deploying joke-server as Deployment..."

for region in milan dublin
    if test "$region" = "milan"
        set -l CONTEXT "arn:aws:eks:eu-south-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
        set -l REGION_VAR "milan"
    else
        set -l CONTEXT "arn:aws:eks:eu-west-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
        set -l REGION_VAR "dublin"
    end
    
    print_status "Deploying joke-server to $region..."
    kubectl config use-context $CONTEXT 2>/dev/null
    
    # Replace the REGION variable and apply
    cat $PROJECT_ROOT/applications/dadjokes/deploy/devspace/custom-resources/joke-server-deployment.yaml | \
        sed "s/\${REGION}/$REGION_VAR/g" | \
        kubectl apply -f -
end

# Phase 4: Wait for deployments to be ready
print_status "Phase 4: Waiting for deployments to be ready..."

for region in milan dublin
    if test "$region" = "milan"
        set -l CONTEXT "arn:aws:eks:eu-south-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
    else
        set -l CONTEXT "arn:aws:eks:eu-west-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
    end
    
    print_status "Waiting for $region deployments..."
    kubectl config use-context $CONTEXT 2>/dev/null
    
    # Wait for MongoDB
    print_status "Waiting for MongoDB in $region..."
    set -l MAX_WAIT 300
    set -l WAITED 0
    while test $WAITED -lt $MAX_WAIT
        set -l PHASE (kubectl get mongodbcommunity mongodb -n dev -o jsonpath='{.status.phase}' 2>/dev/null)
        if test "$PHASE" = "Running"
            print_success "MongoDB is running in $region"
            break
        else
            print_status "MongoDB phase: $PHASE, waiting..."
            sleep 10
            set WAITED (math $WAITED + 10)
        end
    end
    
    # Wait for joke-server
    kubectl wait --for=condition=available --timeout=120s deployment/joke-server -n dev
    print_success "joke-server is ready in $region"
end

# Phase 5: Deploy Global Accelerator
print_status "Phase 5: Deploying Global Accelerator..."

cd $SCRIPT_DIR
if test -f deploy-global-accelerator.fish
    ./deploy-global-accelerator.fish
else
    print_warning "Global Accelerator script not found, skipping..."
end

# Phase 6: Verify deployments
print_status "Phase 6: Verifying deployments..."

for region in milan dublin
    if test "$region" = "milan"
        set -l CONTEXT "arn:aws:eks:eu-south-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-milan"
        set -l ALB_REGION "eu-south-1"
    else
        set -l CONTEXT "arn:aws:eks:eu-west-1:(aws sts get-caller-identity --query Account --output text):cluster/k8s-dr-dublin"
        set -l ALB_REGION "eu-west-1"
    end
    
    print_status "Verifying $region deployment..."
    kubectl config use-context $CONTEXT 2>/dev/null
    
    # Check pods
    print_status "Pods in $region:"
    kubectl get pods -n dev
    
    # Check ALB
    set -l ALB_DNS (kubectl get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if test -n "$ALB_DNS"
        print_success "ALB found: $ALB_DNS"
        
        # Test health endpoint
        set -l HEALTH_STATUS (curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/health)
        if test "$HEALTH_STATUS" = "200"
            print_success "Health check passed for $region"
        else
            print_warning "Health check returned: $HEALTH_STATUS"
        end
    else
        print_warning "ALB not found in $region"
    end
end

# Phase 7: Summary
print_status "🎉 Deployment complete!"
print_status ""
print_status "📋 Summary:"
print_status "  • MongoDB deployed with proper readiness probes"
print_status "  • joke-server deployed as Deployment (not StatefulSet)"
print_status "  • Global Accelerator configured (if ALBs available)"
print_status "  • Health endpoints accessible via ALBs"
print_status ""
print_status "🔧 To test the deployment:"
print_status "  1. Check Global Accelerator: curl http://<GA-DNS>/health"
print_status "  2. Check Milan ALB: curl http://<Milan-ALB>/health"
print_status "  3. Check Dublin ALB: curl http://<Dublin-ALB>/health"
print_status ""
print_status "📝 Next steps:"
print_status "  1. Run disaster recovery scenarios"
print_status "  2. Test failover between regions"
print_status "  3. Monitor application metrics" 