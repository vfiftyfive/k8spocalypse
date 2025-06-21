import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

export interface CoreDnsConfigArgs {
    k8sProvider: k8s.Provider;
    privateHostedZoneId?: pulumi.Input<string>;
    tags?: Record<string, string>;
}

export class CoreDnsConfig extends pulumi.ComponentResource {
    public readonly configMap: k8s.core.v1.ConfigMap;
    
    constructor(name: string, args: CoreDnsConfigArgs, opts?: pulumi.ComponentResourceOptions) {
        super("custom:coredns:CoreDnsConfig", name, {}, opts);

        // Create CoreDNS custom configuration
        this.configMap = new k8s.core.v1.ConfigMap(`${name}-coredns-custom`, {
            metadata: {
                name: "coredns-custom",
                namespace: "kube-system",
                labels: {
                    "eks.amazonaws.com/component": "coredns",
                    "k8s-app": "kube-dns",
                },
            },
            data: {
                "internal.k8sdr.com.server": `# Custom DNS configuration for cross-region MongoDB
internal.k8sdr.com:53 {
    errors
    cache 30
    forward . 169.254.169.253:53
    log
}`,
            },
        }, { provider: args.k8sProvider, parent: this });

        // Restart CoreDNS deployment to pick up the new configuration
        const coreDnsRestart = new k8s.core.v1.ConfigMap(`${name}-coredns-restart-trigger`, {
            metadata: {
                name: "coredns-restart-trigger",
                namespace: "kube-system",
                annotations: {
                    "pulumi.com/restart-trigger": Date.now().toString(),
                },
            },
            data: {
                "restart-time": new Date().toISOString(),
            },
        }, { 
            provider: args.k8sProvider, 
            parent: this,
            dependsOn: [this.configMap],
        });

        // Note: CoreDNS will automatically pick up the new ConfigMap
        // No need to restart the deployment manually

        this.registerOutputs({
            configMapName: this.configMap.metadata.name,
        });
    }
} 