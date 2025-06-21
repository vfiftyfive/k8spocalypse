# K8s Multi-Region Disaster Recovery Demo

A comprehensive demonstration of Kubernetes disaster recovery patterns across multiple AWS regions, featuring automated failover, backup strategies, and chaos engineering.

## 🎯 Project Overview

This project showcases enterprise-grade disaster recovery capabilities using:
- **Multi-region EKS clusters** (Milan + Dublin) running **EKS 1.33**
- **Automated DNS failover** with Route53 and Global Accelerator
- **Multiple backup strategies** (Velero, EBS snapshots, MongoDB replica sets)
- **Chaos engineering** with built-in fault injection scenarios
- **Infrastructure as Code** with Pulumi TypeScript
- **Fish shell automation** for streamlined operations

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

- **Fish shell** (strongly recommended - user prefers over PowerShell/bash)
- **AWS CLI** with SSO configured
- **yawsso** for credential management
- **Pulumi CLI** (v3.0+)
- **kubectl** and **helm**
- **jq** for JSON processing
- **devspace** CLI for application deployment

### 1. Initial Setup

```fish
# Run the setup script
./scripts/setup.sh

# Load DR helper functions
source scripts/k8s-dr-helpers.fish
```

### 2. Deploy Complete Solution

```fish
# Deploy complete solution (infrastructure + applications + Global Accelerator)
./scripts/deploy-complete-solution.fish
```

This single script handles:
- Infrastructure deployment to both regions
- Application deployment with proper configuration
- MongoDB and storage fixes
- Global Accelerator setup
- Health verification

### 3. Verify Deployment

```fish
# Load helper functions (if not already loaded)
source scripts/k8s-dr-helpers.fish

# Check health of both regions
dr-health

# Check detailed status
use-milan
dr-status

use-dublin  
dr-status
```

## 📁 Project Structure (Cleaned Up)

```
k8spocalypse/
├── scripts/                       # 🎯 ALL ESSENTIAL SCRIPTS (CONSOLIDATED)
│   ├── deploy-complete-solution.fish  # Main deployment script
│   ├── deploy-global-accelerator.fish # Global Accelerator setup
│   ├── deploy-app-with-region.fish    # Application deployment
│   ├── k8s-dr-helpers.fish        # Essential DR operations
│   ├── setup.sh                   # Initial project setup
│   ├── snapshot-management.sh     # EBS snapshot utilities
│   ├── verify-dr-readiness.fish   # DR readiness verification
│   └── README.md                  # Script documentation
├── infrastructure/
│   └── pulumi/                    # Infrastructure as Code
│       ├── components/            # Reusable components
│       │   ├── networking.ts      # VPC, subnets, NAT gateways
│       │   ├── eks-cluster.ts     # EKS with ALB controller
│       │   ├── storage.ts         # EBS, storage classes, DLM
│       │   ├── backup.ts          # Velero, snapshot policies
│       │   └── coredns-config.ts  # CoreDNS cross-region config
│       ├── index.ts               # Main orchestration
│       ├── Pulumi.milan.yaml      # Milan stack config
│       └── Pulumi.dublin.yaml     # Dublin stack config
├── applications/
│   └── dadjokes/                  # Demo application
│       ├── cmd/                   # Go microservices
│       ├── deploy/devspace/       # DevSpace configs (single devspace.yaml)
│       └── internal/              # Business logic + fault injection
├── scenarios/                     # DR demonstration scenarios
│   ├── scenario-1-data-loss/      # RPO comparison
│   ├── scenario-2-failover/       # DNS failover testing
│   └── scenario-3-health-checks/  # Health check comparison
└── docs/                          # Step-by-step guides
```

## 🛠️ Essential Scripts (All in `scripts/` directory)

### Main Deployment
- **`scripts/deploy-complete-solution.fish`** - Complete end-to-end deployment
- **`scripts/deploy-global-accelerator.fish`** - Global Accelerator setup
- **`scripts/deploy-app-with-region.fish`** - Application deployment to specific regions

