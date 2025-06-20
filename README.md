# K8s Multi-Region Disaster Recovery Demo

A comprehensive demonstration of Kubernetes disaster recovery patterns across multiple AWS regions, featuring automated failover, backup strategies, and chaos engineering.

## 🎯 Project Overview

This project showcases enterprise-grade disaster recovery capabilities using:
- **Multi-region EKS clusters** (Milan + Dublin) running **EKS 1.33**
- **Automated DNS failover** with Route53 and Global Accelerator
- **Multiple backup strategies** (Velero, EBS snapshots, MongoDB replica sets)
- **Chaos engineering** with built-in fault injection and Chaos Mesh
- **Infrastructure as Code** with Pulumi TypeScript

### Key Features

- ⚡ **Sub-60 second failover** for internet-facing traffic
- 🔄 **Multi-layer backup** with different RPO objectives
- 🎭 **Comprehensive fault injection** (application + infrastructure level)
- 📊 **Health check comparison** (naive vs dependency-aware)
- 🐟 **Fish shell helpers** for streamlined operations
- 🤖 **Automated Velero backups** every 6 hours with 7-day retention

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Milan (EU-S1) │    │  Dublin (EU-W1) │
│   Primary       │    │   Secondary     │
├─────────────────┤    ├─────────────────┤
│ EKS 1.33        │◄──►│ EKS 1.33        │
│ MongoDB Primary │◄──►│ MongoDB Replica │
│ Redis Cache     │    │ Redis Cache     │
│ DadJokes App    │    │ DadJokes App    │
│ Velero + S3     │    │ Velero + S3     │
│ Prometheus/Graf │    │ Prometheus/Graf │
│ Chaos Mesh      │    │ Chaos Mesh      │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────┬───────────────┘
                 │
    ┌─────────────────────────┐
    │   Global Accelerator    │
    │   Route53 Health Checks │
    │   DNS Failover (30s)    │
    └─────────────────────────┘
```

## 🤖 What's Automated vs Manual

### ✅ Fully Automated (via Pulumi)
- EKS cluster creation with version 1.33 and latest addon versions
- VPC and networking infrastructure (10.0.0.0/16 Milan, 10.1.0.0/16 Dublin)
- Storage classes and EBS CSI driver
- **Velero installation** with:
  - S3 bucket creation with encryption
  - IAM roles with IRSA (IAM Roles for Service Accounts)
  - Automatic backup schedules (every 6 hours for MongoDB and DadJokes)
  - 7-day retention policy
  - Cross-region bucket replication support
- Monitoring stack (Prometheus/Grafana with persistent storage)
- Chaos Mesh for chaos engineering
- Cross-region VPC peering and security groups
- Private hosted zone (internal.k8sdr.com)

### ⚠️ Semi-Automated (templates provided)
- CoreDNS configuration (patch file at `infrastructure/pulumi/configs/coredns-patch.yaml`)
- MongoDB NLB services (requires manual kubectl apply)
- Fish shell helper functions for operations

### 🔴 Manual Steps Required
- Application deployment via DevSpace
- DNS/Global Accelerator setup (requires ALB ARNs from deployed applications)
- MongoDB cross-region DNS records (requires NLB DNS names)
- Route53 failover configuration

## 🚀 Quick Start

### Prerequisites

- **Fish shell** (recommended) or bash
- **AWS CLI** with SSO configured
- **yawsso** for credential management
- **Pulumi CLI** (v3.0+)
- **kubectl** and **helm**
- **jq** for JSON processing

### 1. AWS Credentials Setup

```fish
# Install yawsso if not already installed
pip install yawsso

# Configure AWS SSO (one-time setup)
aws configure sso

# Refresh credentials with yawsso
yawsso

# Export credentials for Pulumi (fish syntax)
set -gx AWS_ACCESS_KEY_ID (aws configure get aws_access_key_id)
set -gx AWS_SECRET_ACCESS_KEY (aws configure get aws_secret_access_key)
set -gx AWS_SESSION_TOKEN (aws configure get aws_session_token)

# Verify credentials
aws sts get-caller-identity
```

### 2. Deploy Infrastructure

```fish
# Navigate to Pulumi directory
cd infrastructure/pulumi

# Deploy Milan (primary) region
pulumi stack select milan
pulumi up

