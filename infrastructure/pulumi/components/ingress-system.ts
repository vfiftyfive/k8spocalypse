import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

export interface IngressSystemArgs {
    k8sProvider: k8s.Provider;
    clusterName: string;
    certificateArn?: string; // Optional SSL certificate for HTTPS
    tags?: Record<string, string>;
    // Add dependencies for services
    monitoringChart?: pulumi.Resource;
    chaosMeshChart?: pulumi.Resource;
}

export class IngressSystem extends pulumi.ComponentResource {
    public readonly grafanaIngress: k8s.networking.v1.Ingress;
    public readonly chaosDashboardIngress: k8s.networking.v1.Ingress;

    constructor(name: string, args: IngressSystemArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:ingress:IngressSystem", name, {}, opts);

        // Grafana Ingress - only create if monitoring chart is provided
        this.grafanaIngress = new k8s.networking.v1.Ingress(`${name}-grafana`, {
            metadata: {
                name: "grafana-ingress",
                namespace: "monitoring",
                annotations: {
                    "kubernetes.io/ingress.class": "alb",
                    "alb.ingress.kubernetes.io/scheme": "internet-facing",
                    "alb.ingress.kubernetes.io/target-type": "ip",
                    "alb.ingress.kubernetes.io/listen-ports": args.certificateArn 
                        ? '[{"HTTP": 80}, {"HTTPS": 443}]'
                        : '[{"HTTP": 80}]',
                    ...(args.certificateArn && {
                        "alb.ingress.kubernetes.io/certificate-arn": args.certificateArn,
                        "alb.ingress.kubernetes.io/ssl-redirect": "443",
                    }),
                    "alb.ingress.kubernetes.io/healthcheck-path": "/api/health",
                    "alb.ingress.kubernetes.io/healthcheck-interval-seconds": "30",
                    "alb.ingress.kubernetes.io/healthy-threshold-count": "2",
                    "alb.ingress.kubernetes.io/unhealthy-threshold-count": "3",
                    "alb.ingress.kubernetes.io/tags": `Environment=${args.clusterName},Component=monitoring`,
                },
            },
            spec: {
                rules: [{
                    host: `grafana-${args.clusterName}.local`, // Update with your domain
                    http: {
                        paths: [{
                            path: "/",
                            pathType: "Prefix",
                            backend: {
                                service: {
                                    name: "prometheus-grafana", // kube-prometheus-stack service name
                                    port: {
                                        number: 80,
                                    },
                                },
                            },
                        }],
                    },
                }],
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: args.monitoringChart ? [args.monitoringChart] : [],
            customTimeouts: {
                create: "15m", // ALB provisioning can take time
                update: "10m",
                delete: "10m",
            },
        });

        // Chaos Mesh Dashboard Ingress - only create if chaos mesh chart is provided
        this.chaosDashboardIngress = new k8s.networking.v1.Ingress(`${name}-chaos-dashboard`, {
            metadata: {
                name: "chaos-dashboard-ingress",
                namespace: "chaos-mesh",
                annotations: {
                    "kubernetes.io/ingress.class": "alb",
                    "alb.ingress.kubernetes.io/scheme": "internet-facing",
                    "alb.ingress.kubernetes.io/target-type": "ip",
                    "alb.ingress.kubernetes.io/listen-ports": args.certificateArn 
                        ? '[{"HTTP": 80}, {"HTTPS": 443}]'
                        : '[{"HTTP": 80}]',
                    ...(args.certificateArn && {
                        "alb.ingress.kubernetes.io/certificate-arn": args.certificateArn,
                        "alb.ingress.kubernetes.io/ssl-redirect": "443",
                    }),
                    "alb.ingress.kubernetes.io/healthcheck-path": "/api/common/version",
                    "alb.ingress.kubernetes.io/healthcheck-interval-seconds": "30",
                    "alb.ingress.kubernetes.io/healthy-threshold-count": "2",
                    "alb.ingress.kubernetes.io/unhealthy-threshold-count": "3",
                    "alb.ingress.kubernetes.io/tags": `Environment=${args.clusterName},Component=chaos-engineering`,
                },
            },
            spec: {
                rules: [{
                    host: `chaos-${args.clusterName}.local`, // Update with your domain
                    http: {
                        paths: [{
                            path: "/",
                            pathType: "Prefix",
                            backend: {
                                service: {
                                    name: "chaos-dashboard", // Chaos Mesh dashboard service name
                                    port: {
                                        number: 2333,
                                    },
                                },
                            },
                        }],
                    },
                }],
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: args.chaosMeshChart ? [args.chaosMeshChart] : [],
            customTimeouts: {
                create: "15m", // ALB provisioning can take time
                update: "10m", 
                delete: "10m",
            },
        });

        // Register outputs
        this.registerOutputs({
            grafanaIngressName: this.grafanaIngress.metadata.name,
            chaosDashboardIngressName: this.chaosDashboardIngress.metadata.name,
        });
    }
} 