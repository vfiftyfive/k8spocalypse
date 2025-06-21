# K8spocalypse Scripts

This directory contains all the essential scripts for the k8spocalypse multi-region Kubernetes disaster recovery project.

## 🚀 Infrastructure Deployment

### `deploy-complete-solution.fish`
**Primary infrastructure deployment script**
- Deploys both Milan and Dublin EKS clusters with all components
- Handles Pulumi stack deployment, cross-region connectivity, and monitoring
- Usage: `./scripts/deploy-complete-solution.fish`

### `deploy-global-accelerator.fish`
**Global Accelerator deployment for failover**
- Creates AWS Global Accelerator with static IPs
- Configures failover between Milan (primary) and Dublin (standby)
- Usage: `./scripts/deploy-global-accelerator.fish`

## 📦 Application Deployment

### `deploy-app-with-region.fish`
**Application deployment to specific regions**
- Deploys dadjokes application using DevSpace
- Handles region-specific configuration and kubectl context
- Usage: `./scripts/deploy-app-with-region.fish <region>`
- Example: `./scripts/deploy-app-with-region.fish milan`

### `k8s-dr-helpers.fish`
**Comprehensive DR operations toolkit**
- Contains all disaster recovery functions: `dr-deploy`, `dr-status`, `dr-backup`, etc.
- Fault injection, monitoring, and scenario execution
- Source this file: `source scripts/k8s-dr-helpers.fish`
- Then use functions like: `dr-deploy milan`, `dr-status`, `dr-fault mongodb`

## 🔧 Setup & Management

### `setup.sh`
**Initial environment setup**
- Installs required tools (kubectl, helm, devspace, etc.)
- Configures AWS CLI and other dependencies
- Usage: `./scripts/setup.sh`

### `snapshot-management.sh`
**EBS snapshot operations**
- Manual snapshot creation and cross-region replication
- Snapshot restoration and management
- Usage: `./scripts/snapshot-management.sh <action>`

### `verify-dr-readiness.fish`
**DR readiness verification**
- Comprehensive health checks for both regions
- Validates infrastructure, applications, and connectivity
- Usage: `./scripts/verify-dr-readiness.fish`

## 🎯 Disaster Recovery Scenarios

Scenario scripts are located in the `scenarios/` directory at the project root:

- **Scenario 1**: Data Loss / RPO Paradox (`scenarios/scenario-1-data-loss/`)
- **Scenario 2**: Internet-Facing Failover (`scenarios/scenario-2-failover/`)
- **Scenario 3**: Health-Check Theatre (`scenarios/scenario-3-health-checks/`)

Each scenario contains `inject.sh` and `validate.sh` scripts.

## 📁 Project Structure

```
k8spocalypse/
├── scripts/                    # 🎯 All essential scripts (THIS DIRECTORY)
├── infrastructure/pulumi/      # Infrastructure as Code
├── applications/dadjokes/      # Application source and DevSpace config
├── scenarios/                  # DR testing scenarios
└── docs/                      # Documentation
```

## 🔄 Typical Workflow

1. **Setup**: `./scripts/setup.sh`
2. **Deploy Infrastructure**: `./scripts/deploy-complete-solution.fish`
3. **Deploy Applications**: `./scripts/deploy-app-with-region.fish milan && ./scripts/deploy-app-with-region.fish dublin`
4. **Setup Global Accelerator**: `./scripts/deploy-global-accelerator.fish`
5. **Verify Readiness**: `./scripts/verify-dr-readiness.fish`
6. **Run DR Operations**: `source scripts/k8s-dr-helpers.fish` then use `dr-*` functions

## 🛠️ Requirements

- AWS CLI configured with appropriate permissions
- kubectl, helm, devspace, pulumi installed
- Fish shell for `.fish` scripts
- Bash for `.sh` scripts

All scripts are designed to be run from the project root directory. 