#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME="k8s-dr-milan"
REGION="eu-south-1"
ACTION=""
VOLUME_ID=""
SNAPSHOT_ID=""
PVC_NAME=""
NAMESPACE="default"

# Help function
show_help() {
    echo "EBS Snapshot Management Script"
    echo ""
    echo "Usage: $0 [OPTIONS] ACTION"
    echo ""
    echo "Actions:"
    echo "  list-volumes      List all EBS volumes in the cluster"
    echo "  list-snapshots    List all EBS snapshots for the cluster"
    echo "  create-snapshot   Create a snapshot of a volume"
    echo "  restore-snapshot  Restore a volume from a snapshot"
    echo "  copy-snapshot     Copy a snapshot to another region"
    echo ""
    echo "Options:"
    echo "  -c, --cluster     Cluster name (default: k8s-dr-milan)"
    echo "  -r, --region      AWS region (default: eu-south-1)"
    echo "  -v, --volume      Volume ID for snapshot operations"
    echo "  -s, --snapshot    Snapshot ID for restore operations"
    echo "  -p, --pvc         PVC name for K8s operations"
    echo "  -n, --namespace   Kubernetes namespace (default: default)"
    echo "  -h, --help        Show this help message"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -v|--volume)
            VOLUME_ID="$2"
            shift 2
            ;;
        -s|--snapshot)
            SNAPSHOT_ID="$2"
            shift 2
            ;;
        -p|--pvc)
            PVC_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            ACTION="$1"
            shift
            ;;
    esac
done

# Validate action
if [ -z "$ACTION" ]; then
    echo -e "${RED}Error: No action specified${NC}"
    show_help
    exit 1
fi

# Function to list volumes
list_volumes() {
    echo -e "${GREEN}Listing EBS volumes for cluster: $CLUSTER_NAME${NC}"
    
    aws ec2 describe-volumes \
        --region $REGION \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
        --query 'Volumes[*].[VolumeId,Size,State,CreateTime,Tags[?Key==`kubernetes.io/created-for/pvc/name`].Value|[0]]' \
        --output table
}

# Function to list snapshots
list_snapshots() {
    echo -e "${GREEN}Listing EBS snapshots for cluster: $CLUSTER_NAME${NC}"
    
    aws ec2 describe-snapshots \
        --region $REGION \
        --owner-ids self \
        --filters "Name=tag:Cluster,Values=$CLUSTER_NAME" \
        --query 'Snapshots[*].[SnapshotId,VolumeId,VolumeSize,StartTime,State,Description]' \
        --output table
}

# Function to create snapshot
create_snapshot() {
    if [ -z "$VOLUME_ID" ] && [ -z "$PVC_NAME" ]; then
        echo -e "${RED}Error: Either --volume or --pvc must be specified${NC}"
        exit 1
    fi
    
    # If PVC name is provided, get the volume ID
    if [ -n "$PVC_NAME" ]; then
        echo -e "${YELLOW}Finding volume for PVC: $PVC_NAME in namespace: $NAMESPACE${NC}"
        
        # Get PV name from PVC
        PV_NAME=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}' 2>/dev/null)
        
        if [ -z "$PV_NAME" ]; then
            echo -e "${RED}Error: PVC $PVC_NAME not found in namespace $NAMESPACE${NC}"
            exit 1
        fi
        
        # Get volume ID from PV
        VOLUME_ID=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.csi.volumeHandle}' 2>/dev/null)
        
        if [ -z "$VOLUME_ID" ]; then
            echo -e "${RED}Error: Could not find volume ID for PV $PV_NAME${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Found volume: $VOLUME_ID${NC}"
    fi
    
    # Create snapshot
    echo -e "${YELLOW}Creating snapshot for volume: $VOLUME_ID${NC}"
    
    SNAPSHOT_ID=$(aws ec2 create-snapshot \
        --region $REGION \
        --volume-id $VOLUME_ID \
        --description "Manual snapshot for PVC $PVC_NAME in namespace $NAMESPACE" \
        --tag-specifications "ResourceType=snapshot,Tags=[{Key=Cluster,Value=$CLUSTER_NAME},{Key=PVC,Value=$PVC_NAME},{Key=Namespace,Value=$NAMESPACE},{Key=Type,Value=Manual}]" \
        --query 'SnapshotId' \
        --output text)
    
    echo -e "${GREEN}Snapshot created: $SNAPSHOT_ID${NC}"
    
    # Wait for snapshot to complete
    echo -e "${YELLOW}Waiting for snapshot to complete...${NC}"
    aws ec2 wait snapshot-completed --region $REGION --snapshot-ids $SNAPSHOT_ID
    
    echo -e "${GREEN}Snapshot completed successfully!${NC}"
    
    # Show snapshot details
    aws ec2 describe-snapshots \
        --region $REGION \
        --snapshot-ids $SNAPSHOT_ID \
        --query 'Snapshots[0]'
}

