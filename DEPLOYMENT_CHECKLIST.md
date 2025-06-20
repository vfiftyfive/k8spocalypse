# K8s Multi-Region DR Deployment Checklist

## 🤖 What's Automated vs Manual

### ✅ Fully Automated (via Pulumi)
- EKS cluster creation (now using 1.33 with latest addon versions)
- VPC and networking setup
- Storage classes and EBS CSI driver
- Velero installation with:
  - S3 bucket creation
  - IAM roles and policies
  - Automatic backup schedules (every 6 hours for MongoDB and DadJokes)
  - 7-day retention policy
- Monitoring stack (Prometheus/Grafana)
- Chaos Mesh installation
- Cross-region VPC peering and security groups

### ⚠️ Semi-Automated (templates provided)
- CoreDNS configuration (configmap exists at `infrastructure/pulumi/configs/coredns-patch.yaml`)
- MongoDB NLB services (requires manual creation after deployment)
- Route53 DNS records (requires dynamic NLB endpoints)

### 🔴 Manual Steps Required
- ALB ARN extraction for DNS component
- DNS/Global Accelerator deployment (requires ALB ARNs from applications)
- MongoDB cross-region DNS records (requires NLB DNS names)
- Application deployment via DevSpace

## Phase 1: Infrastructure Deployment

### 1.1 Deploy Dublin Stack (Fresh)
```bash
cd infrastructure/pulumi
pulumi up -s dublin --yes
```
✅ Creates: 
- VPC with CIDR 10.1.0.0/16
- EKS 1.33 with latest addon versions
- Storage classes with EBS CSI driver
- Velero with automatic backup schedules
- Monitoring (Prometheus/Grafana)
- Chaos Mesh
- Ingress System (ALB controller)

### 1.2 Deploy/Upgrade Milan Stack
```bash
pulumi up -s milan --yes
```
✅ Creates/Updates:
- VPC with CIDR 10.0.0.0/16  
- EKS upgraded to 1.33 (from 1.29)
- All components matching Dublin

## Phase 2: Cross-Region Connectivity

### 2.1 Enable Cross-Region on Both Stacks
```bash
pulumi config set enableCrossRegion true -s milan
pulumi config set enableCrossRegion true -s dublin
```

### 2.2 Deploy Cross-Region Infrastructure
```bash
# Milan creates VPC peering
pulumi up -s milan --yes

# Dublin accepts peering
pulumi up -s dublin --yes
```
✅ Creates: VPC Peering, Private Hosted Zone (internal.k8sdr.com), Security Groups

## Phase 3: Application Deployment

### 3.1 Deploy MongoDB Operators
```bash
# Set context to Milan
kubectl config use-context k8s-dr-milan

# Deploy operators and base configs
cd applications/dadjokes/deploy/devspace
devspace deploy --namespace dev
```

### 3.2 Enable Multi-Region MongoDB
```bash
# Replace single-region with multi-region MongoDB
mv custom-resources/mongodb.yaml custom-resources/mongodb.yaml.single
mv custom-resources/mongodb-multiregion.yaml.disabled custom-resources/mongodb.yaml

# Update cross-region endpoint
sed -i 's/mongodb-2.internal.company.com/mongo.db.internal.k8sdr.com/' custom-resources/mongodb.yaml

# Redeploy
kubectl apply -f custom-resources/mongodb.yaml
```

### 3.3 Deploy to Dublin
```bash
# Set context to Dublin
kubectl config use-context k8s-dr-dublin

# Deploy with Dublin region
REGION=dublin devspace deploy --namespace dev
```

## Phase 4: Configure Cross-Region Services

### 4.1 Apply CoreDNS Configuration
```bash
# Apply CoreDNS patch in Milan
kubectl --context k8s-dr-milan apply -f infrastructure/pulumi/configs/coredns-patch.yaml

# Apply CoreDNS patch in Dublin  
kubectl --context k8s-dr-dublin apply -f infrastructure/pulumi/configs/coredns-patch.yaml

# Restart CoreDNS in both clusters
kubectl --context k8s-dr-milan rollout restart deployment/coredns -n kube-system
kubectl --context k8s-dr-dublin rollout restart deployment/coredns -n kube-system
```

### 4.2 Create MongoDB NLB Services
```bash
# In Milan
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

# Repeat in Dublin (same command with dublin context)
kubectl --context k8s-dr-dublin apply -f - <<EOF
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
```

### 4.3 Configure MongoDB Cross-Region DNS
```bash
# Get NLB DNS names (wait for them to be provisioned)
MILAN_MONGO_NLB=$(kubectl --context k8s-dr-milan get svc -n dev mongo-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_MONGO_NLB=$(kubectl --context k8s-dr-dublin get svc -n dev mongo-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get private hosted zone ID from Pulumi
ZONE_ID=$(pulumi stack output privateHostedZoneId -s milan)

# Create Route53 failover records
# This step requires AWS CLI and manual configuration
```

## Phase 5: Verification

### 5.1 Check Infrastructure
```bash
# Source fish helpers
source infrastructure/scripts/k8s-dr-helpers.fish

# Check both clusters
dr-status
dr-health

# Verify Velero is running and scheduled
kubectl get backupstoragelocations -n velero
kubectl get schedules -n velero
```

### 5.2 Test Application
```bash
# Get ALB URLs (after applications are deployed)
kubectl get ingress -n dev

# Test endpoints
curl https://<milan-alb>/joke
curl https://<dublin-alb>/joke
```

### 5.3 Test Cross-Region MongoDB
```bash
# Check replica set status
kubectl exec -n dev mongodb-0 -- mongosh --eval "rs.status()"
```

## Phase 6: DNS and Global Failover (Manual)

### 6.1 Extract ALB Information
```bash
# Get ALB DNS names
MILAN_ALB=$(kubectl --context k8s-dr-milan get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_ALB=$(kubectl --context k8s-dr-dublin get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get ALB ARNs and Zone IDs (requires AWS CLI)
# See DNS_DEPLOYMENT_GUIDE.md for detailed commands
```

### 6.2 Deploy DNS Component
```bash
# After getting ALB details, configure Pulumi and deploy DNS
# This creates Route53 hosted zone and Global Accelerator
```

## Phase 7: Run DR Scenarios

### 7.1 Scenario 1: Data Loss
```bash
cd scenarios/scenario-1-data-loss
./inject.sh
./validate.sh
```

### 7.2 Scenario 2: Failover
```bash
cd scenarios/scenario-2-failover
./inject.sh
./validate.sh
```

### 7.3 Scenario 3: Health Checks
```bash
cd scenarios/scenario-3-health-checks
./inject-mongo-pool.sh
./validate.sh
```

## Important Notes

1. **EKS Version**: Now using EKS 1.33 with latest addon versions (vpc-cni, ebs-csi-driver, coredns, kube-proxy)

2. **Velero Backups**: Automatically configured with:
   - MongoDB backups every 6 hours
   - DadJokes app backups every 6 hours
   - 7-day retention policy
   - Cross-region bucket replication (if enabled)

3. **CoreDNS**: The configmap patch is provided but must be applied manually after cluster creation

4. **MongoDB Multi-Region**: Default deployment uses single-member MongoDB. Must manually switch to multi-region configuration.

5. **DNS/Global Accelerator**: Cannot be automated due to ALB dependency. Deploy applications first, then configure DNS.

6. **Namespace**: All applications deploy to the `dev` namespace, which Velero is configured to backup.

7. **Cross-Region Latency**: Expect ~20-30ms latency between Milan and Dublin for MongoDB replication. 