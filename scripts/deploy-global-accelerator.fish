#!/usr/bin/env fish

# Deploy Global Accelerator using AWS CLI for k8spocalypse
# This is a simpler approach than using Pulumi for Global Accelerator

function print_status
    echo "[INFO] $argv"
end

function print_success
    echo "[SUCCESS] $argv"
end

function print_error
    echo "[ERROR] $argv"
end

print_status "🌐 Deploying Global Accelerator for k8spocalypse..."

# Get ALB information
print_status "Discovering ALBs in both regions..."

set -l MILAN_ALB_JSON (aws elbv2 describe-load-balancers --region eu-south-1 2>/dev/null | jq '.LoadBalancers[] | select(.LoadBalancerName | contains("dadjokes"))')
set -l DUBLIN_ALB_JSON (aws elbv2 describe-load-balancers --region eu-west-1 2>/dev/null | jq '.LoadBalancers[] | select(.LoadBalancerName | contains("dadjokes"))')

if test -z "$MILAN_ALB_JSON" -o -z "$DUBLIN_ALB_JSON"
    print_error "ALBs not found in both regions. Deploy applications first."
    exit 1
end

# Extract ALB ARNs
set -l MILAN_ALB_ARN (echo $MILAN_ALB_JSON | jq -r '.LoadBalancerArn')
set -l DUBLIN_ALB_ARN (echo $DUBLIN_ALB_JSON | jq -r '.LoadBalancerArn')

print_success "Found ALBs:"
print_status "  Milan: $MILAN_ALB_ARN"
print_status "  Dublin: $DUBLIN_ALB_ARN"

# Check if Global Accelerator already exists
set -l EXISTING_GA (aws globalaccelerator list-accelerators --region us-west-2 2>/dev/null | jq -r '.Accelerators[] | select(.Name | contains("dadjokes")) | .AcceleratorArn // empty')

if test -n "$EXISTING_GA"
    print_status "Found existing Global Accelerator: $EXISTING_GA"
    set GA_ARN $EXISTING_GA
else
    # Create Global Accelerator
    print_status "Creating Global Accelerator..."
    set -l GA_RESULT (aws globalaccelerator create-accelerator \
        --name "dadjokes-k8sdr-accelerator" \
        --ip-address-type IPV4 \
        --enabled \
        --region us-west-2 \
        --output json)
    
    if test $status -eq 0
        set GA_ARN (echo $GA_RESULT | jq -r '.Accelerator.AcceleratorArn')
        print_success "Created Global Accelerator: $GA_ARN"
    else
        print_error "Failed to create Global Accelerator"
        exit 1
    end
end

# Get or create listener
set -l LISTENER_ARN (aws globalaccelerator list-listeners --accelerator-arn $GA_ARN --region us-west-2 2>/dev/null | jq -r '.Listeners[0].ListenerArn // empty')

if test -z "$LISTENER_ARN"
    print_status "Creating listener..."
    set -l LISTENER_RESULT (aws globalaccelerator create-listener \
        --accelerator-arn $GA_ARN \
        --protocol TCP \
        --port-ranges FromPort=80,ToPort=80 FromPort=443,ToPort=443 \
        --client-affinity SOURCE_IP \
        --region us-west-2 \
        --output json)
    
    if test $status -eq 0
        set LISTENER_ARN (echo $LISTENER_RESULT | jq -r '.Listener.ListenerArn')
        print_success "Created listener: $LISTENER_ARN"
    else
        print_error "Failed to create listener"
        exit 1
    end
else
    print_status "Using existing listener: $LISTENER_ARN"
end

# Create or update endpoint groups
print_status "Creating/updating endpoint groups..."

