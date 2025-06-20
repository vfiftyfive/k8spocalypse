import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

export interface DnsArgs {
    domainName: string;
    primaryAlbArn: pulumi.Input<string>;
    primaryAlbDnsName: pulumi.Input<string>;
    primaryAlbZoneId: pulumi.Input<string>;
    secondaryAlbArn: pulumi.Input<string>;
    secondaryAlbDnsName: pulumi.Input<string>;
    secondaryAlbZoneId: pulumi.Input<string>;
    primaryRegion: string;
    secondaryRegion: string;
    tags?: Record<string, string>;
}

export class Dns extends pulumi.ComponentResource {
    public readonly hostedZone: aws.route53.Zone;
    public readonly globalAccelerator: aws.globalaccelerator.Accelerator;
    public readonly primaryHealthCheck: aws.route53.HealthCheck;
    public readonly secondaryHealthCheck: aws.route53.HealthCheck;
    public readonly globalAcceleratorDnsName: pulumi.Output<string>;
    public readonly globalAcceleratorIps: pulumi.Output<string[]>;

    constructor(name: string, args: DnsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:dns:Dns", name, {}, opts);

        // Create Route53 hosted zone
        this.hostedZone = new aws.route53.Zone(`${name}-hosted-zone`, {
            name: args.domainName,
            comment: "Hosted zone for multi-region DR demo",
            tags: {
                ...args.tags,
                Name: `${args.domainName}-hosted-zone`,
            },
        }, { parent: this });

        // Create health checks for each region
        this.primaryHealthCheck = new aws.route53.HealthCheck(`${name}-primary-health-check`, {
            fqdn: args.primaryAlbDnsName,
            port: 80,
            type: "HTTP",
            resourcePath: "/health",
            failureThreshold: 3,
            requestInterval: 30,
            measureLatency: true,
            tags: {
                ...args.tags,
                Name: `${args.domainName}-primary-health-check`,
                Region: args.primaryRegion,
            },
        }, { parent: this });

        this.secondaryHealthCheck = new aws.route53.HealthCheck(`${name}-secondary-health-check`, {
            fqdn: args.secondaryAlbDnsName,
            port: 80,
            type: "HTTP",
            resourcePath: "/health",
            failureThreshold: 3,
            requestInterval: 30,
            measureLatency: true,
            tags: {
                ...args.tags,
                Name: `${args.domainName}-secondary-health-check`,
                Region: args.secondaryRegion,
            },
        }, { parent: this });

        // Create failover records
        const primaryRecord = new aws.route53.Record(`${name}-primary-record`, {
            zoneId: this.hostedZone.zoneId,
            name: args.domainName,
            type: "A",
            ttl: 30,
            setIdentifier: "Primary",
            failoverRoutingPolicies: [{
                type: "PRIMARY",
            }],
            healthCheckId: this.primaryHealthCheck.id,
            aliases: [{
                name: args.primaryAlbDnsName,
                zoneId: args.primaryAlbZoneId,
                evaluateTargetHealth: true,
            }],
        }, { parent: this });

        const secondaryRecord = new aws.route53.Record(`${name}-secondary-record`, {
            zoneId: this.hostedZone.zoneId,
            name: args.domainName,
            type: "A",
            ttl: 30,
            setIdentifier: "Secondary",
            failoverRoutingPolicies: [{
                type: "SECONDARY",
            }],
            healthCheckId: this.secondaryHealthCheck.id,
            aliases: [{
                name: args.secondaryAlbDnsName,
                zoneId: args.secondaryAlbZoneId,
                evaluateTargetHealth: true,
            }],
        }, { parent: this });

        // Create Global Accelerator
        this.globalAccelerator = new aws.globalaccelerator.Accelerator(`${name}-global-accelerator`, {
            name: `${args.domainName}-accelerator`,
            ipAddressType: "IPV4",
            enabled: true,
            attributes: {
                flowLogsEnabled: false,
            },
            tags: {
                ...args.tags,
                Name: `${args.domainName}-global-accelerator`,
            },
        }, { parent: this });

        // Create listener for Global Accelerator
        const listener = new aws.globalaccelerator.Listener(`${name}-listener`, {
            acceleratorArn: this.globalAccelerator.id,
            clientAffinity: "SOURCE_IP",
            protocol: "TCP",
            portRanges: [{
                fromPort: 80,
                toPort: 80,
            }, {
                fromPort: 443,
                toPort: 443,
            }],
        }, { parent: this });

        // Create endpoint groups for each region
        const primaryEndpointGroup = new aws.globalaccelerator.EndpointGroup(`${name}-primary-endpoint-group`, {
            listenerArn: listener.id,
            endpointGroupRegion: args.primaryRegion,
            trafficDialPercentage: 100,
            healthCheckIntervalSeconds: 30,
            healthCheckPath: "/health",
            healthCheckPort: 80,
            healthCheckProtocol: "HTTP",
            thresholdCount: 3,
            endpointConfigurations: [{
                endpointId: args.primaryAlbArn,
                weight: 100,
            }],
        }, { parent: this });

        const secondaryEndpointGroup = new aws.globalaccelerator.EndpointGroup(`${name}-secondary-endpoint-group`, {
            listenerArn: listener.id,
            endpointGroupRegion: args.secondaryRegion,
            trafficDialPercentage: 0, // Secondary region starts with 0 traffic
            healthCheckIntervalSeconds: 30,
            healthCheckPath: "/health",
            healthCheckPort: 80,
            healthCheckProtocol: "HTTP",
            thresholdCount: 3,
            endpointConfigurations: [{
                endpointId: args.secondaryAlbArn,
                weight: 100,
            }],
        }, { parent: this });

        // Create Route53 record for Global Accelerator
        const globalAcceleratorRecord = new aws.route53.Record(`${name}-ga-record`, {
            zoneId: this.hostedZone.zoneId,
            name: `ga.${args.domainName}`,
            type: "A",
            ttl: 30,
            records: this.globalAccelerator.ipSets.apply(ipSets => 
                ipSets[0]?.ipAddresses || []
            ),
        }, { parent: this });

        this.globalAcceleratorDnsName = this.globalAccelerator.dnsName;
        this.globalAcceleratorIps = this.globalAccelerator.ipSets.apply(ipSets => 
            ipSets[0]?.ipAddresses || []
        );

        this.registerOutputs({
            hostedZoneId: this.hostedZone.zoneId,
            globalAcceleratorArn: this.globalAccelerator.id,
            globalAcceleratorDnsName: this.globalAcceleratorDnsName,
            globalAcceleratorIps: this.globalAcceleratorIps,
        });
    }
} 