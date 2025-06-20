import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";

export interface EksClusterArgs {
    clusterName: string;
    vpcId: pulumi.Input<string>;
    privateSubnetIds: pulumi.Input<pulumi.Input<string>[]>;
    publicSubnetIds: pulumi.Input<pulumi.Input<string>[]>;
    nodeInstanceType: string;
    desiredCapacity: number;
    minSize: number;
    maxSize: number;
    eksVersion?: string;
    tags?: Record<string, string>;
}

export class EksCluster extends pulumi.ComponentResource {
    public readonly cluster: eks.Cluster;
    public readonly nodeGroup: eks.ManagedNodeGroup;
    public readonly kubeconfig: pulumi.Output<any>;
    public readonly clusterName: pulumi.Output<string>;
    public readonly clusterEndpoint: pulumi.Output<string>;
    public readonly provider: k8s.Provider;
    public readonly oidcProvider: aws.iam.OpenIdConnectProvider;
    public readonly oidcProviderArn: pulumi.Output<string>;
    public readonly oidcProviderUrl: pulumi.Output<string>;

    constructor(name: string, args: EksClusterArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:eks:EksCluster", name, {}, opts);

        const eksVersion = args.eksVersion || "1.30";

        // Create IAM role for EKS cluster
        const clusterRole = new aws.iam.Role(`${name}-cluster-role`, {
            assumeRolePolicy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [{
                    Action: "sts:AssumeRole",
                    Effect: "Allow",
                    Principal: {
                        Service: "eks.amazonaws.com",
                    },
                }],
            }),
            tags: args.tags,
        }, { parent: this });

        // Attach required policies to cluster role
        const clusterPolicies = [
            "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
            "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
        ];

        clusterPolicies.forEach((policyArn, index) => {
            new aws.iam.RolePolicyAttachment(`${name}-cluster-policy-${index}`, {
                policyArn: policyArn,
                role: clusterRole.name,
            }, { parent: this });
        });

        // Create IAM role for node group (before cluster creation)
        const nodeRole = new aws.iam.Role(`${name}-node-role`, {
            assumeRolePolicy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [{
                    Action: "sts:AssumeRole",
                    Effect: "Allow",
                    Principal: {
                        Service: "ec2.amazonaws.com",
                    },
                }],
            }),
            tags: args.tags,
        }, { parent: this });

        // Attach required policies to node role
        const nodePolicies = [
            "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
            "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
            "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
            "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", // For Systems Manager access
        ];

        nodePolicies.forEach((policyArn, index) => {
            new aws.iam.RolePolicyAttachment(`${name}-node-policy-${index}`, {
                policyArn: policyArn,
                role: nodeRole.name,
            }, { parent: this });
        });

        // Create the EKS cluster with instance roles
        this.cluster = new eks.Cluster(`${name}-cluster`, {
            name: args.clusterName,
            version: eksVersion,
            vpcId: args.vpcId,
            subnetIds: pulumi.all([args.privateSubnetIds, args.publicSubnetIds]).apply(
                ([privateIds, publicIds]) => [...privateIds, ...publicIds]
            ),
            endpointPrivateAccess: true,
            endpointPublicAccess: true,
            serviceRole: clusterRole,
            instanceRoles: [nodeRole], // Add node role to instance roles for managed node groups
            providerCredentialOpts: {
                profileName: aws.config.profile,
            },
            skipDefaultNodeGroup: true, // We'll create our own managed node group
            enabledClusterLogTypes: [
                "api",
                "audit",
                "authenticator",
                "controllerManager",
                "scheduler",
            ],
            tags: {
                ...args.tags,
                Name: args.clusterName,
            },
        }, { parent: this });

        this.clusterName = this.cluster.eksCluster.name;
        this.clusterEndpoint = this.cluster.eksCluster.endpoint;
        this.kubeconfig = this.cluster.kubeconfig;

        // Get OIDC issuer URL from the cluster
        const oidcIssuer = this.cluster.eksCluster.identities.apply(identities => {
            if (identities && identities.length > 0 && identities[0].oidcs && identities[0].oidcs.length > 0) {
                return identities[0].oidcs[0].issuer;
            }
            throw new Error("OIDC issuer not found on EKS cluster");
        });

        // Create OIDC provider for IRSA (IAM Roles for Service Accounts)
        this.oidcProvider = new aws.iam.OpenIdConnectProvider(`${name}-oidc-provider`, {
            clientIdLists: ["sts.amazonaws.com"],
            thumbprintLists: ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"],
            url: oidcIssuer,
            tags: args.tags,
        }, { parent: this, dependsOn: [this.cluster] });

        this.oidcProviderArn = this.oidcProvider.arn;
        this.oidcProviderUrl = oidcIssuer;

        // Create managed node group
        this.nodeGroup = new eks.ManagedNodeGroup(`${name}-node-group`, {
            cluster: this.cluster,
            nodeGroupName: `${args.clusterName}-nodes`,
            nodeRole: nodeRole,
            subnetIds: args.privateSubnetIds,
            instanceTypes: [args.nodeInstanceType],
            scalingConfig: {
                desiredSize: args.desiredCapacity,
                minSize: args.minSize,
                maxSize: args.maxSize,
            },
            diskSize: 100, // GB
            amiType: "AL2_x86_64", // Amazon Linux 2
            labels: {
                "node-role": "worker",
            },
            tags: {
                ...args.tags,
                Name: `${args.clusterName}-node`,
                "k8s.io/cluster-autoscaler/enabled": "true",
                [`k8s.io/cluster-autoscaler/${args.clusterName}`]: "owned",
            },
        }, { parent: this });

        // Create Kubernetes provider
        this.provider = new k8s.Provider(`${name}-k8s-provider`, {
            kubeconfig: this.kubeconfig.apply(JSON.stringify),
        }, { parent: this });

        // Install EKS Add-ons
        const ebsCsiDriverRole = this.createEbsCsiDriverRole(name, args.clusterName);
        const vpcCniRole = this.createVpcCniRole(name, args.clusterName);
        this.installEksAddons(name, ebsCsiDriverRole, vpcCniRole);

        // Install AWS Load Balancer Controller
        const albControllerRole = this.createAlbControllerRole(name, args.clusterName);
        this.installAlbController(name, albControllerRole);

        // Register outputs
        this.registerOutputs({
            clusterName: this.clusterName,
            clusterEndpoint: this.clusterEndpoint,
            nodeGroupId: this.nodeGroup.nodeGroup.id,
            oidcProviderArn: this.oidcProviderArn,
        });
    }

    private createEbsCsiDriverRole(name: string, clusterName: string): aws.iam.Role {
        const oidcProviderUrl = this.oidcProviderUrl.apply(url => 
            url.replace("https://", "")
        );

        const ebsCsiRole = new aws.iam.Role(`${name}-ebs-csi-driver-role`, {
            assumeRolePolicy: pulumi.all([this.oidcProviderArn, oidcProviderUrl]).apply(
                ([oidcArn, oidcUrl]) => JSON.stringify({
                    Version: "2012-10-17",
                    Statement: [{
                        Effect: "Allow",
                        Principal: {
                            Federated: oidcArn,
                        },
                        Action: "sts:AssumeRoleWithWebIdentity",
                        Condition: {
                            StringEquals: {
                                [`${oidcUrl}:sub`]: "system:serviceaccount:kube-system:ebs-csi-controller-sa",
                                [`${oidcUrl}:aud`]: "sts.amazonaws.com",
                            },
                        },
                    }],
                })
            ),
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-ebs-csi-driver-policy`, {
            policyArn: "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
            role: ebsCsiRole.name,
        }, { parent: this });

        return ebsCsiRole;
    }

    private installEbsCsiDriver(name: string, role: aws.iam.Role): void {
        // Create service account with IAM role annotation
        const ebsCsiServiceAccount = new k8s.core.v1.ServiceAccount(`${name}-ebs-csi-sa`, {
            metadata: {
                name: "ebs-csi-controller-sa",
                namespace: "kube-system",
                annotations: {
                    "eks.amazonaws.com/role-arn": role.arn,
                },
            },
        }, { provider: this.provider, parent: this });

        // This method is now replaced by installEksAddons
    }

    private createVpcCniRole(name: string, clusterName: string): aws.iam.Role {
        const oidcProviderUrl = this.oidcProviderUrl.apply(url => 
            url.replace("https://", "")
        );

        const vpcCniRole = new aws.iam.Role(`${name}-vpc-cni-role`, {
            assumeRolePolicy: pulumi.all([this.oidcProviderArn, oidcProviderUrl]).apply(
                ([oidcArn, oidcUrl]) => JSON.stringify({
                    Version: "2012-10-17",
                    Statement: [{
                        Effect: "Allow",
                        Principal: {
                            Federated: oidcArn,
                        },
                        Action: "sts:AssumeRoleWithWebIdentity",
                        Condition: {
                            StringEquals: {
                                [`${oidcUrl}:sub`]: "system:serviceaccount:kube-system:aws-node",
                                [`${oidcUrl}:aud`]: "sts.amazonaws.com",
                            },
                        },
                    }],
                })
            ),
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-vpc-cni-policy`, {
            policyArn: "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
            role: vpcCniRole.name,
        }, { parent: this });

        return vpcCniRole;
    }

    private installEksAddons(name: string, ebsCsiRole: aws.iam.Role, vpcCniRole: aws.iam.Role): void {
        // Install VPC CNI Add-on (use default version for K8s 1.30)
        new aws.eks.Addon(`${name}-vpc-cni`, {
            clusterName: this.clusterName,
            addonName: "vpc-cni",
            // No version specified - use default compatible version
            serviceAccountRoleArn: vpcCniRole.arn,
            resolveConflictsOnCreate: "OVERWRITE",
            resolveConflictsOnUpdate: "OVERWRITE",
        }, { parent: this, dependsOn: [this.cluster, vpcCniRole] });

        // Install CoreDNS Add-on (use default version for K8s 1.30)
        new aws.eks.Addon(`${name}-coredns`, {
            clusterName: this.clusterName,
            addonName: "coredns",
            // No version specified - use default compatible version
            resolveConflictsOnCreate: "OVERWRITE",
            resolveConflictsOnUpdate: "OVERWRITE",
        }, { parent: this, dependsOn: [this.cluster] });

        // Install kube-proxy Add-on (use default version for K8s 1.30)
        new aws.eks.Addon(`${name}-kube-proxy`, {
            clusterName: this.clusterName,
            addonName: "kube-proxy",
            // No version specified - use default compatible version
            resolveConflictsOnCreate: "OVERWRITE",
            resolveConflictsOnUpdate: "OVERWRITE",
        }, { parent: this, dependsOn: [this.cluster] });

        // Install EBS CSI Driver Add-on (use default version for K8s 1.30)
        new aws.eks.Addon(`${name}-ebs-csi-driver`, {
            clusterName: this.clusterName,
            addonName: "aws-ebs-csi-driver",
            // No version specified - use default compatible version
            serviceAccountRoleArn: ebsCsiRole.arn,
            resolveConflictsOnCreate: "OVERWRITE",
            resolveConflictsOnUpdate: "OVERWRITE",
        }, { parent: this, dependsOn: [this.cluster, ebsCsiRole] });
    }

    private createAlbControllerRole(name: string, clusterName: string): aws.iam.Role {
        const oidcProviderUrl = this.oidcProviderUrl.apply(url => 
            url.replace("https://", "")
        );

        const albControllerRole = new aws.iam.Role(`${name}-alb-controller-role`, {
            assumeRolePolicy: pulumi.all([this.oidcProviderArn, oidcProviderUrl]).apply(
                ([oidcArn, oidcUrl]) => JSON.stringify({
                    Version: "2012-10-17",
                    Statement: [{
                        Effect: "Allow",
                        Principal: {
                            Federated: oidcArn,
                        },
                        Action: "sts:AssumeRoleWithWebIdentity",
                        Condition: {
                            StringEquals: {
                                [`${oidcUrl}:sub`]: "system:serviceaccount:kube-system:aws-load-balancer-controller",
                                [`${oidcUrl}:aud`]: "sts.amazonaws.com",
                            },
                        },
                    }],
                })
            ),
        }, { parent: this });

        // Download and attach the ALB controller IAM policy
        const albControllerPolicyUrl = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.2/docs/install/iam_policy.json";
        
        const albControllerPolicy = new aws.iam.Policy(`${name}-alb-controller-policy`, {
            policy: pulumi.output(albControllerPolicyUrl).apply(async (url) => {
                const response = await fetch(url);
                return await response.text();
            }),
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-alb-controller-policy-attachment`, {
            policyArn: albControllerPolicy.arn,
            role: albControllerRole.name,
        }, { parent: this });

        return albControllerRole;
    }

    private installAlbController(name: string, role: aws.iam.Role): void {
        // Create service account for ALB controller
        const albServiceAccount = new k8s.core.v1.ServiceAccount(`${name}-alb-controller-sa`, {
            metadata: {
                name: "aws-load-balancer-controller",
                namespace: "kube-system",
                annotations: {
                    "eks.amazonaws.com/role-arn": role.arn,
                },
            },
        }, { provider: this.provider, parent: this });

        // Install AWS Load Balancer Controller using Helm
        new k8s.helm.v3.Chart(`${name}-alb-controller`, {
            chart: "aws-load-balancer-controller",
            version: "1.6.2",
            namespace: "kube-system",
            fetchOpts: {
                repo: "https://aws.github.io/eks-charts",
            },
            values: {
                clusterName: this.clusterName,
                serviceAccount: {
                    create: false,
                    name: "aws-load-balancer-controller",
                },
                region: aws.getRegion().then(r => r.name),
                vpcId: this.cluster.eksCluster.vpcConfig.apply(vpc => vpc.vpcId),
            },
        }, { provider: this.provider, parent: this, dependsOn: [albServiceAccount] });
    }
} 