# Deploy Dublin (secondary) region
pulumi stack select dublin
pulumi up
```

### 3. Load Helper Functions

```fish
# From project root
source infrastructure/scripts/k8s-dr-helpers.fish

# Verify both clusters
dr-health
```

### 4. Deploy Applications

```fish
# Deploy to Milan
dr-deploy milan

# Deploy to Dublin
dr-deploy dublin

# Check status
use-milan
dr-status
use-dublin
dr-status
```

## 📁 Project Structure

```
k8spocalypse/
├── infrastructure/
│   ├── pulumi/                    # Infrastructure as Code
│   │   ├── components/            # Reusable components
│   │   │   ├── networking.ts      # VPC, subnets, NAT gateways
│   │   │   ├── eks-cluster.ts     # EKS with ALB controller
│   │   │   ├── storage.ts         # EBS, storage classes, DLM
│   │   │   ├── dns.ts             # Route53, Global Accelerator
│   │   │   └── backup.ts          # Velero, snapshot policies
│   │   ├── index.ts               # Main orchestration
│   │   ├── Pulumi.milan.yaml      # Milan stack config
│   │   └── Pulumi.dublin.yaml     # Dublin stack config
│   └── scripts/
│       ├── k8s-dr-helpers.fish    # Fish shell helpers
│       └── README.md              # Helper documentation
├── applications/
│   ├── dadjokes/                  # Demo application
│   │   ├── cmd/                   # Go microservices
│   │   ├── deploy/devspace/       # DevSpace configs
│   │   └── internal/              # Business logic + fault injection
│   ├── deploy-app-milan.sh        # Milan deployment script
│   └── deploy-app-dublin.sh       # Dublin deployment script
├── scenarios/                     # DR demonstration scenarios
│   ├── scenario-1-data-loss/      # RPO comparison
│   ├── scenario-2-failover/       # DNS failover testing
│   └── scenario-3-health-checks/  # Health check comparison
└── docs/                          # Step-by-step guides
```

## 🎭 Disaster Recovery Scenarios

### Scenario 1: Stale Data / RPO Paradox
Demonstrates different Recovery Point Objectives across backup methods:
```fish
cd scenarios/scenario-1-data-loss
./inject.sh     # Create test data and snapshots
./fail-milan.sh # Simulate Milan failure
./validate.sh   # Compare RPO across methods
```

### Scenario 2: Internet-Facing Failover
Tests sub-60 second DNS failover:
```fish
cd scenarios/scenario-2-failover
./inject.sh     # Inject health check failures
./validate.sh   # Monitor failover progress
```

### Scenario 3: Health-Check Theatre
Compares naive vs dependency-aware health checks:
```fish
cd scenarios/scenario-3-health-checks
./inject-mongo-pool.sh    # Built-in fault injection
kubectl apply -f inject-redis-stress.yaml  # Chaos Mesh
./validate.sh             # Compare /healthz vs /readyz
```

## 🐟 Fish Shell Helpers

The project includes comprehensive fish shell helpers for streamlined operations:

### Cluster Management
```fish
use-milan          # Switch to Milan cluster
use-dublin         # Switch to Dublin cluster
dr-status          # Show current cluster status
dr-health          # Check health of both regions
```

### Backup & Recovery
```fish
dr-snapshot        # Create manual EBS snapshot
dr-backup          # Create manual Velero backup
dr-list-backups    # List all available backups
```

### Fault Injection
```fish
dr-fault mongodb pool-exhausted    # Inject MongoDB failure
dr-fault redis oom                 # Inject Redis OOM
dr-fault health 500                # Make health checks fail
dr-restore                         # Clear all faults
dr-compare-health                  # Compare health endpoints
```

### Scenarios
```fish
dr-scenario 1      # Run RPO paradox scenario
dr-scenario 2      # Run failover scenario
dr-scenario 3      # Run health check scenario
```

## 🔧 Chaos Engineering

### Built-in Fault Injection
The DadJokes application includes HTTP endpoints for fault injection:
- `/inject/fault` - Inject various failure modes
- `/inject/restore` - Clear all injected faults
- `/healthz` - Naive health check (port-only)
- `/readyz` - Dependency-aware health check

### Chaos Mesh Integration
Infrastructure-level chaos testing:
```fish
# Install Chaos Mesh
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace

