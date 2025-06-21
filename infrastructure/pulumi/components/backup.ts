import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as k8s from "@pulumi/kubernetes";

export interface BackupArgs {
    clusterName: string;
    k8sProvider: k8s.Provider;
    oidcProviderArn: pulumi.Input<string>;
    oidcProviderUrl: pulumi.Input<string>;
    region: string;
    crossRegionDestination?: string;
    tags?: Record<string, string>;
    albControllerReady?: pulumi.Resource;
}

export class Backup extends pulumi.ComponentResource {
    public readonly veleroBucket: aws.s3.Bucket;
    public readonly veleroRole: aws.iam.Role;
    public readonly snapshotLifecyclePolicy: aws.dlm.LifecyclePolicy;
    public readonly veleroNamespace: k8s.core.v1.Namespace;

    constructor(name: string, args: BackupArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:backup:Backup", name, {}, opts);

        // Create S3 bucket for Velero backups
        this.veleroBucket = new aws.s3.Bucket(`${name}-velero-backups`, {
            bucket: `velero-backups-${args.clusterName}-${args.region}`,
            versioning: {
                enabled: true,
            },
            lifecycleRules: [{
                id: "expire-old-backups",
                enabled: true,
                expiration: {
                    days: 30,
                },
                noncurrentVersionExpiration: {
                    days: 7,
                },
            }],
            serverSideEncryptionConfiguration: {
                rule: {
                    applyServerSideEncryptionByDefault: {
                        sseAlgorithm: "AES256",
                    },
                },
            },
            tags: {
                ...args.tags,
                Name: `velero-backups-${args.clusterName}`,
                Purpose: "Velero backups",
            },
        }, { parent: this });

        // Block public access
        new aws.s3.BucketPublicAccessBlock(`${name}-velero-bucket-pab`, {
            bucket: this.veleroBucket.id,
            blockPublicAcls: true,
            blockPublicPolicy: true,
            ignorePublicAcls: true,
            restrictPublicBuckets: true,
        }, { parent: this });

        // Create IAM role for Velero
        const oidcProviderUrl = pulumi.output(args.oidcProviderUrl).apply(url => 
            url.replace("https://", "")
        );

        this.veleroRole = new aws.iam.Role(`${name}-velero-role`, {
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
                                [`${oidcUrl}:sub`]: "system:serviceaccount:velero:velero",
                                [`${oidcUrl}:aud`]: "sts.amazonaws.com",
                            },
                        },
                    }],
                })
            ),
            tags: {
                ...args.tags,
                Name: `velero-role-${args.clusterName}`,
            },
        }, { parent: this });

        // Attach policies to Velero role
        const veleroS3Policy = new aws.iam.Policy(`${name}-velero-s3-policy`, {
            policy: pulumi.all([this.veleroBucket.arn]).apply(([bucketArn]) => JSON.stringify({
                Version: "2012-10-17",
                Statement: [
                    {
                        Effect: "Allow",
                        Action: [
                            "s3:GetObject",
                            "s3:DeleteObject",
                            "s3:PutObject",
                            "s3:AbortMultipartUpload",
                            "s3:ListMultipartUploadParts",
                        ],
                        Resource: [`${bucketArn}/*`],
                    },
                    {
                        Effect: "Allow",
                        Action: [
                            "s3:ListBucket",
                            "s3:GetBucketLocation",
                            "s3:ListBucketMultipartUploads",
                        ],
                        Resource: [bucketArn],
                    },
                ],
            })),
        }, { parent: this });

        const veleroEc2Policy = new aws.iam.Policy(`${name}-velero-ec2-policy`, {
            policy: JSON.stringify({
                Version: "2012-10-17",
                Statement: [
                    {
                        Effect: "Allow",
                        Action: [
                            "ec2:DescribeVolumes",
                            "ec2:DescribeSnapshots",
                            "ec2:CreateTags",
                            "ec2:CreateVolume",
                            "ec2:CreateSnapshot",
                            "ec2:DeleteSnapshot",
                        ],
                        Resource: "*",
                    },
                ],
            }),
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-velero-s3-attachment`, {
            policyArn: veleroS3Policy.arn,
            role: this.veleroRole.name,
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-velero-ec2-attachment`, {
            policyArn: veleroEc2Policy.arn,
            role: this.veleroRole.name,
        }, { parent: this });

        // Create Velero namespace
        this.veleroNamespace = new k8s.core.v1.Namespace(`${name}-velero-namespace`, {
            metadata: {
                name: "velero",
            },
        }, { provider: args.k8sProvider, parent: this });

        // Install Velero using Helm
        const veleroChart = new k8s.helm.v3.Chart(`${name}-velero`, {
            chart: "velero",
            version: "5.2.0",
            namespace: this.veleroNamespace.metadata.name,
            fetchOpts: {
                repo: "https://vmware-tanzu.github.io/helm-charts",
            },
            skipAwait: true,
            values: {
                configuration: {
                    backupStorageLocation: [{
                        name: "default",
                        provider: "aws",
                        bucket: this.veleroBucket.bucket,
                        config: {
                            region: args.region,
                        },
                    }],
                    volumeSnapshotLocation: [{
                        name: "default", 
                        provider: "aws",
                        config: {
                            region: args.region,
                        },
                    }],
                },
                credentials: {
                    useSecret: false,
                },
                serviceAccount: {
                    server: {
                        create: true,
                        name: "velero",
                        annotations: {
                            "eks.amazonaws.com/role-arn": this.veleroRole.arn,
                        },
                    },
                },
                // Force ClusterIP to avoid ALB webhook issues
                service: {
                    type: "ClusterIP",
                },
                initContainers: [{
                    name: "velero-plugin-for-aws",
                    image: "velero/velero-plugin-for-aws:v1.8.0",
                    volumeMounts: [{
                        mountPath: "/target",
                        name: "plugins",
                    }],
                }],
                schedules: {
                    "mongodb-backup": {
                        schedule: "0 */6 * * *", // Every 6 hours
                        template: {
                            includedNamespaces: ["dev"],
                            labelSelector: {
                                matchLabels: {
                                    app: "mongodb",
                                },
                            },
                            ttl: "168h0m0s", // 7 days
                            storageLocation: "default",
                            volumeSnapshotLocations: ["default"],
                        },
                    },
                    "dadjokes-backup": {
                        schedule: "0 */6 * * *", // Every 6 hours
                        template: {
                            includedNamespaces: ["dev"],
                            labelSelector: {
                                matchLabels: {
                                    app: "dadjokes",
                                },
                            },
                            ttl: "168h0m0s", // 7 days
                            storageLocation: "default",
                        },
                    },
                },
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: args.albControllerReady ? [args.albControllerReady] : [],
        });

        // Create DLM lifecycle policy for EBS snapshots
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
            tags: {
                ...args.tags,
                Name: `dlm-role-${args.clusterName}`,
            },
        }, { parent: this });

        new aws.iam.RolePolicyAttachment(`${name}-dlm-policy-attachment`, {
            policyArn: "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole",
            role: dlmRole.name,
        }, { parent: this });

        // Create lifecycle policy for EBS snapshots
        const lifecyclePolicyDocument = {
            PolicyDetails: {
                ResourceTypes: ["VOLUME"],
                TargetTags: [{
                    Key: "env",
                    Value: "prod",
                }, {
                    Key: "app",
                    Value: "dadjokes-db",
                }],
                Schedules: [{
                    Name: "6 hour snapshots",
                    CreateRule: {
                        Interval: 6,
                        IntervalUnit: "HOURS",
                        Times: ["00:00"],
                    },
                    RetainRule: {
                        Count: 28, // 7 days * 4 snapshots per day
                    },
                    CopyTags: true,
                    TagsToAdd: [{
                        Key: "Type",
                        Value: "DLM-Snapshot",
                    }],
                    ...(args.crossRegionDestination ? {
                        CrossRegionCopyRules: [{
                            TargetRegion: args.crossRegionDestination,
                            Encrypted: true,
                            RetainRule: {
                                Interval: 7,
                                IntervalUnit: "DAYS",
                            },
                            CopyTags: true,
                        }],
                    } : {}),
                }],
            },
            State: "ENABLED",
        };

        this.snapshotLifecyclePolicy = new aws.dlm.LifecyclePolicy(`${name}-snapshot-policy`, {
            description: `EBS snapshot policy for ${args.clusterName}`,
            executionRoleArn: dlmRole.arn,
            state: "ENABLED",
            policyDetails: {
                resourceTypes: ["VOLUME"],
                targetTags: {
                    env: "prod",
                    app: "dadjokes-db",
                },
                schedules: [{
                    name: "6 hour snapshots",
                    createRule: {
                        interval: 6,
                        intervalUnit: "HOURS",
                        times: "00:00",
                    },
                    retainRule: {
                        count: 28,
                    },
                    tagsToAdd: {
                        Type: "DLM-Snapshot",
                    },
                    copyTags: true,
                    ...(args.crossRegionDestination ? {
                        crossRegionCopyRules: [{
                            target: args.crossRegionDestination,
                            encrypted: true,
                            retainRule: {
                                interval: 7,
                                intervalUnit: "DAYS",
                            },
                            copyTags: true,
                        }],
                    } : {}),
                }],
            },
            tags: {
                ...args.tags,
                Name: `snapshot-policy-${args.clusterName}`,
            },
        }, { parent: this });

        this.registerOutputs({
            veleroBucketName: this.veleroBucket.bucket,
            veleroRoleArn: this.veleroRole.arn,
            snapshotPolicyId: this.snapshotLifecyclePolicy.id,
        });
    }
} 