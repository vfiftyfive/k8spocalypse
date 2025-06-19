#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Verifying EKS Cluster Setup${NC}\n"

# Get the current stack
STACK=$(pulumi stack --show-name 2>/dev/null)
if [ -z "$STACK" ]; then
    echo -e "${RED}No Pulumi stack selected. Please select a stack first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Current stack: ${STACK}${NC}"

# Get cluster name
CLUSTER_NAME=$(pulumi stack output eksClusterName 2>/dev/null)
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}EKS cluster not found. Has the stack been deployed?${NC}"
    exit 1
fi

REGION=$(pulumi stack output currentRegion 2>/dev/null)

echo -e "\n${GREEN}EKS Cluster Information:${NC}"
echo -e "Cluster Name: ${CLUSTER_NAME}"
echo -e "Region: ${REGION}"

# Update kubeconfig
echo -e "\n${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Test kubectl connection
echo -e "\n${YELLOW}Testing kubectl connection...${NC}"
kubectl cluster-info

# Get node information
echo -e "\n${GREEN}Node Information:${NC}"
kubectl get nodes -o wide

# Check node status
echo -e "\n${GREEN}Node Status:${NC}"
kubectl describe nodes | grep -E "Name:|Status:|Roles:|Instance-Id:|Internal-IP:|External-IP:" | grep -B1 -A5 "Name:"

# Check system pods
echo -e "\n${GREEN}System Pods:${NC}"
kubectl get pods -n kube-system

# Check EBS CSI Driver
echo -e "\n${GREEN}EBS CSI Driver Status:${NC}"
kubectl get pods -n kube-system | grep ebs-csi

# Check storage classes
echo -e "\n${GREEN}Storage Classes:${NC}"
kubectl get storageclass

# Get EKS summary
echo -e "\n${GREEN}EKS Summary:${NC}"
pulumi stack output eksSummary -j 2>/dev/null | jq '.'

# Save kubeconfig to file
echo -e "\n${YELLOW}Saving kubeconfig to file...${NC}"
KUBECONFIG_FILE="$HOME/.kube/config-${CLUSTER_NAME}"
pulumi stack output kubeconfig --show-secrets > $KUBECONFIG_FILE
chmod 600 $KUBECONFIG_FILE
echo -e "${GREEN}Kubeconfig saved to: ${KUBECONFIG_FILE}${NC}"
echo -e "To use this kubeconfig: export KUBECONFIG=${KUBECONFIG_FILE}"

echo -e "\n${GREEN}Verification complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Create a storage class for GP3 volumes"
echo -e "2. Install core add-ons (metrics-server, load balancer controller, etc.)"
echo -e "3. Deploy applications" 