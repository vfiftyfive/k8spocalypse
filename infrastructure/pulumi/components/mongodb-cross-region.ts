import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as k8s from "@pulumi/kubernetes";

export interface MongoDBCrossRegionArgs {
    primaryProvider: k8s.Provider;
    secondaryProvider: k8s.Provider;
    primaryRegion: string;
    secondaryRegion: string;
    privateHostedZoneId: pulumi.Input<string>;
    primaryVpcId: pulumi.Input<string>;
    secondaryVpcId: pulumi.Input<string>;
    primarySubnetIds: pulumi.Input<pulumi.Input<string>[]>;
    secondarySubnetIds: pulumi.Input<pulumi.Input<string>[]>;
    crossRegionSecurityGroupId: pulumi.Input<string>;
    namespace?: string;
    tags?: Record<string, string>;
}

export class MongoDBCrossRegion extends pulumi.ComponentResource {
    public readonly primaryNlbDnsName: pulumi.Output<string>;
    public readonly secondaryNlbDnsName: pulumi.Output<string>;
    public readonly mongoEndpoint: pulumi.Output<string>;
    
    constructor(name: string, args: MongoDBCrossRegionArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:mongodb:MongoDBCrossRegion", name, {}, opts);

        const namespace = args.namespace || "mongodb";
        const defaultTags = args.tags || {};

        // Create namespace in both clusters
        const primaryNamespace = new k8s.core.v1.Namespace(`${name}-primary-ns`, {
            metadata: {
                name: namespace,
            },
        }, { provider: args.primaryProvider, parent: this });

        const secondaryNamespace = new k8s.core.v1.Namespace(`${name}-secondary-ns`, {
            metadata: {
                name: namespace,
            },
        }, { provider: args.secondaryProvider, parent: this });

        // Create internal NLB service in primary region (Milan)
        const primaryMongoService = new k8s.core.v1.Service(`${name}-primary-nlb`, {
            metadata: {
                name: "mongo-nlb",
                namespace: namespace,
                annotations: {
                    "service.beta.kubernetes.io/aws-load-balancer-internal": "true",
                    "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
                    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port": "27017",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol": "TCP",
                },
            },
            spec: {
                type: "LoadBalancer",
                selector: {
                    app: "mongodb",
                },
                ports: [{
                    name: "mongo",
                    port: 27017,
                    targetPort: 27017,
                    protocol: "TCP",
                }],
            },
        }, { provider: args.primaryProvider, parent: this, dependsOn: [primaryNamespace] });

        // Create internal NLB service in secondary region (Dublin)
        const secondaryMongoService = new k8s.core.v1.Service(`${name}-secondary-nlb`, {
            metadata: {
                name: "mongo-nlb",
                namespace: namespace,
                annotations: {
                    "service.beta.kubernetes.io/aws-load-balancer-internal": "true",
                    "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
                    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port": "27017",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol": "TCP",
                },
            },
            spec: {
                type: "LoadBalancer",
                selector: {
                    app: "mongodb",
                },
                ports: [{
                    name: "mongo",
                    port: 27017,
                    targetPort: 27017,
                    protocol: "TCP",
                }],
            },
        }, { provider: args.secondaryProvider, parent: this, dependsOn: [secondaryNamespace] });

        // Extract NLB DNS names
        this.primaryNlbDnsName = primaryMongoService.status.loadBalancer.ingress[0].hostname;
        this.secondaryNlbDnsName = secondaryMongoService.status.loadBalancer.ingress[0].hostname;

        // Create health checks for each NLB
        const primaryHealthCheck = new aws.route53.HealthCheck(`${name}-primary-health`, {
            fqdn: this.primaryNlbDnsName,
            port: 27017,
            type: "TCP",
            failureThreshold: 3,
            requestInterval: 10, // Fast health checks for quick failover
            measureLatency: true,
            tags: {
                ...defaultTags,
                Name: `mongodb-primary-health-check`,
                Region: args.primaryRegion,
            },
        }, { parent: this });

        const secondaryHealthCheck = new aws.route53.HealthCheck(`${name}-secondary-health`, {
            fqdn: this.secondaryNlbDnsName,
            port: 27017,
            type: "TCP",
            failureThreshold: 3,
            requestInterval: 10,
            measureLatency: true,
            tags: {
                ...defaultTags,
                Name: `mongodb-secondary-health-check`,
                Region: args.secondaryRegion,
            },
        }, { parent: this });

        // Create failover DNS records in the private hosted zone
        const primaryRecord = new aws.route53.Record(`${name}-primary-record`, {
            zoneId: args.privateHostedZoneId,
            name: "mongo.db.internal.k8sdr.com",
            type: "A",
            ttl: 10, // Low TTL for fast failover
            setIdentifier: "Primary-Milan",
            failoverRoutingPolicies: [{
                type: "PRIMARY",
            }],
            healthCheckId: primaryHealthCheck.id,
            records: [this.primaryNlbDnsName.apply(dns => {
                // This would normally resolve to IPs, but for NLB we need the actual IPs
                // In production, you'd query the NLB for its IPs
                return dns; // Placeholder - needs actual IP resolution
            })],
        }, { parent: this });

        const secondaryRecord = new aws.route53.Record(`${name}-secondary-record`, {
            zoneId: args.privateHostedZoneId,
            name: "mongo.db.internal.k8sdr.com",
            type: "A",
            ttl: 10,
            setIdentifier: "Secondary-Dublin",
            failoverRoutingPolicies: [{
                type: "SECONDARY",
            }],
            healthCheckId: secondaryHealthCheck.id,
            records: [this.secondaryNlbDnsName.apply(dns => {
                return dns; // Placeholder - needs actual IP resolution
            })],
        }, { parent: this });

        // Create CoreDNS ConfigMap update for both clusters
        const coreDnsConfig = `
internal.k8sdr.com:53 {
    errors
    cache 10
    forward . /etc/resolv.conf
}
`;

        // Update CoreDNS in primary cluster
        const primaryCoreDnsPatch = new k8s.core.v1.ConfigMapPatch(`${name}-primary-coredns`, {
            metadata: {
                name: "coredns",
                namespace: "kube-system",
            },
            data: {
                "Corefile": pulumi.interpolate`${coreDnsConfig}`,
            },
        }, { provider: args.primaryProvider, parent: this });

        // Update CoreDNS in secondary cluster
        const secondaryCoreDnsPatch = new k8s.core.v1.ConfigMapPatch(`${name}-secondary-coredns`, {
            metadata: {
                name: "coredns",
                namespace: "kube-system",
            },
            data: {
                "Corefile": pulumi.interpolate`${coreDnsConfig}`,
            },
        }, { provider: args.secondaryProvider, parent: this });

        this.mongoEndpoint = pulumi.output("mongo.db.internal.k8sdr.com");

        this.registerOutputs({
            primaryNlbDnsName: this.primaryNlbDnsName,
            secondaryNlbDnsName: this.secondaryNlbDnsName,
            mongoEndpoint: this.mongoEndpoint,
        });
    }
} 