#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up K8s Multi-Region DR Demo${NC}"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check for Pulumi
if ! command -v pulumi &> /dev/null; then
    echo -e "${RED}Pulumi is not installed. Please install it first: https://www.pulumi.com/docs/get-started/install/${NC}"
    exit 1
fi

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it first: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
fi

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js is not installed. Please install it first: https://nodejs.org/${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}AWS credentials not configured. Please run 'aws configure'${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites met!${NC}"

# Navigate to Pulumi directory
cd ../pulumi

# Install dependencies
echo -e "\n${YELLOW}Installing Node.js dependencies...${NC}"
npm install

# Initialize Pulumi stacks
echo -e "\n${YELLOW}Initializing Pulumi stacks...${NC}"

# Login to Pulumi (using local backend for demo)
pulumi login --local

# Initialize Milan stack
echo -e "\n${YELLOW}Initializing Milan stack...${NC}"
pulumi stack init milan --secrets-provider=passphrase

# Initialize Dublin stack  
echo -e "\n${YELLOW}Initializing Dublin stack...${NC}"
pulumi stack init dublin --secrets-provider=passphrase

# Select Milan as default
pulumi stack select milan

echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "\nNext steps:"
echo -e "1. Deploy Milan infrastructure: ${YELLOW}npm run deploy:milan${NC}"
echo -e "2. Deploy Dublin infrastructure: ${YELLOW}npm run deploy:dublin${NC}"
echo -e "\nOr use Pulumi directly:"
echo -e "- ${YELLOW}pulumi up -s milan${NC}"
echo -e "- ${YELLOW}pulumi up -s dublin${NC}" 