# Step 4: Storage Configuration

This guide covers the storage configuration for the Kubernetes multi-region disaster recovery setup, including EBS CSI driver, storage classes, and snapshot policies.

## Prerequisites

- Completed Step 3 (EKS cluster setup)
- AWS CLI configured with appropriate permissions
- kubectl configured to access the EKS cluster

## Components Overview

The storage configuration includes:
- GP3 storage class (default)
- EBS CSI driver configuration
- Volume snapshot configuration (requires additional setup)
- DLM (Data Lifecycle Manager) policies for automated snapshots
- Cross-region snapshot replication (for DR)

## Storage Class Configuration

The infrastructure automatically creates a GP3 storage class with the following features:
- **Type**: GP3 (latest generation EBS volumes)
- **IOPS**: 3000
- **Throughput**: 125 MB/s
- **Encryption**: Enabled by default
- **Volume Expansion**: Allowed
- **Binding Mode**: WaitForFirstConsumer

## Installing the CSI Snapshot Controller

Before you can use VolumeSnapshots, you need to install the CSI Snapshot Controller and CRDs:

```bash
# Install the CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.3/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.3/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.3/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml

# Install the snapshot controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.3/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-6.3/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

# Verify the controller is running
kubectl get pods -n kube-system | grep snapshot-controller
```

After installing the snapshot controller, you can uncomment the VolumeSnapshotClass creation in `infrastructure/pulumi/components/storage.ts` and run `pulumi up` again.

## Automated Snapshot Policy

## Components Created

### Storage Class (GP3)
- **Type**: GP3 (latest generation EBS volumes)
- **IOPS**: 3000 (baseline)
- **Throughput**: 125 MB/s
- **Encryption**: Enabled by default
- **Volume Expansion**: Allowed
- **Binding Mode**: WaitForFirstConsumer (optimal for multi-AZ)

### Volume Snapshot Class
- **Driver**: EBS CSI Driver
- **Deletion Policy**: Retain (snapshots persist even if VolumeSnapshot is deleted)
- **Tagging**: Automatic tagging with cluster name

### DLM (Data Lifecycle Manager) Policy
- **Schedule**: Hourly snapshots
- **Retention**: Last 24 snapshots
- **Target**: All EBS volumes tagged with cluster name
- **Tags**: Automatic tagging for organization

## Adding Storage to Your Deployment

**Note**: The EKS cluster must be fully deployed before adding storage configuration.

1. **Update index.ts to include storage**:
   ```typescript
   import { Storage } from "./components/storage";
   
   // After EKS cluster creation, add:
   const storage = new Storage("main", {
       clusterName: clusterName,
       k8sProvider: eksCluster.provider,
       oidcProviderArn: eksCluster.oidcProviderArn,
       oidcProviderUrl: eksCluster.oidcProviderUrl,
       region: region,
       tags: getTags(),
   });
   ```

2. **Deploy the update**:
   ```bash
   cd infrastructure/pulumi
   pulumi up -s milan
   ```

## Verification

### Check Storage Classes
```bash
kubectl get storageclass
```

Expected output:
```
NAME            PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             ebs.csi.aws.com    Delete          WaitForFirstConsumer   false                  10m
gp3 (default)   ebs.csi.aws.com    Delete          WaitForFirstConsumer   true                   5m
```

### Check Volume Snapshot Class
```bash
kubectl get volumesnapshotclass
```

### Test Storage with a Sample PVC
```bash
# Create a test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
EOF

# Check PVC status
kubectl get pvc test-pvc
```

## Snapshot Management

### Using the Snapshot Script
```bash
cd infrastructure/scripts

# List all volumes
./snapshot-management.sh list-volumes

# Create a manual snapshot
./snapshot-management.sh create-snapshot --pvc test-pvc

# List snapshots
./snapshot-management.sh list-snapshots

# Copy snapshot to Dublin (for DR)
./snapshot-management.sh copy-snapshot --snapshot snap-xxxxx
```

### Creating a Manual Snapshot via Kubernetes
```bash
# Create a VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  volumeSnapshotClassName: ebs-snapshot-class
  source:
    persistentVolumeClaimName: test-pvc
EOF

# Check snapshot status
kubectl get volumesnapshot test-snapshot
```

### Restoring from a Snapshot
```bash
# Create a new PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: test-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
```

## Automated Snapshots

The DLM policy automatically creates hourly snapshots of all EBS volumes. To verify:

```bash
# Check DLM policy
aws dlm get-lifecycle-policy --policy-id <policy-id> --region eu-south-1

# View automated snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:SnapshotType,Values=Automated" \
  --region eu-south-1
```

## Cross-Region Snapshot Replication

For disaster recovery, snapshots should be copied to Dublin:

```bash
# Manual copy
./snapshot-management.sh copy-snapshot --snapshot snap-xxxxx

# Or use AWS CLI
aws ec2 copy-snapshot \
  --source-region eu-south-1 \
  --source-snapshot-id snap-xxxxx \
  --destination-region eu-west-1 \
  --description "DR copy from Milan"
```

## Cost Considerations

- **GP3 Storage**: ~$0.08/GB-month (20% cheaper than GP2)
- **Snapshots**: ~$0.05/GB-month (incremental after first)
- **Cross-region transfer**: ~$0.02/GB

## Next Steps

Once storage is configured and tested:
1. Proceed to Step 5 for automated cross-region snapshot replication
2. Deploy your applications with persistent storage
3. Test disaster recovery scenarios 