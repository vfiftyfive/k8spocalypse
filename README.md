# K8s Multi-Region Disaster Recovery Demo

A comprehensive demonstration of Kubernetes disaster recovery patterns across multiple AWS regions, featuring automated failover, backup strategies, and chaos engineering.

## 🎯 Project Overview

This project showcases enterprise-grade disaster recovery capabilities using:
- **Multi-region EKS clusters** (Milan + Dublin)
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

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Milan (EU-S1) │    │  Dublin (EU-W1) │
│   Primary       │    │   Secondary     │
├─────────────────┤    ├─────────────────┤
│ EKS Cluster     │◄──►│ EKS Cluster     │
│ MongoDB Primary │◄──►│ MongoDB Replica │
│ Redis Cache     │    │ Redis Cache     │
│ DadJokes App    │    │ DadJokes App    │
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