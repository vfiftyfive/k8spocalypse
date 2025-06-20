import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";
import { Networking } from "./components/networking";
import { EksCluster } from "./components/eks-cluster";
import { Storage } from "./components/storage";
import { Dns } from "./components/dns";
import { Backup } from "./components/backup";
import { CrossRegion } from "./components/cross-region";
import { ChaosMesh } from "./components/chaos-mesh";
import { Monitoring } from "./components/monitoring";
import { IngressSystem } from "./components/ingress-system";

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
  eksVersion: "1.33",
  tags: getTags(),
});

const storage = new Storage("main", {
  clusterName: clusterName,
  k8sProvider: eksCluster.provider,
  oidcProviderArn: eksCluster.oidcProviderArn,
  oidcProviderUrl: eksCluster.oidcProviderUrl,
  region: region,
  tags: getTags(),
});

// Create backup infrastructure
const backup = new Backup("main", {
  clusterName: clusterName,
  k8sProvider: eksCluster.provider,
  oidcProviderArn: eksCluster.oidcProviderArn,
  oidcProviderUrl: eksCluster.oidcProviderUrl,
  region: region,
  crossRegionDestination: isDRRegion ? "eu-south-1" : "eu-west-1",
  albControllerReady: eksCluster.albController,
  tags: getTags(),
});

// Create monitoring stack
// NOTE: Due to webhook timing issues, monitoring may fail on first deployment
// Run `pulumi up` twice to resolve CRD and webhook timing issues
const monitoring = new Monitoring("main", {
  k8sProvider: eksCluster.provider,
  clusterName: clusterName,
  tags: getTags(),
});

// Create Chaos Mesh for failure injection
const chaosMesh = new ChaosMesh("main", {
  k8sProvider: eksCluster.provider,
  tags: getTags(),
});

// Create ingress for monitoring and chaos dashboards
// NOTE: This may fail if ALB controller webhook isn't ready
// Run `pulumi up` twice if ingress creation fails
const ingressSystem = new IngressSystem("main", {
  k8sProvider: eksCluster.provider,
  clusterName: clusterName,
  // certificateArn: "arn:aws:acm:...", // Add your certificate ARN for HTTPS
  monitoringChart: monitoring.prometheusChart,
  chaosMeshChart: chaosMesh.chart,
  tags: getTags(),
});

// Cross-region setup (only if both regions should be connected)
let crossRegion: CrossRegion | undefined;

// Only deploy cross-region infrastructure if we have configuration for it
const enableCrossRegion = config.getBoolean("enableCrossRegion") || false;

if (enableCrossRegion) {
  try {
    // Determine peer region and stack name
    const peerRegion = isMainRegion ? "eu-west-1" : "eu-south-1";
    const peerStackName = isMainRegion ? "dublin" : "milan";
    const peerEnvironment = isMainRegion ? "dublin" : "milan";
    
    // Get stack reference to peer region
    const peerStackRef = new pulumi.StackReference(`peer-stack`, {
      name: `k8s-multi-region-dr/${peerStackName}`,
    });
    
    // Get peer VPC information
    const peerVpcId = peerStackRef.getOutput("vpcId");
    const peerVpcCidr = peerStackRef.getOutput("vpcCidr_");
    
    // Only create cross-region resources from the main region to avoid duplicates
    if (isMainRegion) {
      crossRegion = new CrossRegion("cross-region", {
        primaryVpcId: networking.vpcId,
        primaryVpcCidr: pulumi.output(vpcCidr),
        primaryRegion: region,
        secondaryVpcId: peerVpcId,
        secondaryVpcCidr: peerVpcCidr,
        secondaryRegion: peerRegion,
        projectName: projectName,
        environment: environment,
        tags: getTags(),
      });
    }
    
    pulumi.log.info(`Cross-region connectivity enabled between ${region} and ${peerRegion}`);
  } catch (error) {
    pulumi.log.warn(`Cross-region setup skipped: ${error}. Deploy peer region first.`);
  }
}

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

// Note: DNS component requires ALBs from both regions
// Should be deployed separately after both regions have ALBs
// Example usage:
// const dns = new Dns("main", {
//   domainName: "dadjokes.k8sdr.com",
//   primaryAlbArn: primaryAlbArn,
//   primaryAlbDnsName: primaryAlbDnsName,
//   primaryAlbZoneId: primaryAlbZoneId,
//   secondaryAlbArn: secondaryAlbArn,
//   secondaryAlbDnsName: secondaryAlbDnsName,
//   secondaryAlbZoneId: secondaryAlbZoneId,
//   primaryRegion: "eu-south-1",
//   secondaryRegion: "eu-west-1",
//   tags: getTags(),
// });

// Export cross-region outputs (if enabled)
export const crossRegionEnabled = enableCrossRegion;
export const vpcPeeringConnectionId = crossRegion?.vpcPeeringConnection?.id;
export const privateHostedZoneId = crossRegion?.privateHostedZone?.zoneId;

// Export monitoring outputs
export const monitoringNamespace = monitoring.namespace.metadata.name;
export const grafanaIngressName = ingressSystem.grafanaIngress.metadata.name;

// Export chaos engineering outputs
export const chaosMeshNamespace = chaosMesh.namespace.metadata.name;
export const chaosDashboardIngressName = ingressSystem.chaosDashboardIngress.metadata.name;

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
  eksVersion: "1.33",
  nodeInstanceType: nodeInstanceType,
  nodeCount: desiredCapacity,
})); 
