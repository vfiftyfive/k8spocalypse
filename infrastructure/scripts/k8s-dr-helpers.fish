#!/usr/bin/env fish
# K8s Multi-Region DR Helper Functions

# Set default regions
set -gx DR_PRIMARY_REGION eu-south-1
set -gx DR_SECONDARY_REGION eu-west-1
set -gx DR_PRIMARY_CLUSTER k8s-dr-milan
set -gx DR_SECONDARY_CLUSTER k8s-dr-dublin

# Color codes for output
set -g COLOR_SUCCESS (set_color green)
set -g COLOR_ERROR (set_color red)
set -g COLOR_WARNING (set_color yellow)
set -g COLOR_INFO (set_color blue)
set -g COLOR_NORMAL (set_color normal)

# Helper function to print colored messages
function dr_info
    echo "$COLOR_INFO➜$COLOR_NORMAL $argv"
end

function dr_success
    echo "$COLOR_SUCCESS✓$COLOR_NORMAL $argv"
end

function dr_error
    echo "$COLOR_ERROR✗$COLOR_NORMAL $argv"
end

function dr_warning
    echo "$COLOR_WARNING⚠$COLOR_NORMAL $argv"
end

# Switch to Milan cluster
function use-milan
    set -l context "arn:aws:eks:$DR_PRIMARY_REGION:"(aws sts get-caller-identity --query Account --output text)":cluster/$DR_PRIMARY_CLUSTER"
    kubectl config use-context $context
    and dr_success "Switched to Milan cluster"
    or dr_error "Failed to switch to Milan cluster"
    
    # Set AWS region
    set -gx AWS_DEFAULT_REGION $DR_PRIMARY_REGION
    dr_info "AWS region set to $DR_PRIMARY_REGION"
end

# Switch to Dublin cluster
function use-dublin
    set -l context "arn:aws:eks:$DR_SECONDARY_REGION:"(aws sts get-caller-identity --query Account --output text)":cluster/$DR_SECONDARY_CLUSTER"
    kubectl config use-context $context
    and dr_success "Switched to Dublin cluster"
    or dr_error "Failed to switch to Dublin cluster"
    
    # Set AWS region
    set -gx AWS_DEFAULT_REGION $DR_SECONDARY_REGION
    dr_info "AWS region set to $DR_SECONDARY_REGION"
end

# Get current cluster info
function dr-status
    dr_info "Current Context:"
    kubectl config current-context
    
    echo ""
    dr_info "Cluster Info:"
    kubectl cluster-info | head -n 1
    
    echo ""
    dr_info "Nodes:"
    kubectl get nodes -o wide
    
    echo ""
    dr_info "DadJokes Application Status:"
    kubectl get pods -n dev -l 'app in (joke-server,joke-worker,mongodb,redis)' -o wide
end

