#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Verifying Networking Setup${NC}\n"

# Get the current stack
STACK=$(pulumi stack --show-name 2>/dev/null)
if [ -z "$STACK" ]; then
    echo -e "${RED}No Pulumi stack selected. Please select a stack first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Current stack: ${STACK}${NC}"

# Get stack outputs
echo -e "\n${YELLOW}Getting stack outputs...${NC}"

# Get VPC ID
VPC_ID=$(pulumi stack output vpcId 2>/dev/null)
if [ -z "$VPC_ID" ]; then
    echo -e "${RED}VPC not found. Has the stack been deployed?${NC}"
    exit 1
fi

echo -e "\n${GREEN}VPC Information:${NC}"
echo -e "VPC ID: ${VPC_ID}"

# Get VPC details
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].[CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text

# Get subnets
echo -e "\n${GREEN}Subnets:${NC}"

# Public subnets
echo -e "\n${YELLOW}Public Subnets:${NC}"
PUBLIC_SUBNETS=$(pulumi stack output publicSubnetIds -j 2>/dev/null | jq -r '.[]')
for subnet in $PUBLIC_SUBNETS; do
    echo -e "\nSubnet ID: $subnet"
    aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].[AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text
done

# Private subnets
echo -e "\n${YELLOW}Private Subnets:${NC}"
PRIVATE_SUBNETS=$(pulumi stack output privateSubnetIds -j 2>/dev/null | jq -r '.[]')
for subnet in $PRIVATE_SUBNETS; do
    echo -e "\nSubnet ID: $subnet"
    aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].[AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text
done

# NAT Gateways
echo -e "\n${GREEN}NAT Gateways:${NC}"
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
    --query 'NatGateways[].[NatGatewayId,SubnetId,Tags[?Key==`Name`].Value|[0]]' --output table

# Internet Gateway
echo -e "\n${GREEN}Internet Gateway:${NC}"
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[0].[InternetGatewayId,Tags[?Key==`Name`].Value|[0]]' --output text

# Security Groups
echo -e "\n${GREEN}EKS Security Group:${NC}"
SG_ID=$(pulumi stack output eksSecurityGroupId 2>/dev/null)
if [ ! -z "$SG_ID" ]; then
    echo -e "Security Group ID: $SG_ID"
    aws ec2 describe-security-groups --group-ids $SG_ID \
        --query 'SecurityGroups[0].[GroupName,Description]' --output text
fi

# VPC Endpoints
echo -e "\n${GREEN}VPC Endpoints:${NC}"
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State]' --output table

# Summary
echo -e "\n${GREEN}Network Summary:${NC}"
pulumi stack output networkingSummary -j 2>/dev/null | jq '.'

echo -e "\n${GREEN}Verification complete!${NC}" 