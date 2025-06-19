import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";

export interface NetworkingArgs {
    vpcCidr: string;
    projectName: string;
    environment: string;
    region: string;
    tags?: Record<string, string>;
}

export class Networking extends pulumi.ComponentResource {
    public readonly vpc: awsx.ec2.Vpc;
    public readonly vpcId: pulumi.Output<string>;
    public readonly publicSubnetIds: pulumi.Output<string[]>;
    public readonly privateSubnetIds: pulumi.Output<string[]>;
    public readonly eksSecurityGroup: aws.ec2.SecurityGroup;

    constructor(name: string, args: NetworkingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:networking:Networking", name, {}, opts);

        const defaultTags = {
            Project: args.projectName,
            Environment: args.environment,
            Region: args.region,
            ManagedBy: "Pulumi",
            Component: "Networking",
            ...args.tags,
        };

        // Create VPC with 3 AZs
        this.vpc = new awsx.ec2.Vpc(`${name}-vpc`, {
            cidrBlock: args.vpcCidr,
            numberOfAvailabilityZones: 3,
            natGateways: {
                strategy: "OnePerAz", // NAT Gateway in each AZ for high availability
            },
            subnetSpecs: [
                {
                    type: awsx.ec2.SubnetType.Public,
                    name: "public",
                    cidrMask: 24, // /24 subnets
                    tags: {
                        ...defaultTags,
                        "kubernetes.io/role/elb": "1", // For AWS Load Balancer Controller
                        SubnetType: "Public",
                    },
                },
                {
                    type: awsx.ec2.SubnetType.Private,
                    name: "private",
                    cidrMask: 22, // /22 subnets (larger for EKS nodes)
                    tags: {
                        ...defaultTags,
                        "kubernetes.io/role/internal-elb": "1", // For internal load balancers
                        SubnetType: "Private",
                    },
                },
            ],
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-vpc`,
            },
        }, { parent: this });

        this.vpcId = this.vpc.vpcId;
        this.publicSubnetIds = this.vpc.publicSubnetIds;
        this.privateSubnetIds = this.vpc.privateSubnetIds;

        // Create security group for EKS cluster
        this.eksSecurityGroup = new aws.ec2.SecurityGroup(`${name}-eks-cluster-sg`, {
            vpcId: this.vpcId,
            description: "Security group for EKS cluster",
            ingress: [
                // Allow all traffic within the VPC
                {
                    protocol: "-1",
                    fromPort: 0,
                    toPort: 0,
                    cidrBlocks: [args.vpcCidr],
                    description: "Allow all traffic within VPC",
                },
                // Allow HTTPS from anywhere (for kubectl access)
                {
                    protocol: "tcp",
                    fromPort: 443,
                    toPort: 443,
                    cidrBlocks: ["0.0.0.0/0"],
                    description: "Allow HTTPS for kubectl",
                },
            ],
            egress: [
                // Allow all outbound traffic
                {
                    protocol: "-1",
                    fromPort: 0,
                    toPort: 0,
                    cidrBlocks: ["0.0.0.0/0"],
                    description: "Allow all outbound traffic",
                },
            ],
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-eks-cluster-sg`,
            },
        }, { parent: this });

        // Create VPC endpoints for better performance and security
        const s3Endpoint = new aws.ec2.VpcEndpoint(`${name}-s3-endpoint`, {
            vpcId: this.vpcId,
            serviceName: `com.amazonaws.${args.region}.s3`,
            routeTableIds: pulumi.all([
                this.vpc.publicSubnetIds,
                this.vpc.privateSubnetIds,
            ]).apply(([publicIds, privateIds]) => {
                // Get route tables for all subnets
                return [...publicIds, ...privateIds];
            }),
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-s3-endpoint`,
            },
        }, { parent: this });

        // Create ECR endpoints for pulling container images
        const ecrApiEndpoint = new aws.ec2.VpcEndpoint(`${name}-ecr-api-endpoint`, {
            vpcId: this.vpcId,
            serviceName: `com.amazonaws.${args.region}.ecr.api`,
            vpcEndpointType: "Interface",
            subnetIds: this.privateSubnetIds,
            securityGroupIds: [this.eksSecurityGroup.id],
            privateDnsEnabled: true,
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-ecr-api-endpoint`,
            },
        }, { parent: this });

        const ecrDkrEndpoint = new aws.ec2.VpcEndpoint(`${name}-ecr-dkr-endpoint`, {
            vpcId: this.vpcId,
            serviceName: `com.amazonaws.${args.region}.ecr.dkr`,
            vpcEndpointType: "Interface",
            subnetIds: this.privateSubnetIds,
            securityGroupIds: [this.eksSecurityGroup.id],
            privateDnsEnabled: true,
            tags: {
                ...defaultTags,
                Name: `${args.projectName}-${args.environment}-ecr-dkr-endpoint`,
            },
        }, { parent: this });

        // Register outputs
        this.registerOutputs({
            vpcId: this.vpcId,
            publicSubnetIds: this.publicSubnetIds,
            privateSubnetIds: this.privateSubnetIds,
            eksSecurityGroupId: this.eksSecurityGroup.id,
        });
    }
}

// Helper function to create standard tags
export function getNetworkTags(projectName: string, environment: string, region: string): Record<string, string> {
    return {
        Project: projectName,
        Environment: environment,
        Region: region,
        ManagedBy: "Pulumi",
    };
} 