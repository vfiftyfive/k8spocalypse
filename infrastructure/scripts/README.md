# K8s DR Helper Functions

This directory contains helper scripts for managing the multi-region Kubernetes disaster recovery environment.

## Fish Shell Helper Functions

The `k8s-dr-helpers.fish` file provides convenient functions for managing the DR environment.

### Installation

```fish
# Source the helper functions
source infrastructure/scripts/k8s-dr-helpers.fish

# Or add to your fish config for permanent access
echo "source $PWD/infrastructure/scripts/k8s-dr-helpers.fish" >> ~/.config/fish/config.fish
```

### Available Functions

#### Cluster Management
- `use-milan` - Switch kubectl context to Milan cluster and set AWS region
- `use-dublin` - Switch kubectl context to Dublin cluster and set AWS region
- `dr-status` - Show current cluster status and running pods
- `dr-health` - Check health of both regions (clusters and ALBs)

#### Deployment
- `dr-deploy <milan|dublin>` - Deploy DadJokes application to specified region

#### Backup & Recovery
- `dr-snapshot` - Create manual EBS snapshot of ratings volume
- `dr-backup` - Create manual Velero backup of dev namespace
- `dr-list-backups` - List all available Velero backups and EBS snapshots

#### Fault Injection
- `dr-fault <component> [mode]` - Inject fault into application
  - Components: `all`, `mongodb`, `redis`, `openai`, `health`
  - Modes: `default`, `pool-exhausted`, `oom`, `rate-limit`, `500`
- `dr-restore` - Clear all injected faults
- `dr-compare-health` - Compare /healthz vs /readyz responses

#### Scenarios
- `dr-scenario <1|2|3>` - Run DR scenario
  - 1: Stale Data / RPO Paradox
  - 2: Internet-Facing Failover
  - 3: Health-Check Theatre

### Examples

```fish
# Check health of both regions
dr-health

# Switch to Milan and check status
use-milan
dr-status

# Inject MongoDB failure
dr-fault mongodb pool-exhausted

# Compare health endpoints
dr-compare-health

# Clear all faults
dr-restore

# Run scenario 1
dr-scenario 1

# Create manual backup
dr-backup

# List all backups
dr-list-backups
```

### Color-Coded Output

The functions use color coding for better readability:
- 🟢 Green (✓) - Success messages
- 🔴 Red (✗) - Error messages
- 🟡 Yellow (⚠) - Warning messages
- 🔵 Blue (➜) - Information messages

### Environment Variables

The functions use these environment variables (with defaults):
- `DR_PRIMARY_REGION` - Primary AWS region (default: eu-south-1)
- `DR_SECONDARY_REGION` - Secondary AWS region (default: eu-west-1)
- `DR_PRIMARY_CLUSTER` - Primary cluster name (default: k8s-dr-milan)
- `DR_SECONDARY_CLUSTER` - Secondary cluster name (default: k8s-dr-dublin)

### Prerequisites

- Fish shell 3.0+
- kubectl configured with both cluster contexts
- AWS CLI configured with appropriate credentials
- jq for JSON parsing
- Velero CLI (for backup functions)
- curl for health checks

### Troubleshooting

If functions don't work:
1. Ensure you're in the project root directory
2. Check AWS credentials: `aws sts get-caller-identity`
3. Verify kubectl contexts: `kubectl config get-contexts`
4. Ensure required tools are installed: `which kubectl aws jq velero curl` 