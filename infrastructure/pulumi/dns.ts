import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import { Dns } from "./components/dns";

// Get configuration
const config = new pulumi.Config();
const projectName = config.require("projectName");
const environment = config.require("environment");
const domainName = config.require("domainName");
const primaryRegion = config.require("primaryRegion");
const secondaryRegion = config.require("secondaryRegion");

// Get ALB configuration
const primaryAlbArn = config.require("primaryAlbArn");
const primaryAlbDnsName = config.require("primaryAlbDnsName");
const primaryAlbZoneId = config.require("primaryAlbZoneId");
const secondaryAlbArn = config.require("secondaryAlbArn");
const secondaryAlbDnsName = config.require("secondaryAlbDnsName");
const secondaryAlbZoneId = config.require("secondaryAlbZoneId");

// Export helper function for tagging
export function getTags(additionalTags?: Record<string, string>) {
  return {
    Project: projectName,
    Environment: environment,
    ManagedBy: "Pulumi",
    Component: "DNS",
    ...additionalTags,
  };
}

// Deploy DNS and Global Accelerator
const dns = new Dns("main", {
  domainName: domainName,
  primaryAlbArn: primaryAlbArn,
  primaryAlbDnsName: primaryAlbDnsName,
  primaryAlbZoneId: primaryAlbZoneId,
  secondaryAlbArn: secondaryAlbArn,
  secondaryAlbDnsName: secondaryAlbDnsName,
  secondaryAlbZoneId: secondaryAlbZoneId,
  primaryRegion: primaryRegion,
  secondaryRegion: secondaryRegion,
  tags: getTags(),
});

// Export outputs
export const hostedZoneId = dns.hostedZone.zoneId;
export const hostedZoneName = dns.hostedZone.name;
export const globalAcceleratorArn = dns.globalAccelerator.id;
export const globalAcceleratorDnsName = dns.globalAcceleratorDnsName;
export const globalAcceleratorIps = dns.globalAcceleratorIps;
export const primaryHealthCheckId = dns.primaryHealthCheck.id;
export const secondaryHealthCheckId = dns.secondaryHealthCheck.id;

// Export summary
export const dnsSummary = pulumi.all([
  dns.hostedZone.zoneId,
  dns.globalAcceleratorDnsName,
  dns.globalAcceleratorIps,
]).apply(([zoneId, gaDns, gaIps]) => ({
  hostedZoneId: zoneId,
  globalAcceleratorDns: gaDns,
  globalAcceleratorIps: gaIps,
  domainName: domainName,
  primaryRegion: primaryRegion,
  secondaryRegion: secondaryRegion,
})); 