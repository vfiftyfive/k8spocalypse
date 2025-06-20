# Scenario 3: Health-Check Theatre

This scenario demonstrates the critical difference between naive health checks (port-only) and dependency-aware health checks. We use both our built-in fault injection and Chaos Mesh to simulate various dependency failures.

## Overview

We break different dependencies to show:
- Old `/healthz` (port-only) returns 200 even when dependencies are broken
- New `/readyz` (dependency-aware) correctly returns 503 when dependencies fail
- Pods with failing readiness checks are removed from service endpoints
- Global Accelerator detects unhealthy endpoints and fails over

## Chaos Mesh vs Built-in Fault Injection

### Built-in Fault Injection (`/inject/fault`)
**Advantages:**
- Simple HTTP endpoint, no additional tools needed
- Instant injection/restoration
- Application-aware failures (can simulate specific business logic failures)
- No cluster-wide permissions needed

**Use cases:**
- Application logic failures
- Dependency connection failures
- Custom error scenarios

### Chaos Mesh
**Advantages:**
- Infrastructure-level chaos (network, IO, stress)
- Kubernetes-native with CRDs
- Scheduled and repeatable experiments
- Fine-grained targeting with label selectors
- No application changes needed

**Use cases:**
- Network partitions
- Resource exhaustion (CPU, memory)
- IO delays and failures
- DNS failures

## Prerequisites

### Install Chaos Mesh
```bash
# Add Chaos Mesh Helm repository
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

# Install Chaos Mesh
kubectl create ns chaos-mesh
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock

# Verify installation
kubectl get pods -n chaos-mesh
```

### Verify Dependencies
- DadJokes application with `/readyz` endpoint
- Redis deployed
- MongoDB deployed
- OpenAI API key configured (optional)

## Execution Steps

### Method 1: Built-in Fault Injection

```bash
# Inject MongoDB failure
./inject-mongo-pool.sh

# Inject Redis failure  
./inject-redis-oom.sh

# Inject OpenAI API failure
./inject-openai-429.sh
```

### Method 2: Chaos Mesh Experiments

```bash
# Apply Redis memory stress
kubectl apply -f inject-redis-stress.yaml

# Apply MongoDB network partition
kubectl apply -f inject-mongo-network.yaml

# Apply OpenAI DNS chaos
kubectl apply -f inject-openai-dns.yaml
```

### Validate Health Check Behavior

```bash
./validate.sh
```

This script:
- Compares `/healthz` vs `/readyz` responses
- Checks pod endpoint membership
- Monitors Global Accelerator health
- Tracks 5xx error rates

## Chaos Mesh Manifests

### 1. Redis Memory Stress (`inject-redis-stress.yaml`)
Simulates Redis OOM by consuming available memory:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: redis-memory-stress
  namespace: dev
spec:
  mode: one
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: redis
  stressors:
    memory:
      workers: 1
      size: "256MB"
  duration: "5m"
```

### 2. MongoDB Network Partition (`inject-mongo-network.yaml`)
Blocks network traffic to MongoDB:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: mongodb-network-partition
  namespace: dev
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: mongodb
  direction: both
  duration: "5m"
  target:
    mode: all
    selector:
      namespaces:
        - dev
      labelSelectors:
        app: joke-server
```

### 3. OpenAI DNS Failure (`inject-openai-dns.yaml`)
Causes DNS resolution failures for OpenAI API:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: openai-dns-failure
  namespace: dev
spec:
  action: error
  mode: all
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: joke-worker
  patterns:
    - "api.openai.com"
  duration: "5m"
```

## Working Together: Fault Injection + Chaos Mesh

You can combine both approaches for comprehensive testing:

1. **Layer 1: Application Faults** (Built-in)
   - Business logic failures
   - API response manipulation
   - Connection pool exhaustion

2. **Layer 2: Infrastructure Chaos** (Chaos Mesh)
   - Network delays/partitions
   - Resource exhaustion
   - DNS failures

### Example Combined Test:
```bash
# 1. Inject application-level MongoDB pool exhaustion
kubectl exec -n dev deployment/joke-server -- \
  curl -X POST http://localhost:8080/inject/fault \
  -d '{"component": "mongodb", "failureMode": "pool-exhausted"}'

# 2. Add network latency with Chaos Mesh
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: mongodb-latency
  namespace: dev
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - dev
    labelSelectors:
      app: mongodb
  delay:
    latency: "500ms"
    jitter: "100ms"
  duration: "5m"
EOF

# 3. Validate combined effect
./validate.sh
```

## Key Observations

### With Naive Health Checks (`/healthz`)
- Returns 200 even when Redis/MongoDB/OpenAI are down
- Pods remain in service endpoints
- Traffic continues to route to broken pods
- Users experience 5xx errors

### With Dependency-Aware Health Checks (`/readyz`)
- Returns 503 when any dependency fails
- Kubernetes removes pod from endpoints
- Load balancer stops sending traffic
- Global Accelerator detects failure and reroutes

## Cleanup

### Remove Built-in Faults
```bash
kubectl exec -n dev deployment/joke-server -- \
  curl -X POST http://localhost:8080/inject/restore
```

### Remove Chaos Mesh Experiments
```bash
# List all chaos experiments
kubectl get chaos -A

# Delete specific experiment
kubectl delete stresschaos redis-memory-stress -n dev
kubectl delete networkchaos mongodb-network-partition -n dev
kubectl delete dnschaos openai-dns-failure -n dev

# Or delete all chaos in namespace
kubectl delete chaos --all -n dev
```

## Monitoring Chaos

### Chaos Mesh Dashboard
```bash
# Port-forward to access dashboard
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333

# Access at http://localhost:2333
```

### View Experiment Status
```bash
# Get experiment details
kubectl describe stresschaos redis-memory-stress -n dev

# View affected pods
kubectl get pods -n dev -l chaos-mesh.org/component=manager
```

## Best Practices

1. **Start Small**: Test in dev environment first
2. **Monitor Impact**: Watch metrics during chaos injection
3. **Set Duration**: Always set experiment duration to prevent runaway chaos
4. **Use Selectors**: Target specific pods with label selectors
5. **Document Results**: Record observed behavior and recovery times

## Acceptance Criteria

- ✅ Demonstrate `/healthz` returns 200 with broken dependencies
- ✅ Show `/readyz` returns 503 with broken dependencies
- ✅ Verify pods removed from endpoints when readiness fails
- ✅ Confirm Global Accelerator detects unhealthy endpoints
- ✅ Prove 5xx errors eliminated with proper health checks 