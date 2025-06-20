import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

export interface CrossRegionArgs {
    primaryVpcId: pulumi.Input<string>;
    primaryVpcCidr: pulumi.Input<string>;
    primaryRegion: string;
    secondaryVpcId: pulumi.Input<string>;
    secondaryVpcCidr: pulumi.Input<string>;
    secondaryRegion: string;
    projectName: string;
    environment: string;
    tags?: Record<string, string>;
}

export class CrossRegion extends pulumi.ComponentResource {
    public readonly vpcPeeringConnection: aws.ec2.VpcPeeringConnection;
    public readonly privateHostedZone: aws.route53.Zone;
    public readonly crossRegionSecurityGroup: aws.ec2.SecurityGroup;
    
    constructor(name: string, args: CrossRegionArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:crossregion:CrossRegion", name, {}, opts);

        const defaultTags = {
            Project: args.projectName,
            Environment: args.environment,
            ManagedBy: "Pulumi",
            Component: "CrossRegion",
            ...args.tags,
        };

        // Create VPC Peering Connection (from primary to secondary region)
        this.vpcPeeringConnection = new aws.ec2.VpcPeeringConnection(`${name}-peering`, {
            vpcId: args.primaryVpcId,
            peerVpcId: args.secondaryVpcId,
            peerRegion: args.secondaryRegion,
            autoAccept: false, // We'll accept it in the secondary region
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-vpc-peering`,
                Side: "Requester",
            },
        }, { parent: this });

        // Accept the peering connection in the secondary region
        const peeringAccepter = new aws.ec2.VpcPeeringConnectionAccepter(`${name}-peering-accepter`, {
            vpcPeeringConnectionId: this.vpcPeeringConnection.id,
            autoAccept: true,
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-vpc-peering-accepter`,
                Side: "Accepter",
            },
        }, { 
            parent: this,
            provider: new aws.Provider(`${name}-secondary-provider`, {
                region: args.secondaryRegion as aws.Region,
            }),
        });

        // Create private hosted zone for internal service discovery
        // Single zone shared between both regions for cross-cluster communication
        this.privateHostedZone = new aws.route53.Zone(`${name}-private-zone`, {
            name: `internal.k8sdr.com`, // Common domain for both regions
            comment: "Private hosted zone for cross-region service discovery",
            vpcs: [
                {
                    vpcId: args.primaryVpcId,
                    vpcRegion: args.primaryRegion,
                },
                {
                    vpcId: args.secondaryVpcId,
                    vpcRegion: args.secondaryRegion,
                },
            ],
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-internal-private-zone`,
            },
        }, { parent: this });

        // Create security group for cross-region communication
        this.crossRegionSecurityGroup = new aws.ec2.SecurityGroup(`${name}-cross-region-sg`, {
            vpcId: args.primaryVpcId,
            description: "Security group for cross-region communication",
            ingress: pulumi.output(args.secondaryVpcCidr).apply(cidr => [
                // Allow MongoDB replication (27017)
                {
                    protocol: "tcp",
                    fromPort: 27017,
                    toPort: 27017,
                    cidrBlocks: [cidr],
                    description: "MongoDB replication from secondary region",
                },
                // Allow Redis communication (6379)
                {
                    protocol: "tcp",
                    fromPort: 6379,
                    toPort: 6379,
                    cidrBlocks: [cidr],
                    description: "Redis communication from secondary region",
                },
                // Allow application communication (8080)
                {
                    protocol: "tcp",
                    fromPort: 8080,
                    toPort: 8080,
                    cidrBlocks: [cidr],
                    description: "Application communication from secondary region",
                },
                // Allow health checks (80, 443)
                {
                    protocol: "tcp",
                    fromPort: 80,
                    toPort: 80,
                    cidrBlocks: [cidr],
                    description: "HTTP health checks from secondary region",
                },
                {
                    protocol: "tcp",
                    fromPort: 443,
                    toPort: 443,
                    cidrBlocks: [cidr],
                    description: "HTTPS health checks from secondary region",
                },
                // Allow DNS (53)
                {
                    protocol: "tcp",
                    fromPort: 53,
                    toPort: 53,
                    cidrBlocks: [cidr],
                    description: "DNS from secondary region",
                },
                {
                    protocol: "udp",
                    fromPort: 53,
                    toPort: 53,
                    cidrBlocks: [cidr],
                    description: "DNS UDP from secondary region",
                },
            ]),
            egress: pulumi.output(args.secondaryVpcCidr).apply(cidr => [
                // Allow all outbound to secondary region
                {
                    protocol: "-1",
                    fromPort: 0,
                    toPort: 0,
                    cidrBlocks: [cidr],
                    description: "All traffic to secondary region",
                },
                // Keep existing internet access
                {
                    protocol: "-1",
                    fromPort: 0,
                    toPort: 0,
                    cidrBlocks: ["0.0.0.0/0"],
                    description: "Internet access",
                },
            ]),
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-cross-region-sg`,
            },
        }, { parent: this });

        // DNS records for services will be created by their respective components
        // MongoDB: mongo.db.internal.k8sdr.com (with failover)
        // Redis: redis.cache.internal.k8sdr.com (with failover)
        // This ensures proper NLB integration and health checks

        this.registerOutputs({
            vpcPeeringConnectionId: this.vpcPeeringConnection.id,
            privateHostedZoneId: this.privateHostedZone.zoneId,
            crossRegionSecurityGroupId: this.crossRegionSecurityGroup.id,
        });
    }
} 