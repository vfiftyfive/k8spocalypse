# Step 3: First EKS Cluster (Milan)

This step creates the EKS cluster in Milan region using the networking infrastructure from Step 2.

## Components Created

### EKS Cluster
- **Version**: 1.29 (latest stable)
- **Endpoint Access**: Both public and private enabled
- **Logging**: All control plane logs enabled (api, audit, authenticator, controllerManager, scheduler)
- **OIDC Provider**: Enabled for IRSA (IAM Roles for Service Accounts)

### Managed Node Group
- **Instance Type**: t3.large (configurable)
- **Node Count**: 3 (min: 1, max: 6)
- **Disk Size**: 100 GB
- **AMI Type**: Amazon Linux 2
- **Placement**: Private subnets across 3 AZs

### Add-ons Included
- **AWS VPC CNI**: For pod networking
- **EBS CSI Driver**: For persistent volume support
- **CoreDNS**: For cluster DNS
- **kube-proxy**: For service networking

### IAM Roles Created
1. **Cluster Role**: For EKS control plane
2. **Node Role**: For EC2 instances
3. **EBS CSI Driver Role**: For volume management

## Deployment Instructions

**Note**: Make sure the networking from Step 2 is fully deployed before proceeding.

1. **Ensure you're in the Pulumi directory**:
   ```bash
   cd infrastructure/pulumi
   ```

2. **Update the stack to include EKS**:
   ```bash
   pulumi up -s milan
   ```
   
   This will show you what will be added (the EKS cluster components).

3. **Deployment Time**: 
   - EKS cluster creation takes approximately 10-15 minutes
   - Node group creation takes an additional 3-5 minutes

## Verification

After deployment completes:

1. **Run the verification script**:
   ```bash
   cd ../../infrastructure/scripts
   ./verify-eks.sh
   ```

2. **Manual verification with kubectl**:
   ```bash
   # Update your kubeconfig
   aws eks update-kubeconfig --name k8s-dr-milan --region eu-south-1
   
   # Check cluster info
   kubectl cluster-info
   
   # Check nodes
   kubectl get nodes
   
   # Check system pods
   kubectl get pods -n kube-system
   ```

## Expected Outputs

After successful deployment:

```
Outputs:
    eksClusterEndpoint : "https://xxxxx.gr7.eu-south-1.eks.amazonaws.com"
    eksClusterName     : "k8s-dr-milan"
    eksOidcProviderArn : "arn:aws:iam::xxxx:oidc-provider/oidc.eks.eu-south-1.amazonaws.com/id/xxxx"
    eksSummary         : {
        clusterEndpoint  : "https://xxxxx.gr7.eu-south-1.eks.amazonaws.com"
        clusterName      : "k8s-dr-milan"
        eksVersion       : "1.29"
        nodeCount        : 3
        nodeGroupId      : "k8s-dr-milan-nodes-xxxx"
        nodeInstanceType : "t3.large"
        region           : "eu-south-1"
    }
    kubeconfig         : [secret]
```

## Cost Breakdown

- **EKS Control Plane**: $0.10/hour
- **EC2 Instances**: 3 x t3.large = ~$0.25/hour
- **EBS Volumes**: 3 x 100GB = ~$0.03/hour
- **Total**: ~$0.38/hour for the cluster

## Troubleshooting

### Nodes not joining cluster
- Check security group rules
- Verify IAM roles and policies
- Check node group subnet configuration

### EBS CSI Driver issues
- Verify OIDC provider is created
- Check IAM role trust policy
- Ensure addon is in ACTIVE state

### Cannot connect with kubectl
- Ensure your AWS credentials are valid
- Check if cluster endpoint is accessible
- Verify security group allows HTTPS (443)

## Next Steps

Once the EKS cluster is verified and all nodes are Ready:
1. Proceed to Step 4 to configure storage classes
2. Set up automated EBS snapshots
3. Install additional add-ons (metrics-server, ALB controller) 