import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";
import { Networking } from "./components/networking";

// Get configuration
const config = new pulumi.Config();
const projectName = config.require("projectName");
const environment = config.require("environment");
const awsConfig = new pulumi.Config("aws");
const region = awsConfig.require("region");

// Get VPC configuration
const vpcCidr = config.require("vpcCidr");

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