### Daily Operations  
- **`scripts/k8s-dr-helpers.fish`** - Essential DR functions:
  - `use-milan` / `use-dublin` - Switch between clusters
  - `dr-health` - Check health of both regions
  - `dr-status` - Detailed cluster status
  - `dr-deploy <region>` - Deploy applications to a region
  - `dr-snapshot` - Manual EBS snapshots

### Utilities
- **`scripts/setup.sh`** - Initial project setup
- **`scripts/snapshot-management.sh`** - EBS snapshot operations
- **`scripts/verify-dr-readiness.fish`** - DR readiness verification

See `scripts/README.md` for detailed documentation of each script.

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
./inject-mongo-pool.sh    # MongoDB connection pool exhaustion
./inject-openai-429.sh    # OpenAI API rate limiting
./inject-redis-oom.sh     # Redis out-of-memory
./validate.sh             # Compare health check responses
```

## 🤖 What's Automated vs Manual

### ✅ Fully Automated
- EKS cluster creation with version 1.33 and latest addon versions
- VPC and networking infrastructure (10.0.0.0/16 Milan, 10.1.0.0/16 Dublin)
- Storage classes and EBS CSI driver
- Velero installation with S3 buckets and IAM roles
- Automatic backup schedules (every 6 hours, 7-day retention)
- Cross-region VPC peering and security groups
- Private hosted zone (internal.k8sdr.com)
- CoreDNS configuration for cross-region DNS
- **MongoDB NLBs and DNS records** (managed by Pulumi when enableCrossRegion=true)
- Application deployment with DevSpace
- MongoDB and storage configuration fixes
- Global Accelerator setup (when ALBs are available)

### ⚠️ Manual Steps (for learning/troubleshooting)
- Individual scenario execution
- Manual snapshot operations
- Advanced chaos engineering experiments

## 🔧 Troubleshooting

### Common Issues

1. **OpenAI API Key**: The deployment script automatically decrypts the SOPS-encrypted key
2. **MongoDB not starting**: Fixed in deploy-complete-solution.fish with proper readiness probes
3. **joke-server StatefulSet issues**: Fixed by converting to Deployment
4. **ALB SSL certificate errors**: Fixed by using HTTP-only configuration

### Useful Commands

```fish
# Check pod status
kubectl get pods -n dev

# Check MongoDB status
kubectl get mongodbcommunity -n dev

# Check ALB status
kubectl get ingress -n dev

# View logs
kubectl logs -n dev deployment/joke-server

# Manual snapshot
dr-snapshot
```

## 📊 Monitoring and Observability

The solution includes comprehensive monitoring:
- **Health endpoints** at `/health` on all ALBs
- **Application metrics** via Prometheus (when enabled)
- **EBS snapshot monitoring** via DLM policies
- **Cross-region connectivity** verification

## 🎯 Learning Objectives

This demo teaches:
1. **Multi-region architecture patterns** in Kubernetes
2. **Different backup strategies** and their trade-offs
3. **DNS failover** mechanisms and timing
4. **Chaos engineering** principles and practices
5. **Infrastructure as Code** with Pulumi
6. **Fish shell automation** for DevOps workflows

## 📝 Next Steps

After successful deployment:
1. Run through all three disaster recovery scenarios
2. Experiment with different failure modes
3. Measure and compare recovery times
4. Understand the trade-offs between different backup strategies
5. Practice operational procedures using the fish shell helpers

## 🤝 Contributing

This is a learning project. Feel free to:
- Experiment with different configurations
- Add new chaos engineering scenarios
- Improve the automation scripts
- Document lessons learned

---

**Note**: This project uses fish shell extensively as the user strongly prefers it over PowerShell or bash. All automation scripts are designed to work seamlessly with fish shell syntax and conventions. 