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

        // Install Prometheus stack (includes Prometheus, AlertManager, Grafana, Node Exporter)
        this.prometheusChart = new k8s.helm.v3.Chart(`${name}-prometheus`, {
            chart: "kube-prometheus-stack",
            version: "55.5.0",
            namespace: this.namespace.metadata.name,
            fetchOpts: {
                repo: "https://prometheus-community.github.io/helm-charts",
            },
            values: {
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
                // Disable components we don't need for demo
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
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: [this.namespace],
        });

        // Wait for CRDs to be installed before creating ServiceMonitor
        // Create ServiceMonitor for DadJokes application (only after Prometheus CRDs are available)
        const dadJokesServiceMonitor = new k8s.apiextensions.CustomResource(`${name}-dadjokes-monitor`, {
            apiVersion: "monitoring.coreos.com/v1",
            kind: "ServiceMonitor",
            metadata: {
                name: "dadjokes-metrics",
                namespace: this.namespace.metadata.name,
                labels: {
                    app: "dadjokes",
                    release: "prometheus", // Required for prometheus to pick it up
                },
            },
            spec: {
                selector: {
                    matchLabels: {
                        app: "joke-server",
                    },
                },
                namespaceSelector: {
                    matchNames: ["dev"],
                },
                endpoints: [{
                    port: "http",
                    path: "/metrics",
                    interval: "30s",
                }],
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            // Add explicit dependency on the Prometheus chart completion
            dependsOn: [this.prometheusChart],
            // Add custom timeout for CRD availability
            customTimeouts: {
                create: "10m",
                update: "5m",
                delete: "5m",
            },
        });

        // Register outputs
        this.registerOutputs({
            namespaceName: this.namespace.metadata.name,
        });
    }
} 