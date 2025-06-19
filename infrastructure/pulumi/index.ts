import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";
import { Networking } from "./components/networking";
import { EksCluster } from "./components/eks-cluster";

// Get configuration
const config = new pulumi.Config();
const projectName = config.require("projectName");
const environment = config.require("environment");
const awsConfig = new pulumi.Config("aws");
const region = awsConfig.require("region");

// Get VPC configuration
const vpcCidr = config.require("vpcCidr");

// Get EKS configuration
const clusterName = config.require("clusterName");
const nodeInstanceType = config.require("nodeInstanceType");
const desiredCapacity = config.requireNumber("desiredCapacity");
const minSize = config.requireNumber("minSize");
const maxSize = config.requireNumber("maxSize");

// Export helper function for tagging
export function getTags(additionalTags?: Record<string, string>) {
    return {
        Project: projectName,
        Environment: environment,
        ManagedBy: "Pulumi",
        Region: region,
        ...additionalTags,
    };
}

// Main infrastructure will be defined here based on the current region
const isMainRegion = region === "eu-south-1"; // Milan
const isDRRegion = region === "eu-west-1"; // Dublin

pulumi.log.info(`Deploying to region: ${region}`);
pulumi.log.info(`Is main region: ${isMainRegion}`);
pulumi.log.info(`Is DR region: ${isDRRegion}`);

// Create networking infrastructure
const networking = new Networking("main", {
    vpcCidr: vpcCidr,
    projectName: projectName,
    environment: environment,
    region: region,
    tags: getTags(),
    createEcrEndpoints: false, // Disable ECR endpoints as they're not available in Milan
});

// Create EKS cluster
const eksCluster = new EksCluster("main", {
    clusterName: clusterName,
    vpcId: networking.vpcId,
    privateSubnetIds: networking.privateSubnetIds,
    publicSubnetIds: networking.publicSubnetIds,
    nodeInstanceType: nodeInstanceType,
    desiredCapacity: desiredCapacity,
    minSize: minSize,
    maxSize: maxSize,
    eksVersion: "1.29",
    tags: getTags(),
});

// Export the region for reference
export const currentRegion = region;
export const projectTags = getTags();

// Export networking outputs
export const vpcId = networking.vpcId;
export const publicSubnetIds = networking.publicSubnetIds;
export const privateSubnetIds = networking.privateSubnetIds;
export const eksSecurityGroupId = networking.eksSecurityGroup.id;

// Export VPC CIDR for reference
export const vpcCidr_ = vpcCidr;

// Export availability zones
export const availabilityZones = pulumi.output(aws.getAvailabilityZones({
    state: "available",
})).apply(azs => azs.names.slice(0, 3));

// Export EKS cluster outputs
export const eksClusterName = eksCluster.clusterName;
export const eksClusterEndpoint = eksCluster.clusterEndpoint;
export const eksOidcProviderArn = eksCluster.oidcProviderArn;
export const eksOidcProviderUrl = eksCluster.oidcProviderUrl;

// Export kubeconfig
export const kubeconfig = pulumi.secret(eksCluster.kubeconfig);

// Summary output
export const networkingSummary = pulumi.all([
    networking.vpcId,
    networking.publicSubnetIds,
    networking.privateSubnetIds,
]).apply(([vpcId, publicSubnets, privateSubnets]) => ({
    vpcId: vpcId,
    publicSubnetsCount: publicSubnets.length,
    privateSubnetsCount: privateSubnets.length,
    region: region,
    environment: environment,
}));

// EKS summary output
export const eksSummary = pulumi.all([
    eksCluster.clusterName,
    eksCluster.clusterEndpoint,
    eksCluster.nodeGroup.nodeGroup.id,
]).apply(([clusterName, endpoint, nodeGroupId]) => ({
    clusterName: clusterName,
    clusterEndpoint: endpoint,
    nodeGroupId: nodeGroupId,
    region: region,
    eksVersion: "1.29",
    nodeInstanceType: nodeInstanceType,
    nodeCount: desiredCapacity,
})); 