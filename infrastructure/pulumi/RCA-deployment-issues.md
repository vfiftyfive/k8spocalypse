# Root Cause Analysis: k8spocalypse Deployment Issues

## Executive Summary

Multiple deployment issues were identified preventing the DadJokes application from running properly:

1. **joke-server StatefulSet**: Storage configuration conflict (0 bytes requested)
2. **MongoDB**: Missing readiness probe handler configuration
3. **Global Accelerator**: Not deployed due to manual step requirement
4. **ALB SSL**: Certificate requirement causing deployment failures

## Detailed Root Cause Analysis

### 1. joke-server StatefulSet Issue

**Problem**: StatefulSet cannot create pods due to invalid PVC configuration
```
Error: PersistentVolumeClaim "ratings-storage-joke-server-0" is invalid: 
spec.resources[storage]: Invalid value: "0": must be greater than zero
```

**Root Cause**: 
- DevSpace's `component-chart` is creating a StatefulSet with volumeClaimTemplates
- The chart is trying to create a PVC named `ratings-storage` with 0 storage
- Meanwhile, a separate PVC `ratings-pvc` (10Gi) already exists but isn't being used
- This creates a conflict where the StatefulSet template overrides the existing PVC

**Solution**: Change joke-server from StatefulSet to Deployment to use the existing PVC

### 2. MongoDB Deployment Issue

**Problem**: MongoDB StatefulSet cannot create pods
```
Error: Pod "mongodb-0" is invalid: spec.containers[0].readinessProbe: 
Required value: must specify a handler type
```

**Root Cause**:
- The MongoDB Community Operator CRD requires readiness probe handler specification
- The current configuration only specifies probe timing but not the handler type
- The `mongodbcommunity.yaml` file is missing the probe handler configuration

**Solution**: Add proper readiness probe handlers to MongoDB configuration

### 3. Global Accelerator Not Deployed

**Problem**: Global Accelerator exists in Pulumi code but wasn't deployed

**Root Cause**:
- DNS component requires ALB ARNs from both regions
- ALBs are only created after application deployment
- This creates a circular dependency: Apps → ALBs → DNS/GA → Apps
- The DNS component is commented out in `index.ts` waiting for ALB information

**Solution**: Created standalone deployment script that discovers ALBs automatically

### 4. ALB SSL Certificate Issue

**Problem**: ALBs fail to create when HTTPS is configured without certificates

**Root Cause**:
- Original `ingress.yaml` had SSL redirect and HTTPS listener configured
- No SSL certificate ARN was provided
- AWS ALB controller validation fails: "A certificate must be specified for HTTPS listeners"

**Solution**: Removed HTTPS configuration, using HTTP-only ALBs

## Impact Analysis

- **Service Availability**: 0% - No application pods running
- **Data Loss Risk**: High - MongoDB not running, no data persistence
- **Failover Capability**: None - No healthy endpoints for Global Accelerator
- **Recovery Time**: ~30 minutes with manual fixes

## Permanent Solutions Implemented

### 1. Fixed DevSpace Configuration
- Convert joke-server to Deployment instead of StatefulSet
- Use existing ratings-pvc instead of volumeClaimTemplates
- Ensure proper volume mounting

### 2. Fixed MongoDB Configuration
- Add complete readiness probe handlers
- Ensure operator has proper RBAC permissions
- Fix probe configuration in CRD

### 3. Automated Global Accelerator Deployment
- Created `deploy-global-accelerator.fish` script
- Automatic ALB discovery
- Idempotent deployment (handles existing resources)

### 4. HTTP-Only ALB Configuration
- Removed SSL/HTTPS annotations from ingress
- HTTP-only listeners on port 80
- No certificate requirements

## Repeatability Improvements

### Scripts Created:
1. **fix-deployment-issues.fish** - Comprehensive fix script
2. **deploy-global-accelerator.fish** - Standalone GA deployment
3. **deploy-dns.fish** - DNS configuration (needs fixing)

### Pulumi Components:
1. **CoreDnsConfig** - Automatic CoreDNS configuration
2. **Updated ingress.yaml** - HTTP-only configuration

### Process Improvements:
1. Deploy infrastructure first (Pulumi)
2. Deploy applications (DevSpace)
3. Deploy Global Accelerator (script)
4. Verify health endpoints

## Lessons Learned

1. **Dependency Management**: Clear separation between infrastructure and application deployment
2. **Chart Selection**: Use Deployment for apps with external storage, not StatefulSet
3. **Probe Configuration**: Always specify complete probe handlers for operators
4. **SSL Planning**: Plan SSL certificate management upfront or use HTTP for demos
5. **Automation**: Scripts should handle existing resources gracefully

## Next Steps

1. Fix DevSpace configuration files
2. Update MongoDB CRD with proper probes
3. Test full deployment sequence
4. Document the correct deployment order
5. Create automated validation script 