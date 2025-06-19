#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Initializing Pulumi Project${NC}\n"

# Navigate to Pulumi directory
cd ../pulumi

# Login to local backend
echo -e "${YELLOW}Logging in to local Pulumi backend...${NC}"
pulumi login --local

# Create Milan stack
echo -e "\n${YELLOW}Creating Milan stack...${NC}"
pulumi stack init milan || echo -e "${YELLOW}Milan stack already exists${NC}"

# Set Milan stack configuration
echo -e "\n${YELLOW}Setting Milan stack configuration...${NC}"
pulumi stack select milan
pulumi config set aws:region eu-south-1
pulumi config set k8s-multi-region-dr:projectName k8s-multi-region-dr
pulumi config set k8s-multi-region-dr:environment milan
pulumi config set k8s-multi-region-dr:vpcCidr 10.0.0.0/16
pulumi config set k8s-multi-region-dr:clusterName k8s-dr-milan
pulumi config set k8s-multi-region-dr:nodeInstanceType t3.large
pulumi config set k8s-multi-region-dr:desiredCapacity 3
pulumi config set k8s-multi-region-dr:minSize 1
pulumi config set k8s-multi-region-dr:maxSize 6

# Create Dublin stack
echo -e "\n${YELLOW}Creating Dublin stack...${NC}"
pulumi stack init dublin || echo -e "${YELLOW}Dublin stack already exists${NC}"

# Set Dublin stack configuration
echo -e "\n${YELLOW}Setting Dublin stack configuration...${NC}"
pulumi stack select dublin
pulumi config set aws:region eu-west-1
pulumi config set k8s-multi-region-dr:projectName k8s-multi-region-dr
pulumi config set k8s-multi-region-dr:environment dublin
pulumi config set k8s-multi-region-dr:vpcCidr 10.1.0.0/16
pulumi config set k8s-multi-region-dr:clusterName k8s-dr-dublin
pulumi config set k8s-multi-region-dr:nodeInstanceType t3.large
pulumi config set k8s-multi-region-dr:desiredCapacity 3
pulumi config set k8s-multi-region-dr:minSize 1
pulumi config set k8s-multi-region-dr:maxSize 6

# Switch back to Milan
echo -e "\n${YELLOW}Switching to Milan stack...${NC}"
pulumi stack select milan

echo -e "\n${GREEN}Initialization complete!${NC}"
echo -e "\nCurrent stack: ${YELLOW}milan${NC}"
echo -e "\nNext steps:"
echo -e "1. Deploy Milan VPC: ${YELLOW}pulumi up${NC}"
echo -e "2. Or preview first: ${YELLOW}pulumi preview${NC}" 