import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as k8s from "@pulumi/kubernetes";

export interface StorageArgs {
    clusterName: string;
    k8sProvider: k8s.Provider;
    oidcProviderArn: pulumi.Input<string>;
    oidcProviderUrl: pulumi.Input<string>;
    region: string;
    tags?: Record<string, string>;
}

export class Storage extends pulumi.ComponentResource {
    public readonly gp3StorageClass: k8s.storage.v1.StorageClass;
    public readonly volumeSnapshotClass: k8s.apiextensions.CustomResource;
    public readonly snapshotControllerRole: aws.iam.Role;
    public readonly dlmLifecyclePolicy: aws.dlm.LifecyclePolicy;

    constructor(name: string, args: StorageArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:storage:Storage", name, {}, opts);

        // Create GP3 storage class (faster and more cost-effective than GP2)
        this.gp3StorageClass = new k8s.storage.v1.StorageClass(`${name}-gp3`, {
            metadata: {
                name: "gp3",
                annotations: {
                    "storageclass.kubernetes.io/is-default-class": "true",
                },
            },
            provisioner: "ebs.csi.aws.com",
            volumeBindingMode: "WaitForFirstConsumer",
            allowVolumeExpansion: true,
            parameters: {
                type: "gp3",
                // GP3 specific parameters for better performance
                iops: "3000",
                throughput: "125", // MB/s
                encrypted: "true",
                // Filesystem type
                "csi.storage.k8s.io/fstype": "ext4",
            },
        }, { provider: args.k8sProvider, parent: this });

        // Create VolumeSnapshotClass for EBS snapshots
        this.volumeSnapshotClass = new k8s.apiextensions.CustomResource(`${name}-ebs-snapshot-class`, {
            apiVersion: "snapshot.storage.k8s.io/v1",
            kind: "VolumeSnapshotClass",
            metadata: {
                name: "ebs-snapshot-class",
                annotations: {
                    "snapshot.storage.kubernetes.io/is-default-class": "true",
                },
            },
            driver: "ebs.csi.aws.com",
            deletionPolicy: "Retain", // Keep snapshots even if VolumeSnapshot is deleted
            parameters: {
                // Tags for snapshots
                tagSpecification_1: `ResourceType=snapshot,Tags=[{Key=Cluster,Value=${args.clusterName}},{Key=ManagedBy,Value=Pulumi}]`,
            },
        }, { provider: args.k8sProvider, parent: this });

        // Create IAM role for snapshot management
        const oidcProviderUrl = pulumi.output(args.oidcProviderUrl).apply(url => 
            url.replace("https://", "")
        );

        this.snapshotControllerRole = new aws.iam.Role(`${name}-snapshot-controller-role`, {
            assumeRolePolicy: pulumi.all([args.oidcProviderArn, oidcProviderUrl]).apply(
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
                                [`${oidcUrl}:sub`]: "system:serviceaccount:kube-system:ebs-snapshot-controller",
                                [`${oidcUrl}:aud`]: "sts.amazonaws.com",
                            },
                        },
                    }],
                })
            ),
            tags: args.tags,
        }, { parent: this });

        // Attach snapshot policy to the role
        const snapshotPolicy = new aws.iam.Policy(`${name}-snapshot-policy`, {
            policy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [
                    {
                        Effect: "Allow",
                        Action: [
                            "ec2:CreateSnapshot",
                            "ec2:CreateTags",
                            "ec2:DescribeSnapshots",
                            "ec2:DescribeVolumes",
                            "ec2:DescribeInstances",
                            "ec2:DeleteSnapshot",
                            "ec2:CopySnapshot",
                            "ec2:ModifySnapshotAttribute",
                        ],
                        Resource: "*",
                    },
                ],
            }),
            tags: args.tags,
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-snapshot-policy-attachment`, {
            role: this.snapshotControllerRole.name,
            policyArn: snapshotPolicy.arn,
        }, { parent: this });

        // Create DLM (Data Lifecycle Manager) policy for automated EBS snapshots
        const dlmRole = new aws.iam.Role(`${name}-dlm-role`, {
            assumeRolePolicy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [{
                    Action: "sts:AssumeRole",
                    Effect: "Allow",
                    Principal: {
                        Service: "dlm.amazonaws.com",
                    },
                }],
            }),
            tags: args.tags,
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-dlm-policy`, {
            role: dlmRole.name,
            policyArn: "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole",
        }, { parent: this });

        // Create DLM lifecycle policy for automated snapshots
        this.dlmLifecyclePolicy = new aws.dlm.LifecyclePolicy(`${name}-ebs-snapshot-policy`, {
            description: `Automated EBS snapshots for ${args.clusterName}`,
            executionRoleArn: dlmRole.arn,
            state: "ENABLED",
            policyDetails: {
                resourceTypes: ["VOLUME"],
                targetTags: {
                    [`kubernetes.io/cluster/${args.clusterName}`]: "owned",
                },
                schedules: [{
                    name: "Hourly Snapshots",
                    createRule: {
                        interval: 1,
                        intervalUnit: "HOURS",
                        times: "00:00", // Start at midnight
                    },
                    retainRule: {
                        count: 24, // Keep last 24 hourly snapshots
                    },
                    tagsToAdd: {
                        SnapshotType: "Automated",
                        Cluster: args.clusterName,
                        Frequency: "Hourly",
                    },
                    copyTags: true,
                    // Cross-region copy configuration will be added later for DR
                }],
            },
            tags: {
                ...args.tags,
                Name: `${args.clusterName}-hourly-snapshots`,
            },
        }, { parent: this });

        // Register outputs
        this.registerOutputs({
            gp3StorageClassName: this.gp3StorageClass.metadata.name,
            volumeSnapshotClassName: this.volumeSnapshotClass.metadata.name,
            dlmPolicyId: this.dlmLifecyclePolicy.id,
        });
    }
}

// Helper function to create a test PVC
export function createTestPVC(
    name: string, 
    storageClassName: string, 
    size: string, 
    provider: k8s.Provider
): k8s.core.v1.PersistentVolumeClaim {
    return new k8s.core.v1.PersistentVolumeClaim(name, {
        metadata: {
            name: name,
            labels: {
                app: "test",
                purpose: "storage-validation",
            },
        },
        spec: {
            accessModes: ["ReadWriteOnce"],
            storageClassName: storageClassName,
            resources: {
                requests: {
                    storage: size,
                },
            },
        },
    }, { provider: provider });
} 