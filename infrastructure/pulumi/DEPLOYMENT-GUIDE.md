# k8spocalypse Deployment Guide

## Overview

This guide provides the best repeatable approach for deploying the k8spocalypse multi-region disaster recovery demo, addressing all known issues and providing automated solutions.

## Deployment Approach Comparison

### Option 1: Pulumi + Scripts (Recommended)

**Pros:**
- Infrastructure as Code for AWS resources
- Version control and drift detection
- Automated cross-region connectivity
- Proper state management

**Cons:**
- Complex dependency management
- DNS/GA requires post-deployment step
- Learning curve for Pulumi

**Best for:** Production environments, team collaboration, long-term maintenance

### Option 2: Pure Scripts (Alternative)

**Pros:**
- Simple and direct
- No state management complexity
- Easy to understand and modify
- Faster initial deployment

**Cons:**
- No drift detection
- Manual resource tracking
- Harder to clean up

**Best for:** Demos, workshops, temporary environments

## Recommended Deployment Process

### Prerequisites

1. **AWS Setup:**
   ```fish
   aws sso login
   yawsso
   export AWS_PROFILE=k8s-dr
   ```

2. **Tools Required:**
   - Pulumi CLI
   - kubectl
   - helm
   - DevSpace (optional)
   - SOPS
   - jq

### Step 1: Deploy Infrastructure with Pulumi

```fish
cd infrastructure/pulumi

# Deploy Milan (Primary)
pulumi stack select milan
pulumi up --yes

# Deploy Dublin (Secondary)
pulumi stack select dublin
pulumi up --yes

# Enable cross-region connectivity
./deploy-both-regions.fish
```

### Step 2: Deploy Applications

**Option A: Using Fixed Scripts (Recommended)**
```fish
cd infrastructure/pulumi
./deploy-complete-solution.fish
```

**Option B: Manual DevSpace Deployment**
```fish
cd applications/dadjokes/deploy/devspace

# Deploy to Milan
kubectl config use-context arn:aws:eks:eu-south-1:$ACCOUNT:cluster/k8s-dr-milan
REGION=milan devspace deploy --namespace dev

# Deploy to Dublin
kubectl config use-context arn:aws:eks:eu-west-1:$ACCOUNT:cluster/k8s-dr-dublin
REGION=dublin devspace deploy --namespace dev
```

### Step 3: Deploy Global Accelerator

```fish
cd infrastructure/pulumi
./deploy-global-accelerator.fish
```

## Fixed Issues

1. **joke-server StatefulSet → Deployment**
   - File: `custom-resources/joke-server-deployment.yaml`
   - Uses existing `ratings-pvc` instead of volumeClaimTemplates

2. **MongoDB Readiness Probes**
   - File: `custom-resources/mongodb.yaml`
   - Added proper `exec` handlers for probes

3. **ALB SSL Certificates**
   - File: `custom-resources/ingress.yaml`
   - Removed HTTPS configuration, HTTP-only

4. **Global Accelerator Automation**
   - Script: `deploy-global-accelerator.fish`
   - Automatic ALB discovery and configuration

## Script Evaluation

### deploy-complete-solution.fish ⭐⭐⭐⭐⭐
- **Purpose:** Complete end-to-end deployment
- **Reliability:** Excellent - handles all edge cases
- **Repeatability:** Excellent - idempotent operations
- **Recommendation:** Use this for reliable deployments

### deploy-global-accelerator.fish ⭐⭐⭐⭐⭐
- **Purpose:** Global Accelerator deployment
- **Reliability:** Excellent - handles existing resources
- **Repeatability:** Excellent - can run multiple times
- **Recommendation:** Best solution for GA deployment

### fix-deployment-issues.fish ⭐⭐⭐
- **Purpose:** Fix existing deployments
- **Reliability:** Good - but assumes Pulumi changes
- **Repeatability:** Limited - one-time fix
- **Recommendation:** Use for troubleshooting only

### deploy-dns.fish ⭐⭐
- **Purpose:** DNS and GA via Pulumi
- **Reliability:** Poor - complex Pulumi setup
- **Repeatability:** Poor - state issues
- **Recommendation:** Avoid, use deploy-global-accelerator.fish

## Verification Commands

```fish
# Check pod status
kubectl get pods -n dev

# Check MongoDB
kubectl get mongodbcommunity -n dev

# Check ALBs
kubectl get ingress -n dev

# Test endpoints
curl http://<ALB-DNS>/health

# Check Global Accelerator
aws globalaccelerator list-accelerators --region us-west-2
```

## Troubleshooting

### Issue: MongoDB stuck in Pending
```fish
kubectl describe mongodbcommunity mongodb -n dev
kubectl logs -n dev deployment/mongodb-kubernetes-operator
```

### Issue: joke-server not starting
```fish
kubectl describe pod -n dev -l app=joke-server
kubectl logs -n dev -l app=joke-server
```

### Issue: ALB not creating
```fish
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl describe ingress -n dev dadjokes-ingress
```

## Clean Up

```fish
# Delete applications
kubectl delete namespace dev

# Delete Global Accelerator
aws globalaccelerator list-accelerators --region us-west-2 | \
  jq -r '.Accelerators[] | select(.Name | contains("dadjokes")) | .AcceleratorArn' | \
  xargs -I {} aws globalaccelerator delete-accelerator --accelerator-arn {} --region us-west-2

# Delete infrastructure
pulumi destroy --stack milan --yes
pulumi destroy --stack dublin --yes
```

## Best Practices

1. **Always deploy infrastructure first**
2. **Use the complete solution script for applications**
3. **Deploy Global Accelerator last**
4. **Monitor health endpoints after deployment**
5. **Keep MongoDB and joke-server configurations in sync**

## Summary

The recommended approach combines Pulumi for infrastructure management with targeted scripts for application deployment. The `deploy-complete-solution.fish` script provides the most reliable and repeatable deployment experience, handling all known issues automatically. 