# Apply chaos experiments
kubectl apply -f scenarios/scenario-3-health-checks/inject-redis-stress.yaml
kubectl apply -f scenarios/scenario-3-health-checks/inject-mongo-network.yaml
```

## 📊 Key Metrics

- **RTO (Recovery Time Objective)**: < 60 seconds for DNS failover
- **RPO (Recovery Point Objective)**: 
  - MongoDB replica: ~0 seconds
  - EBS snapshots: ~5 minutes
  - Velero backups: ~4 hours
- **Health Check Interval**: 30 seconds
- **DNS TTL**: 30 seconds for fast failover

## 🔍 Monitoring & Validation

### Health Checks
```fish
# Compare health endpoints
dr-compare-health

# Check Global Accelerator status
aws globalaccelerator list-accelerators
```

### Backup Validation
```fish
# List all backup methods
dr-list-backups

# Check Velero status
velero backup get
velero restore get
```

### Failover Testing
```fish
# Monitor DNS resolution
watch -n 5 'dig +short api.dadjokes.global'

# Test endpoint availability
while true; do 
  curl -s -o /dev/null -w "Status: %{http_code} - Time: $(date)\n" https://api.dadjokes.global/health
  sleep 5
end
```

## 🛠️ Troubleshooting

### AWS Credentials Issues
```fish
# Refresh yawsso credentials
yawsso
set -gx AWS_ACCESS_KEY_ID (aws configure get aws_access_key_id)
set -gx AWS_SECRET_ACCESS_KEY (aws configure get aws_secret_access_key)
set -gx AWS_SESSION_TOKEN (aws configure get aws_session_token)
```

### Cluster Access Issues
```fish
# Update kubeconfig
aws eks update-kubeconfig --region eu-south-1 --name k8s-dr-milan
aws eks update-kubeconfig --region eu-west-1 --name k8s-dr-dublin

# Test connectivity
dr-health
```

### Application Issues
```fish
# Check pod status
kubectl get pods -n dev

# Check service endpoints
kubectl get endpoints -n dev

# Clear any injected faults
dr-restore
```

## 📚 Documentation

- [Infrastructure Setup](docs/step-3-eks-cluster.md)
- [Storage Configuration](docs/step-4-storage-configuration.md)
- [Networking Setup](docs/step-2-networking-setup.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

## 🤝 Contributing

This is a demonstration project showcasing DR patterns and chaos engineering practices. Feel free to adapt the patterns for your own use cases.

## 📄 License

See [LICENSE](LICENSE) file for details.

## 📋 Demo Criteria Verification

### ✅ Infrastructure Components (Fully Automated)
- **EKS 1.33 Clusters**: Milan (eu-south-1) + Dublin (eu-west-1) with latest addon versions
- **VPC & Networking**: 10.0.0.0/16 (Milan), 10.1.0.0/16 (Dublin) with cross-region peering
- **Storage**: GP3 storage classes, EBS CSI driver, automated DLM snapshot policies
- **Backup**: Velero with S3 buckets, 6-hour schedules, 7-day retention, IRSA authentication
- **Monitoring**: Prometheus + Grafana with persistent storage, pre-configured dashboards
- **Chaos Engineering**: Chaos Mesh with dashboard, network/stress/DNS chaos capabilities
- **Load Balancing**: AWS Load Balancer Controller with ALB ingress support

### ✅ Application Components (DadJokes)
- **Multi-Service Architecture**: joke-server, joke-worker, MongoDB, Redis, NATS
- **Health Endpoints**:
  - `/livez` - Basic liveness (always returns 200)
  - `/readyz` - Dependency-aware readiness (checks MongoDB, Redis, NATS, local storage)
  - `/startz` - Startup probe
- **Fault Injection**: Built-in HTTP endpoints `/inject/fault` and `/inject/restore`
- **Business Logic**: OpenAI integration, rating system, caching layer
- **Cross-Region**: MongoDB replica set support, Redis caching, local storage fallback

### ✅ DR Scenarios (Comprehensive Testing)
1. **RPO Paradox**: MongoDB (~0s), EBS snapshots (~5min), Velero (~4h) comparison
2. **DNS Failover**: Sub-60 second RTO with Route53 + Global Accelerator
3. **Health Check Theatre**: `/healthz` vs `/readyz` behavior under dependency failures

### ✅ Chaos Engineering (Dual Approach)
- **Application-Level**: HTTP fault injection (instant, business logic aware)
- **Infrastructure-Level**: Chaos Mesh (network partitions, resource stress, DNS failures)

## 🚀 Detailed Deployment Plan

### Phase 1: Infrastructure Foundation (15-20 minutes)

```fish
# 1. Setup AWS credentials with yawsso
yawsso
set -gx AWS_ACCESS_KEY_ID (aws configure get aws_access_key_id)
set -gx AWS_SECRET_ACCESS_KEY (aws configure get aws_secret_access_key)
set -gx AWS_SESSION_TOKEN (aws configure get aws_session_token)

