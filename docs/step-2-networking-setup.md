# Step 2: Single Region VPC and Networking (Milan)

This step creates the networking infrastructure for the Milan region, including VPC, subnets, NAT gateways, and security groups.

## Components Created

### VPC Configuration
- **CIDR Block**: 10.0.0.0/16 (65,536 IP addresses)
- **Availability Zones**: 3 (for high availability)
- **Region**: eu-south-1 (Milan)

### Subnets
1. **Public Subnets** (3x /24 - 256 IPs each)
   - Used for Application Load Balancers
   - Tagged for ELB discovery: `kubernetes.io/role/elb=1`
   
2. **Private Subnets** (3x /22 - 1,024 IPs each)
   - Used for EKS worker nodes
   - Tagged for internal ELB: `kubernetes.io/role/internal-elb=1`

### NAT Gateways
- One NAT Gateway per AZ (3 total) for high availability
- Enables private subnet internet access

### Security Groups
- **EKS Cluster Security Group**
  - Allows all traffic within VPC
  - Allows HTTPS (443) from anywhere for kubectl access
  - Allows all outbound traffic

### VPC Endpoints
- **S3 Gateway Endpoint**: For efficient S3 access
- **ECR Interface Endpoints**: For pulling container images
  - ECR API endpoint
  - ECR DKR endpoint

## Deployment Instructions

1. **Navigate to the Pulumi directory**:
   ```bash
   cd infrastructure/pulumi
   ```

2. **Install dependencies** (if not already done):
   ```bash
   npm install
   ```

3. **Initialize the Milan stack** (if not already done):
   ```bash
   pulumi stack init milan --secrets-provider=passphrase
   pulumi stack select milan
   ```

4. **Preview the changes**:
   ```bash
   pulumi preview
   ```

5. **Deploy the networking infrastructure**:
   ```bash
   pulumi up
   ```
   
   Select "yes" when prompted to perform the update.

## Verification

After deployment, verify the networking setup:

```bash
# Run the verification script
cd ../../infrastructure/scripts
./verify-networking.sh
```

The script will show:
- VPC details and CIDR block
- Public and private subnet information
- NAT Gateway status
- Internet Gateway details
- Security group configuration
- VPC endpoints

## Expected Outputs

After successful deployment, you should see these outputs:

```
Outputs:
    availabilityZones     : ["eu-south-1a", "eu-south-1b", "eu-south-1c"]
    currentRegion         : "eu-south-1"
    eksSecurityGroupId    : "sg-xxxxxxxxx"
    networkingSummary     : {
        environment         : "milan"
        privateSubnetsCount : 3
        publicSubnetsCount  : 3
        region              : "eu-south-1"
        vpcId               : "vpc-xxxxxxxxx"
    }
    privateSubnetIds      : ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
    publicSubnetIds       : ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
    vpcCidr_              : "10.0.0.0/16"
    vpcId                 : "vpc-xxxxxxxxx"
```

## Cost Considerations

- **NAT Gateways**: ~$0.045/hour per gateway (3 total = ~$0.135/hour)
- **VPC Endpoints**: ~$0.01/hour per endpoint
- **Data Transfer**: Charges apply for data processed through NAT Gateways

## Next Steps

Once the networking is verified, proceed to Step 3 to create the EKS cluster in Milan. 