# Check health of both regions
function dr-health
    dr_info "Checking health of both regions..."
    echo ""
    
    # Check Milan
    dr_info "Milan ($DR_PRIMARY_REGION):"
    use-milan >/dev/null 2>&1
    if kubectl get nodes >/dev/null 2>&1
        set -l pod_count (kubectl get pods -n dev --no-headers 2>/dev/null | wc -l)
        set -l running_count (kubectl get pods -n dev --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        dr_success "Cluster accessible - $running_count/$pod_count pods running"
        
        # Check ALB health
        set -l alb_dns (kubectl get svc -n dev joke-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if test -n "$alb_dns"
            set -l health_status (curl -s -o /dev/null -w "%{http_code}" http://$alb_dns/health)
            if test "$health_status" = "200"
                dr_success "ALB health check: OK"
            else
                dr_error "ALB health check: $health_status"
            end
        end
    else
        dr_error "Cluster not accessible"
    end
    
    echo ""
    
    # Check Dublin
    dr_info "Dublin ($DR_SECONDARY_REGION):"
    use-dublin >/dev/null 2>&1
    if kubectl get nodes >/dev/null 2>&1
        set -l pod_count (kubectl get pods -n dev --no-headers 2>/dev/null | wc -l)
        set -l running_count (kubectl get pods -n dev --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        dr_success "Cluster accessible - $running_count/$pod_count pods running"
        
        # Check ALB health
        set -l alb_dns (kubectl get svc -n dev joke-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if test -n "$alb_dns"
            set -l health_status (curl -s -o /dev/null -w "%{http_code}" http://$alb_dns/health)
            if test "$health_status" = "200"
                dr_success "ALB health check: OK"
            else
                dr_error "ALB health check: $health_status"
            end
        end
    else
        dr_error "Cluster not accessible"
    end
end

# Deploy application to a region
function dr-deploy
    if test (count $argv) -ne 1
        dr_error "Usage: dr-deploy <milan|dublin>"
        return 1
    end
    
    set -l region $argv[1]
    
    switch $region
        case milan
            use-milan
            set -l deploy_script "$PWD/applications/deploy-app-milan.sh"
        case dublin
            use-dublin
            set -l deploy_script "$PWD/applications/deploy-app-dublin.sh"
        case '*'
            dr_error "Invalid region. Use 'milan' or 'dublin'"
            return 1
    end
    
    if test -f $deploy_script
        dr_info "Deploying to $region..."
        bash $deploy_script
    else
        dr_error "Deploy script not found: $deploy_script"
        return 1
    end
end

# Trigger manual EBS snapshot
function dr-snapshot
    set -l volume_id (kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.name=="ratings-pvc") | .spec.csi.volumeHandle')
    
    if test -z "$volume_id"
        dr_error "No volume found for ratings-pvc"
        return 1
    end
    
    dr_info "Creating snapshot for volume: $volume_id"
    set -l snapshot_id (aws ec2 create-snapshot \
        --volume-id $volume_id \
        --description "Manual DR snapshot - "(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Type,Value=Manual},{Key=CreatedBy,Value=dr-snapshot}]' \
        --query 'SnapshotId' --output text)
    
    if test -n "$snapshot_id"
        dr_success "Snapshot created: $snapshot_id"
        dr_info "Waiting for completion..."
        aws ec2 wait snapshot-completed --snapshot-ids $snapshot_id
        dr_success "Snapshot completed"
    else
        dr_error "Failed to create snapshot"
        return 1
    end
end

# Trigger Velero backup
function dr-backup
    set -l backup_name "manual-"(date +%Y%m%d-%H%M%S)
    
    dr_info "Creating Velero backup: $backup_name"
    velero backup create $backup_name \
        --include-namespaces dev \
        --wait
    
    if test $status -eq 0
        dr_success "Backup completed: $backup_name"
        velero backup describe $backup_name
    else
        dr_error "Backup failed"
        return 1
    end
end

# List available backups
function dr-list-backups
    dr_info "Velero backups:"
    velero backup get
    
    echo ""
    dr_info "EBS snapshots:"
    aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:Type,Values=Manual,Scheduled" \
        --query 'Snapshots[*].[SnapshotId,StartTime,Progress,Description]' \
        --output table
end

# Inject fault
function dr-fault
    if test (count $argv) -lt 1
        dr_error "Usage: dr-fault <component> [mode]"
        dr_info "Components: all, mongodb, redis, openai, health"
        dr_info "Modes: default, pool-exhausted, oom, rate-limit, 500"
        return 1
    end
    
    set -l component $argv[1]
    set -l mode "default"
    if test (count $argv) -ge 2
        set mode $argv[2]
    end
    
    set -l pod (kubectl get pod -n dev -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
    if test -z "$pod"
        dr_error "No joke-server pod found"
        return 1
    end
    
    dr_info "Injecting fault: $component ($mode)"
    kubectl exec -n dev $pod -- curl -X POST http://localhost:8080/inject/fault \
        -H "Content-Type: application/json" \
        -d "{\"component\": \"$component\", \"failureMode\": \"$mode\", \"duration\": \"5m\"}"
    
    and dr_success "Fault injected"
    or dr_error "Failed to inject fault"
end

# Clear faults
function dr-restore
    set -l pod (kubectl get pod -n dev -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
    if test -z "$pod"
        dr_error "No joke-server pod found"
        return 1
    end
    
    dr_info "Clearing all faults..."
    kubectl exec -n dev $pod -- curl -X POST http://localhost:8080/inject/restore
    
    and dr_success "Faults cleared"
    or dr_error "Failed to clear faults"
end

# Run scenario
function dr-scenario
    if test (count $argv) -ne 1
        dr_error "Usage: dr-scenario <1|2|3>"
        dr_info "1: Stale Data / RPO Paradox"
        dr_info "2: Internet-Facing Failover"
        dr_info "3: Health-Check Theatre"
        return 1
    end
    
    set -l scenario_dir "$PWD/scenarios/scenario-$argv[1]-"
    
    switch $argv[1]
        case 1
            set scenario_dir "$scenario_dir"data-loss
        case 2
            set scenario_dir "$scenario_dir"failover
        case 3
            set scenario_dir "$scenario_dir"health-checks
        case '*'
            dr_error "Invalid scenario number"
            return 1
    end
    
    if test -d $scenario_dir
        dr_info "Running scenario $argv[1] from $scenario_dir"
        cd $scenario_dir
        if test -f inject.sh
            bash inject.sh
        else
            dr_error "inject.sh not found in scenario directory"
        end
    else
        dr_error "Scenario directory not found: $scenario_dir"
        return 1
    end
end

# Quick health check comparison
function dr-compare-health
    set -l pod (kubectl get pod -n dev -l app=joke-server -o jsonpath='{.items[0].metadata.name}')
    if test -z "$pod"
        dr_error "No joke-server pod found"
        return 1
    end
    
    dr_info "Comparing health endpoints:"
    echo ""
    
    echo -n "/healthz: "
    set -l healthz (kubectl exec -n dev $pod -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)
    if test "$healthz" = "200"
        dr_success "$healthz"
    else
        dr_error "$healthz"
    end
    
    echo -n "/readyz:  "
    set -l readyz (kubectl exec -n dev $pod -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/readyz)
    if test "$readyz" = "200"
        dr_success "$readyz"
    else
        dr_warning "$readyz"
    end
    
    echo ""
    dr_info "Pod endpoint membership:"
    set -l pod_ip (kubectl get pod -n dev $pod -o jsonpath='{.status.podIP}')
    if kubectl get endpoints -n dev joke-server -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q "$pod_ip"
        dr_success "Pod is in service endpoints"
    else
        dr_warning "Pod is NOT in service endpoints"
    end
end

# Monitoring functions
function dr-grafana
    dr_info "Opening Grafana Dashboard"
    
    set -l grafana_ingress (kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if test -n "$grafana_ingress"
        dr_success "Grafana URL: http://$grafana_ingress"
        dr_info "Default credentials: admin/admin"
        open "http://$grafana_ingress" 2>/dev/null || echo "Visit: http://$grafana_ingress"
    else
        dr_error "Grafana ingress not found. Check if monitoring is deployed."
        kubectl get ingress -n monitoring
    end
end

function dr-chaos-dashboard
    dr_info "Opening Chaos Mesh Dashboard"
    
    set -l chaos_ingress (kubectl get ingress -n chaos-mesh chaos-dashboard-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if test -n "$chaos_ingress"
        dr_success "Chaos Dashboard URL: http://$chaos_ingress"
        open "http://$chaos_ingress" 2>/dev/null || echo "Visit: http://$chaos_ingress"
    else
        dr_error "Chaos dashboard ingress not found. Check if Chaos Mesh is deployed."
        kubectl get ingress -n chaos-mesh
    end
end

function dr-metrics
    dr_info "Application Metrics"
    
    # Get joke-server pods
    set -l pods (kubectl get pods -n dev -l app=joke-server -o jsonpath='{.items[*].metadata.name}')
    
    if test -n "$pods"
        for pod in $pods
            dr_info "Metrics from $pod:"
            kubectl exec -n dev $pod -- curl -s localhost:9090/metrics | grep -E "(http_requests_total|http_request_duration)" | head -10
            echo ""
        end
    else
        dr_error "No joke-server pods found"
    end
end

function dr-chaos-status
    dr_info "Chaos Experiments Status"
    
    # Check if Chaos Mesh is installed
    if kubectl get namespace chaos-mesh >/dev/null 2>&1
        dr_success "Chaos Mesh namespace exists"
        
        # List all chaos experiments
        dr_info "Active Chaos Experiments:"
        kubectl get chaos -A 2>/dev/null || echo "No active chaos experiments"
        
        # Check Chaos Mesh pods
        dr_info "Chaos Mesh Components:"
        kubectl get pods -n chaos-mesh
    else
        dr_error "Chaos Mesh not installed"
    end
end

# Show helper functions
function dr-help
    dr_info "K8s Multi-Region DR Helper Functions:"
    echo ""
    echo "Cluster Management:"
    echo "  use-milan         - Switch to Milan cluster"
    echo "  use-dublin        - Switch to Dublin cluster"
    echo "  dr-status         - Show current cluster status"
    echo "  dr-health         - Check health of both regions"
    echo ""
    echo "Deployment:"
    echo "  dr-deploy <region> - Deploy application to milan or dublin"
    echo ""
    echo "Backup & Recovery:"
    echo "  dr-snapshot       - Create manual EBS snapshot"
    echo "  dr-backup         - Create manual Velero backup"
    echo "  dr-list-backups   - List available backups"
    echo ""
    echo "Fault Injection:"
    echo "  dr-fault <component> [mode] - Inject fault"
    echo "  dr-restore        - Clear all faults"
    echo "  dr-compare-health - Compare health endpoints"
    echo ""
    echo "Monitoring & Chaos:"
    echo "  dr-grafana        - Open Grafana dashboard"
    echo "  dr-chaos-dashboard - Open Chaos Mesh dashboard"
    echo "  dr-metrics        - Show application metrics"
    echo "  dr-chaos-status   - Show chaos experiments status"
    echo ""
    echo "Scenarios:"
    echo "  dr-scenario <1|2|3> - Run DR scenario"
    echo ""
    echo "Help:"
    echo "  dr-help          - Show this help message"
end

# Initialize on source
dr_info "K8s DR helper functions loaded. Type 'dr-help' for available commands." 