# 2. Deploy base infrastructure
cd infrastructure/pulumi

# Deploy Milan (primary)
pulumi up -s milan --yes
# ✅ Creates: VPC, EKS 1.33, Storage, Velero, Monitoring, Chaos Mesh, ALB Controller

# Deploy Dublin (secondary)
pulumi up -s dublin --yes
# ✅ Creates: Same as Milan but in eu-west-1

# 3. Enable cross-region connectivity
pulumi config set enableCrossRegion true -s milan
pulumi config set enableCrossRegion true -s dublin
pulumi up -s milan --yes  # Creates VPC peering
pulumi up -s dublin --yes # Accepts peering
```

**What's Automated:**
- EKS clusters with 1.33 and all required addons
- Velero backup schedules (every 6 hours)
- Monitoring stack with persistent storage
- Cross-region VPC peering and security groups
- Private hosted zone (internal.k8sdr.com)

### Phase 2: DNS Configuration (Manual - 5 minutes)

**Why Manual:** CoreDNS needs cluster-specific configuration after EKS deployment.

```fish
# Apply CoreDNS patch to both clusters
kubectl --context k8s-dr-milan apply -f infrastructure/pulumi/configs/coredns-patch.yaml
kubectl --context k8s-dr-dublin apply -f infrastructure/pulumi/configs/coredns-patch.yaml

# Restart CoreDNS to pick up changes
kubectl --context k8s-dr-milan rollout restart deployment/coredns -n kube-system
kubectl --context k8s-dr-dublin rollout restart deployment/coredns -n kube-system
```

**How CoreDNS Patch Works:**
The `coredns-custom` ConfigMap adds a DNS zone override:
- **Zone**: `internal.k8sdr.com:53` 
- **Behavior**: Forwards queries to VPC resolver (/etc/resolv.conf)
- **Cache**: 10-second TTL (matches Route53 TTL for fast failover)
- **Purpose**: Enables cross-region MongoDB DNS resolution

**Guarantee Mechanism:**
1. ConfigMap is applied to `kube-system` namespace
2. CoreDNS automatically picks up ConfigMaps with `.override` suffix
3. Restart ensures immediate activation
4. Test with: `kubectl exec -it <pod> -- nslookup mongo.db.internal.k8sdr.com`

### Phase 3: Application Deployment (Manual - 10 minutes)

**Why Manual:** DevSpace requires interactive deployment and region-specific configuration.

```fish
# 1. Deploy to Milan
kubectl config use-context k8s-dr-milan
cd applications/dadjokes/deploy/devspace
devspace deploy --namespace dev

# 2. Configure multi-region MongoDB (optional)
mv custom-resources/mongodb.yaml custom-resources/mongodb.yaml.single
mv custom-resources/mongodb-multiregion.yaml.disabled custom-resources/mongodb.yaml
sed -i 's/mongodb-2.internal.company.com/mongo.db.internal.k8sdr.com/' custom-resources/mongodb.yaml
kubectl apply -f custom-resources/mongodb.yaml

# 3. Deploy to Dublin
kubectl config use-context k8s-dr-dublin
REGION=dublin devspace deploy --namespace dev
```

### Phase 4: Cross-Region Services (Manual - 10 minutes)

**Why Manual:** Requires dynamic NLB DNS names that can't be predicted.

```fish
# 1. Create MongoDB NLB services in both regions
kubectl --context k8s-dr-milan apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mongo-nlb
  namespace: dev
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  type: LoadBalancer
  selector:
    app: mongodb-svc
  ports:
  - port: 27017
    targetPort: 27017