# Milan endpoint group (primary)
set -l MILAN_EG_RESULT (aws globalaccelerator create-endpoint-group \
    --listener-arn $LISTENER_ARN \
    --endpoint-group-region eu-south-1 \
    --traffic-dial-percentage 100 \
    --health-check-interval-seconds 30 \
    --health-check-path "/health" \
    --health-check-port 80 \
    --health-check-protocol HTTP \
    --threshold-count 3 \
    --endpoint-configurations EndpointId=$MILAN_ALB_ARN,Weight=100 \
    --region us-west-2 \
    --output json 2>/dev/null)

if test $status -eq 0
    print_success "Created Milan endpoint group"
else
    print_status "Milan endpoint group may already exist, updating..."
    # Get existing endpoint group and update it
    set -l EXISTING_EG (aws globalaccelerator list-endpoint-groups --listener-arn $LISTENER_ARN --region us-west-2 | jq -r '.EndpointGroups[] | select(.EndpointGroupRegion == "eu-south-1") | .EndpointGroupArn // empty')
    if test -n "$EXISTING_EG"
        aws globalaccelerator update-endpoint-group \
            --endpoint-group-arn $EXISTING_EG \
            --traffic-dial-percentage 100 \
            --endpoint-configurations EndpointId=$MILAN_ALB_ARN,Weight=100 \
            --region us-west-2 >/dev/null
        print_success "Updated Milan endpoint group"
    end
end

# Dublin endpoint group (secondary)
set -l DUBLIN_EG_RESULT (aws globalaccelerator create-endpoint-group \
    --listener-arn $LISTENER_ARN \
    --endpoint-group-region eu-west-1 \
    --traffic-dial-percentage 0 \
    --health-check-interval-seconds 30 \
    --health-check-path "/health" \
    --health-check-port 80 \
    --health-check-protocol HTTP \
    --threshold-count 3 \
    --endpoint-configurations EndpointId=$DUBLIN_ALB_ARN,Weight=100 \
    --region us-west-2 \
    --output json 2>/dev/null)

if test $status -eq 0
    print_success "Created Dublin endpoint group"
else
    print_status "Dublin endpoint group may already exist, updating..."
    # Get existing endpoint group and update it
    set -l EXISTING_EG (aws globalaccelerator list-endpoint-groups --listener-arn $LISTENER_ARN --region us-west-2 | jq -r '.EndpointGroups[] | select(.EndpointGroupRegion == "eu-west-1") | .EndpointGroupArn // empty')
    if test -n "$EXISTING_EG"
        aws globalaccelerator update-endpoint-group \
            --endpoint-group-arn $EXISTING_EG \
            --traffic-dial-percentage 0 \
            --endpoint-configurations EndpointId=$DUBLIN_ALB_ARN,Weight=100 \
            --region us-west-2 >/dev/null
        print_success "Updated Dublin endpoint group"
    end
end

# Get Global Accelerator details
set -l GA_DETAILS (aws globalaccelerator describe-accelerator --accelerator-arn $GA_ARN --region us-west-2)
set -l GA_DNS (echo $GA_DETAILS | jq -r '.Accelerator.DnsName')
set -l GA_IPS (echo $GA_DETAILS | jq -r '.Accelerator.IpSets[0].IpAddresses[]')

print_success "🎉 Global Accelerator deployment completed!"
print_status ""
print_status "📋 Global Accelerator Details:"
print_status "  • DNS Name: $GA_DNS"
print_status "  • Static IPs: $GA_IPS"
print_status "  • ARN: $GA_ARN"
print_status ""
print_status "🧪 Testing endpoints:"
print_status "  • Global Accelerator: curl http://$GA_DNS/health"
print_status "  • Milan ALB: curl http://(echo $MILAN_ALB_JSON | jq -r '.DNSName')/health"
print_status "  • Dublin ALB: curl http://(echo $DUBLIN_ALB_JSON | jq -r '.DNSName')/health"
print_status ""
print_status "⚡ Failover configuration:"
print_status "  • Milan: 100% traffic (primary)"
print_status "  • Dublin: 0% traffic (standby)"
print_status "  • Health checks: /health endpoint every 30s" 