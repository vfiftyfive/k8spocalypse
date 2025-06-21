import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

export interface MonitoringArgs {
    k8sProvider: k8s.Provider;
    clusterName: string;
    tags?: Record<string, string>;
}

export class Monitoring extends pulumi.ComponentResource {
    public readonly namespace: k8s.core.v1.Namespace;
    public readonly prometheusChart: k8s.helm.v3.Chart;

    constructor(name: string, args: MonitoringArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:monitoring:Monitoring", name, {}, opts);

        // Create monitoring namespace
        this.namespace = new k8s.core.v1.Namespace(`${name}-namespace`, {
            metadata: {
                name: "monitoring",
                labels: {
                    "pod-security.kubernetes.io/enforce": "privileged",
                    "pod-security.kubernetes.io/audit": "privileged",
                    "pod-security.kubernetes.io/warn": "privileged",
                },
            },
        }, { provider: args.k8sProvider, parent: this });

        // Install Prometheus stack with proper CRD handling
        this.prometheusChart = new k8s.helm.v3.Chart(`${name}-prometheus`, {
            chart: "kube-prometheus-stack",
            version: "55.5.0",
            namespace: this.namespace.metadata.name,
            fetchOpts: {
                repo: "https://prometheus-community.github.io/helm-charts",
            },
            values: {
                // Install CRDs
                crds: {
                    enabled: true,
                },
                // Disable admission webhooks to avoid timing issues
                prometheusOperator: {
                    admissionWebhooks: {
                        enabled: false,
                    },
                    // Ensure CRDs are created
                    manageCrds: true,
                },
                // Prometheus configuration
                prometheus: {
                    prometheusSpec: {
                        retention: "7d",
                        storageSpec: {
                            volumeClaimTemplate: {
                                spec: {
                                    storageClassName: "gp3",
                                    accessModes: ["ReadWriteOnce"],
                                    resources: {
                                        requests: {
                                            storage: "20Gi",
                                        },
                                    },
                                },
                            },
                        },
                        // Monitor all namespaces
                        serviceMonitorSelectorNilUsesHelmValues: false,
                        podMonitorSelectorNilUsesHelmValues: false,
                        ruleSelectorNilUsesHelmValues: false,
                        // Add cluster name label
                        externalLabels: {
                            cluster: args.clusterName,
                        },
                    },
                },
                // Grafana configuration
                grafana: {
                    enabled: true,
                    adminPassword: "admin", // Change in production
                    persistence: {
                        enabled: true,
                        storageClassName: "gp3",
                        size: "10Gi",
                    },
                    service: {
                        type: "ClusterIP", // Use ALB for external access
                    },
                    // Pre-configure dashboards
                    dashboardProviders: {
                        "dashboardproviders.yaml": {
                            apiVersion: 1,
                            providers: [{
                                name: "default",
                                orgId: 1,
                                folder: "",
                                type: "file",
                                disableDeletion: false,
                                editable: true,
                                options: {
                                    path: "/var/lib/grafana/dashboards/default",
                                },
                            }],
                        },
                    },
                    dashboards: {
                        default: {
                            "kubernetes-cluster": {
                                gnetId: 7249,
                                revision: 1,
                                datasource: "Prometheus",
                            },
                            "kubernetes-pods": {
                                gnetId: 6417,
                                revision: 1,
                                datasource: "Prometheus",
                            },
                            "node-exporter": {
                                gnetId: 1860,
                                revision: 31,
                                datasource: "Prometheus",
                            },
                        },
                    },
                },
                // AlertManager configuration
                alertmanager: {
                    alertmanagerSpec: {
                        storage: {
                            volumeClaimTemplate: {
                                spec: {
                                    storageClassName: "gp3",
                                    accessModes: ["ReadWriteOnce"],
                                    resources: {
                                        requests: {
                                            storage: "5Gi",
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
                // Enable node exporter
                nodeExporter: {
                    enabled: true,
                },
                // Enable kube-state-metrics
                kubeStateMetrics: {
                    enabled: true,
                },
                // Enable default rules and ServiceMonitors
                defaultRules: {
                    create: true,
                },
                // Enable ServiceMonitors
                kubeApiServer: {
                    enabled: true,
                },
                kubelet: {
                    enabled: true,
                },
                kubeControllerManager: {
                    enabled: false, // EKS managed
                },
                coreDns: {
                    enabled: true,
                },
                kubeEtcd: {
                    enabled: false, // EKS managed
                },
                kubeScheduler: {
                    enabled: false, // EKS managed
                },
                kubeProxy: {
                    enabled: false, // EKS managed
                },
            },
            // Resource options for the chart
            transformations: [
                // Skip waiting for CRD-dependent resources on initial install
                (obj: any) => {
                    if (obj.apiVersion?.includes("monitoring.coreos.com")) {
                        obj.metadata = obj.metadata || {};
                        obj.metadata.annotations = obj.metadata.annotations || {};
                        obj.metadata.annotations["pulumi.com/skipAwait"] = "true";
                    }
                },
            ],
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: [this.namespace],
            customTimeouts: {
                create: "10m",
                update: "10m",
                delete: "5m",
            },
        });

        // Note: ServiceMonitor for DadJokes will be created after the app is deployed
        // This avoids timing issues with CRDs

        // Register outputs
        this.registerOutputs({
            namespace: this.namespace,
            prometheusChart: this.prometheusChart,
        });
    }
} 