#!/bin/bash

echo "🚀 Deploying Dad Jokes Application to Milan (Primary)..."
echo "================================================"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured. Please configure access to Milan cluster first."
    exit 1
fi

# Navigate to deployment directory
cd dadjokes/deploy/devspace

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ OPENAI_API_KEY environment variable is not set"
    echo "Please set it with: export OPENAI_API_KEY=your_api_key_here"
    exit 1
fi

# Check if namespace exists, create if not
if ! kubectl get namespace dev &> /dev/null; then
    echo "📦 Creating namespace 'dev'..."
    kubectl create namespace dev
fi

# Check if secret already exists
if kubectl get secret openai-api-key -n dev &> /dev/null; then
    echo "✅ OpenAI API key secret already exists"
else
    echo "🔐 Creating encrypted OpenAI API key secret..."
    # Check if GPG key exists
    if ! gpg --list-secret-keys | grep -q "sec"; then
        echo "⚠️  No GPG key found. Creating one..."
        gpg --batch --generate-key <<EOF
%echo Generating GPG key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: K8s DR Demo
Name-Email: demo@k8spocalypse.local
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
    fi

    # Create SOPS config if not exists
    if [ ! -f .sops.yaml ]; then
        first_pgp_key=$(gpg --list-secret-keys --keyid-format LONG | grep -m1 '^sec' | awk '{print $2}' | cut -d '/' -f2)
        cat <<EOF > .sops.yaml
creation_rules:
- encrypted_regex: "^(data|stringData)$"
  pgp: >-
    ${first_pgp_key}
EOF
    fi

    # Encrypt the secret
    devspace run encrypt-openai-secret
fi

# Deploy with Milan-specific configuration
echo "🚀 Deploying application with DevSpace..."
REGION=eu-south-1 devspace deploy -n dev

# Wait for deployments to be ready
echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment --all -n dev

# Get the joke-server service endpoint
echo ""
echo "✅ Dad Jokes application deployed to Milan!"
echo ""
echo "📊 Deployment status:"
kubectl get pods -n dev
echo ""
echo "💾 Ratings storage:"
kubectl get pvc -n dev
echo ""
echo "⚠️  Note: Ratings are stored locally on EBS volume and are NOT replicated to Dublin!"
echo "    This demonstrates data loss during DR failover scenarios."
echo ""
echo "🔗 To access the application:"
echo "   kubectl port-forward -n dev svc/joke-server 8080:8080"
echo ""
echo "📝 Available endpoints:"
echo "   GET  /joke              - Get a random joke"
echo "   GET  /joke/{id}         - Get a specific joke"
echo "   POST /rating            - Rate a joke {id, score}"
echo "   GET  /rating/{id}       - Get joke ratings"
echo "   GET  /ratings/top?n=10  - Get top rated jokes"
echo "   GET  /ratings/storage   - Get storage info"
echo "   GET  /readyz            - Health check"
echo "   POST /inject/fault      - Inject fault for testing" 