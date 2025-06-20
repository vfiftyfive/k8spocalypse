import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

export interface ChaosMeshArgs {
    k8sProvider: k8s.Provider;
    tags?: Record<string, string>;
}

export class ChaosMesh extends pulumi.ComponentResource {
    public readonly namespace: k8s.core.v1.Namespace;
    public readonly chart: k8s.helm.v3.Chart;

    constructor(name: string, args: ChaosMeshArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:chaos:ChaosMesh", name, {}, opts);

        // Create chaos-mesh namespace
        this.namespace = new k8s.core.v1.Namespace(`${name}-namespace`, {
            metadata: {
                name: "chaos-mesh",
                labels: {
                    "chaos-mesh.org/inject": "enabled",
                },
            },
        }, { provider: args.k8sProvider, parent: this });

        // Install Chaos Mesh using Helm
        this.chart = new k8s.helm.v3.Chart(`${name}-chart`, {
            chart: "chaos-mesh",
            version: "2.6.2",
            namespace: this.namespace.metadata.name,
            fetchOpts: {
                repo: "https://charts.chaos-mesh.org",
            },
            values: {
                // Configure for EKS/containerd
                chaosDaemon: {
                    runtime: "containerd",
                    socketPath: "/run/containerd/containerd.sock",
                    // Enable privilege mode for network chaos
                    privileged: true,
                },
                // Dashboard configuration
                dashboard: {
                    create: true,
                    serviceType: "ClusterIP", // Use ALB for external access
                    securityMode: false, // Enable for production
                },
                // Controller manager configuration
                controllerManager: {
                    replicaCount: 1,
                    enableFilterNamespace: false, // Allow chaos in all namespaces
                },
                // Webhook configuration
                webhook: {
                    enableCertManager: false, // Use self-signed certs
                },
                // DNS server for DNS chaos
                dnsServer: {
                    create: true,
                },
                // Enable all chaos types
                enableProfiling: true,
                enableCtrlServer: true,
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: [this.namespace],
        });

        // Register outputs
        this.registerOutputs({
            namespaceName: this.namespace.metadata.name,
        });
    }
} 