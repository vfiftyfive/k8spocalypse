# DNS and Cross-Region Deployment Guide

## Current Status

### ✅ Working Components
- VPC Peering between Milan and Dublin
- Private hosted zone `internal.k8sdr.com`
- Cross-region security groups
- EKS clusters with AWS Load Balancer Controller
- Monitoring and Chaos Mesh

### ❌ Missing/Broken Components
1. **DNS/Global Accelerator** - Not deployed (requires ALB ARNs)
2. **MongoDB Cross-Region DNS** - Incorrect record types
3. **CoreDNS Configuration** - Not applied to clusters
4. **Multi-region MongoDB** - Disabled by default

## Step-by-Step Fix Guide

### 1. Deploy Applications First

```fish
# Deploy to Milan
cd applications/dadjokes/deploy/devspace
kubectl config use-context k8s-dr-milan
REGION=milan devspace deploy --namespace dev

# Deploy to Dublin
kubectl config use-context k8s-dr-dublin
REGION=dublin devspace deploy --namespace dev
```

### 2. Get ALB Information

```fish
# Get Milan ALB
kubectl get ingress -n dev dadjokes-ingress -o json | jq -r '.status.loadBalancer.ingress[0].hostname'
# Example: k8s-dev-dadjokes-abc123.eu-south-1.elb.amazonaws.com

# Get Dublin ALB
kubectl config use-context k8s-dr-dublin
kubectl get ingress -n dev dadjokes-ingress -o json | jq -r '.status.loadBalancer.ingress[0].hostname'
# Example: k8s-dev-dadjokes-xyz789.eu-west-1.elb.amazonaws.com
```

### 3. Deploy DNS and Global Accelerator

Create `deploy-dns.sh`:

```bash
#!/bin/bash

# Get ALB details
MILAN_ALB_DNS=$(kubectl --context k8s-dr-milan get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_ALB_DNS=$(kubectl --context k8s-dr-dublin get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get ALB ARNs
MILAN_ALB_ARN=$(aws elbv2 describe-load-balancers --region eu-south-1 --query "LoadBalancers[?DNSName=='${MILAN_ALB_DNS}'].LoadBalancerArn" --output text)
DUBLIN_ALB_ARN=$(aws elbv2 describe-load-balancers --region eu-west-1 --query "LoadBalancers[?DNSName=='${DUBLIN_ALB_DNS}'].LoadBalancerArn" --output text)

# Get ALB Zone IDs
MILAN_ALB_ZONE=$(aws elbv2 describe-load-balancers --region eu-south-1 --query "LoadBalancers[?DNSName=='${MILAN_ALB_DNS}'].CanonicalHostedZoneId" --output text)
DUBLIN_ALB_ZONE=$(aws elbv2 describe-load-balancers --region eu-west-1 --query "LoadBalancers[?DNSName=='${DUBLIN_ALB_DNS}'].CanonicalHostedZoneId" --output text)

echo "Milan ALB: $MILAN_ALB_DNS (ARN: $MILAN_ALB_ARN)"
echo "Dublin ALB: $DUBLIN_ALB_DNS (ARN: $DUBLIN_ALB_ARN)"

# Update Pulumi config
cd infrastructure/pulumi
pulumi config set milanAlbArn $MILAN_ALB_ARN
pulumi config set milanAlbDns $MILAN_ALB_DNS
pulumi config set milanAlbZone $MILAN_ALB_ZONE
pulumi config set dublinAlbArn $DUBLIN_ALB_ARN
pulumi config set dublinAlbDns $DUBLIN_ALB_DNS
pulumi config set dublinAlbZone $DUBLIN_ALB_ZONE

# Deploy DNS component separately
pulumi up -s dns --yes
```

### 4. Fix MongoDB Cross-Region

#### 4.1 Apply CoreDNS Configuration

```fish
# Apply to Milan
kubectl --context k8s-dr-milan apply -f infrastructure/pulumi/configs/coredns-patch.yaml

# Apply to Dublin
kubectl --context k8s-dr-dublin apply -f infrastructure/pulumi/configs/coredns-patch.yaml

# Restart CoreDNS
kubectl --context k8s-dr-milan rollout restart deployment/coredns -n kube-system
kubectl --context k8s-dr-dublin rollout restart deployment/coredns -n kube-system
```

