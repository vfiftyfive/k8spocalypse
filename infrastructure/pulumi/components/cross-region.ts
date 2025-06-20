import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

export interface CrossRegionArgs {
    primaryVpcId: pulumi.Input<string>;
    primaryVpcCidr: string;
    primaryRegion: string;
    secondaryVpcId: pulumi.Input<string>;
    secondaryVpcCidr: string;
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
        this.privateHostedZone = new aws.route53.Zone(`${name}-private-zone`, {
            name: `${args.environment}.internal`,
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
                Name: `${args.projectName}-${args.environment}-private-zone`,
            },
        }, { parent: this });

        // Create security group for cross-region communication
        this.crossRegionSecurityGroup = new aws.ec2.SecurityGroup(`${name}-cross-region-sg`, {
            vpcId: args.primaryVpcId,
            description: "Security group for cross-region communication",
            ingress: [
                // Allow MongoDB replication (27017)
                {
                    protocol: "tcp",
                    fromPort: 27017,
                    toPort: 27017,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "MongoDB replication from secondary region",
                },
                // Allow Redis communication (6379)
                {
                    protocol: "tcp",
                    fromPort: 6379,
                    toPort: 6379,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "Redis communication from secondary region",
                },
                // Allow application communication (8080)
                {
                    protocol: "tcp",
                    fromPort: 8080,
                    toPort: 8080,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "Application communication from secondary region",
                },
                // Allow health checks (80, 443)
                {
                    protocol: "tcp",
                    fromPort: 80,
                    toPort: 80,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "HTTP health checks from secondary region",
                },
                {
                    protocol: "tcp",
                    fromPort: 443,
                    toPort: 443,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "HTTPS health checks from secondary region",
                },
                // Allow DNS (53)
                {
                    protocol: "tcp",
                    fromPort: 53,
                    toPort: 53,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "DNS from secondary region",
                },
                {
                    protocol: "udp",
                    fromPort: 53,
                    toPort: 53,
                    cidrBlocks: [args.secondaryVpcCidr],
                    description: "DNS UDP from secondary region",
                },
            ],
            egress: [
                // Allow all outbound to secondary region
                {
                    protocol: "-1",
                    fromPort: 0,
                    toPort: 0,
                    cidrBlocks: [args.secondaryVpcCidr],
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
            ],
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-cross-region-sg`,
            },
        }, { parent: this });

        // Create DNS records for key services
        const mongoRecord = new aws.route53.Record(`${name}-mongo-record`, {
            zoneId: this.privateHostedZone.zoneId,
            name: `mongodb.${args.environment}.internal`,
            type: "A",
            ttl: 300,
            records: ["10.0.100.10"], // Placeholder - will be updated with actual MongoDB service IP
        }, { parent: this });

        const redisRecord = new aws.route53.Record(`${name}-redis-record`, {
            zoneId: this.privateHostedZone.zoneId,
            name: `redis.${args.environment}.internal`,
            type: "A",
            ttl: 300,
            records: ["10.0.100.20"], // Placeholder - will be updated with actual Redis service IP
        }, { parent: this });

        this.registerOutputs({
            vpcPeeringConnectionId: this.vpcPeeringConnection.id,
            privateHostedZoneId: this.privateHostedZone.zoneId,
            crossRegionSecurityGroupId: this.crossRegionSecurityGroup.id,
        });
    }
} 