# Function to restore from snapshot
restore_snapshot() {
    if [ -z "$SNAPSHOT_ID" ]; then
        echo -e "${RED}Error: --snapshot must be specified${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Creating volume from snapshot: $SNAPSHOT_ID${NC}"
    
    # Get snapshot details
    SNAPSHOT_INFO=$(aws ec2 describe-snapshots \
        --region $REGION \
        --snapshot-ids $SNAPSHOT_ID \
        --query 'Snapshots[0].[VolumeSize,VolumeId]' \
        --output text)
    
    VOLUME_SIZE=$(echo $SNAPSHOT_INFO | cut -d' ' -f1)
    ORIGINAL_VOLUME_ID=$(echo $SNAPSHOT_INFO | cut -d' ' -f2)
    
    # Create volume from snapshot
    NEW_VOLUME_ID=$(aws ec2 create-volume \
        --region $REGION \
        --availability-zone ${REGION}a \
        --snapshot-id $SNAPSHOT_ID \
        --volume-type gp3 \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=restored-from-$SNAPSHOT_ID},{Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=owned}]" \
        --query 'VolumeId' \
        --output text)
    
    echo -e "${GREEN}Created volume: $NEW_VOLUME_ID${NC}"
    
    # Wait for volume to be available
    echo -e "${YELLOW}Waiting for volume to be available...${NC}"
    aws ec2 wait volume-available --region $REGION --volume-ids $NEW_VOLUME_ID
    
    echo -e "${GREEN}Volume is ready!${NC}"
    echo -e "${BLUE}To use this volume in Kubernetes:${NC}"
    echo "1. Create a PV with volumeHandle: $NEW_VOLUME_ID"
    echo "2. Create a PVC that binds to this PV"
}

# Function to copy snapshot to another region
copy_snapshot() {
    if [ -z "$SNAPSHOT_ID" ]; then
        echo -e "${RED}Error: --snapshot must be specified${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Enter destination region (e.g., eu-west-1):${NC}"
    read DEST_REGION
    
    echo -e "${GREEN}Copying snapshot $SNAPSHOT_ID to region $DEST_REGION${NC}"
    
    # Get snapshot description
    DESCRIPTION=$(aws ec2 describe-snapshots \
        --region $REGION \
        --snapshot-ids $SNAPSHOT_ID \
        --query 'Snapshots[0].Description' \
        --output text)
    
    # Copy snapshot
    COPIED_SNAPSHOT_ID=$(aws ec2 copy-snapshot \
        --region $DEST_REGION \
        --source-region $REGION \
        --source-snapshot-id $SNAPSHOT_ID \
        --description "Copy of $SNAPSHOT_ID from $REGION - $DESCRIPTION" \
        --query 'SnapshotId' \
        --output text)
    
    echo -e "${GREEN}Snapshot copy initiated: $COPIED_SNAPSHOT_ID in region $DEST_REGION${NC}"
    echo -e "${YELLOW}Note: Cross-region copy may take several minutes to complete${NC}"
}

# Execute action
case $ACTION in
    list-volumes)
        list_volumes
        ;;
    list-snapshots)
        list_snapshots
        ;;
    create-snapshot)
        create_snapshot
        ;;
    restore-snapshot)
        restore_snapshot
        ;;
    copy-snapshot)
        copy_snapshot
        ;;
    *)
        echo -e "${RED}Error: Unknown action '$ACTION'${NC}"
        show_help
        exit 1
        ;;
esac 