EOF

# Repeat for Dublin...

# 2. Wait for NLB provisioning (2-3 minutes)
kubectl --context k8s-dr-milan get svc mongo-nlb -n dev -w

# 3. Create Route53 failover records
MILAN_MONGO_NLB=$(kubectl --context k8s-dr-milan get svc -n dev mongo-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_MONGO_NLB=$(kubectl --context k8s-dr-dublin get svc -n dev mongo-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ZONE_ID=$(pulumi stack output privateHostedZoneId -s milan)

# Create Route53 records with AWS CLI (see DEPLOYMENT_CHECKLIST.md)
```

### Phase 5: DNS & Global Failover (Manual - 15 minutes)

**Why Manual:** Requires ALB ARNs from deployed applications.

```fish
# 1. Extract ALB information
MILAN_ALB=$(kubectl --context k8s-dr-milan get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_ALB=$(kubectl --context k8s-dr-dublin get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 2. Get ALB ARNs and Zone IDs
MILAN_ALB_ARN=$(aws elbv2 describe-load-balancers --region eu-south-1 --query "LoadBalancers[?DNSName=='${MILAN_ALB}'].LoadBalancerArn" --output text)
DUBLIN_ALB_ARN=$(aws elbv2 describe-load-balancers --region eu-west-1 --query "LoadBalancers[?DNSName=='${DUBLIN_ALB}'].LoadBalancerArn" --output text)

# 3. Configure Pulumi DNS component
pulumi config set milanAlbArn $MILAN_ALB_ARN -s dns
pulumi config set dublinAlbArn $DUBLIN_ALB_ARN -s dns
# ... (see DNS_DEPLOYMENT_GUIDE.md for complete commands)

# 4. Deploy DNS component
pulumi up -s dns --yes
```

### Phase 6: Verification & Testing (5 minutes)

```fish
# Source helper functions
source infrastructure/scripts/k8s-dr-helpers.fish

# Verify infrastructure
dr-status
dr-health

# Test applications
curl https://<milan-alb>/joke
curl https://<dublin-alb>/joke

# Verify Velero backups
kubectl get schedules -n velero
kubectl get backups -n velero

# Test health endpoints
dr-compare-health
```

## 🔧 CoreDNS Patch Deep Dive

### What It Does
The CoreDNS patch (`infrastructure/pulumi/configs/coredns-patch.yaml`) configures DNS forwarding for cross-region service discovery:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  internal.override: |
    internal.k8sdr.com:53 {
        errors
        cache 10 {
            success 10
            denial 10
        }
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        reload
        loadbalance
    }
```

### How It Works
1. **Zone Override**: Creates a DNS zone for `internal.k8sdr.com`
2. **VPC Resolver**: Forwards queries to AWS VPC resolver via `/etc/resolv.conf`
3. **Fast Cache**: 10-second TTL matches Route53 for quick failover
4. **Auto-Discovery**: CoreDNS automatically loads ConfigMaps with `.override` suffix

### Guarantee Mechanism
- **Automatic Loading**: CoreDNS watches for ConfigMaps in kube-system
- **Immediate Effect**: Restart ensures configuration is active
- **Verification**: Test with `nslookup mongo.db.internal.k8sdr.com` from any pod
- **Fallback**: If patch fails, applications still work with cluster.local DNS

### Why Not Automated
- **Timing**: EKS addon management conflicts with immediate configuration changes
- **Cluster-Specific**: Each cluster needs its own CoreDNS restart timing
- **Safety**: Manual verification ensures DNS resolution works before proceeding

## 🎯 Total Deployment Time
- **Automated (Pulumi)**: ~20 minutes
- **Manual Steps**: ~30 minutes  
- **Total**: ~50 minutes for complete multi-region DR environment

## 🔍 Validation Checklist
- [ ] Both EKS clusters running with 1.33
- [ ] Velero schedules active in both regions
- [ ] CoreDNS forwarding `internal.k8sdr.com` queries
- [ ] Applications deployed and healthy
- [ ] Cross-region MongoDB connectivity
- [ ] Health endpoints returning correct status
- [ ] Fault injection working via HTTP endpoints
- [ ] Chaos Mesh experiments can be applied
- [ ] DNS failover configured (if Global Accelerator deployed) 