#### 4.2 Create MongoDB NLB Services

```fish
# Create NLB in Milan
kubectl --context k8s-dr-milan apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mongodb-nlb
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

# Create NLB in Dublin
kubectl --context k8s-dr-dublin apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mongodb-nlb
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

#### 4.3 Create Route53 Records for MongoDB

```bash
# Get NLB DNS names
MILAN_MONGO_NLB=$(kubectl --context k8s-dr-milan get svc -n dev mongodb-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
DUBLIN_MONGO_NLB=$(kubectl --context k8s-dr-dublin get svc -n dev mongodb-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get private hosted zone ID
ZONE_ID=$(pulumi stack output privateHostedZoneId -s milan)

# Create CNAME records with failover
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "mongo.db.internal.k8sdr.com",
        "Type": "CNAME",
        "TTL": 10,
        "SetIdentifier": "Primary-Milan",
        "Failover": "PRIMARY",
        "ResourceRecords": [{"Value": "'$MILAN_MONGO_NLB'"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "mongo.db.internal.k8sdr.com",
        "Type": "CNAME",
        "TTL": 10,
        "SetIdentifier": "Secondary-Dublin",
        "Failover": "SECONDARY",
        "ResourceRecords": [{"Value": "'$DUBLIN_MONGO_NLB'"}]
      }
    }
  ]
}'
```

#### 4.4 Enable Multi-Region MongoDB

```fish
cd applications/dadjokes/deploy/devspace

# Switch to multi-region config
mv custom-resources/mongodb.yaml custom-resources/mongodb.yaml.single
mv custom-resources/mongodb-multiregion.yaml.disabled custom-resources/mongodb.yaml

# Update MongoDB config with cross-region member
sed -i 's/mongodb-2.internal.company.com/mongo.db.internal.k8sdr.com/' custom-resources/mongodb.yaml

# Apply in both regions
kubectl --context k8s-dr-milan apply -f custom-resources/mongodb.yaml
kubectl --context k8s-dr-dublin apply -f custom-resources/mongodb.yaml
```

### 5. Verify Everything Works

#### 5.1 Test Cross-Region MongoDB

```fish
# Test DNS resolution
kubectl --context k8s-dr-milan exec -n dev deployment/joke-server -- nslookup mongo.db.internal.k8sdr.com

# Check MongoDB replica status
kubectl --context k8s-dr-milan exec -n dev mongodb-0 -- mongosh --eval "rs.status()"
```

#### 5.2 Test Application Failover

```fish
# Test primary endpoint
curl https://$MILAN_ALB_DNS/health

# Test secondary endpoint  
curl https://$DUBLIN_ALB_DNS/health

# Test Global Accelerator (if deployed)
curl http://$(pulumi stack output globalAcceleratorIps -s dns | jq -r '.[0]')/health
```

## Scenario Validation

### Scenario 1: Data Loss
- ✅ MongoDB replica provides zero RPO
- ✅ EBS snapshots work with manual restore
- ✅ Velero backups scheduled every 6 hours

### Scenario 2: Internet Failover
- ⚠️ Requires DNS/Global Accelerator deployment
- ⚠️ Use ALB DNS directly for testing without Route53

### Scenario 3: Health Checks
- ✅ Application fault injection works
- ✅ Chaos Mesh can inject infrastructure failures
- ✅ Health endpoints properly implemented

## Manual Workarounds

If DNS/Global Accelerator deployment is blocked:

1. **Direct ALB Testing**: Use ALB DNS names directly
2. **Manual Failover**: Update local /etc/hosts file
3. **Health Check Testing**: Use kubectl port-forward

```fish
# Port forward for local testing
kubectl --context k8s-dr-milan port-forward -n dev svc/joke-server 8080:8080

# Test health endpoints
curl http://localhost:8080/health
curl http://localhost:8080/readyz
```

## Next Steps

1. Create a separate Pulumi stack for DNS/Global Accelerator
2. Automate ALB discovery after application deployment
3. Consider using External DNS for automatic Route53 updates
4. Test all three DR scenarios with current setup 