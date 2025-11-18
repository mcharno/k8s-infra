#!/bin/bash
# Script to set up GitHub Actions deployment for k3s cluster

set -e

NAMESPACE="github-actions"
SERVICE_ACCOUNT="github-actions-deployer"
OUTPUT_FILE="/tmp/github-actions-kubeconfig"

echo "======================================================"
echo "GitHub Actions k3s Deployment Setup"
echo "======================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check cluster connection
echo "Step 1: Verifying cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster."
    echo "Please configure kubectl with your k3s cluster credentials."
    exit 1
fi
echo "✓ Connected to cluster"
echo ""

# Deploy RBAC
echo "Step 2: Deploying RBAC for GitHub Actions..."
if [ ! -d "infrastructure/rbac" ]; then
    echo "Error: infrastructure/rbac directory not found."
    echo "Please run this script from the repository root."
    exit 1
fi

kubectl apply -k infrastructure/rbac/
echo "✓ RBAC deployed"
echo ""

# Wait for service account to be created
echo "Step 3: Waiting for service account to be ready..."
kubectl wait --for=jsonpath='{.metadata.name}'=github-actions-deployer \
    serviceaccount/github-actions-deployer -n $NAMESPACE --timeout=60s
echo "✓ Service account ready"
echo ""

# Generate kubeconfig
echo "Step 4: Generating kubeconfig for service account..."

# Get cluster information
CONTEXT=$(kubectl config current-context)
CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER')].cluster.server}")

# For Kubernetes 1.24+, create a token
echo "Creating long-lived token (valid for 10 years)..."
TOKEN=$(kubectl create token $SERVICE_ACCOUNT -n $NAMESPACE --duration=87600h)

# Get the CA certificate
CA_DATA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$CLUSTER')].cluster.certificate-authority-data}")

# Create kubeconfig
cat > $OUTPUT_FILE << EOF
apiVersion: v1
kind: Config
clusters:
- name: k3s-cluster
  cluster:
    certificate-authority-data: $CA_DATA
    server: $SERVER
contexts:
- name: github-actions
  context:
    cluster: k3s-cluster
    user: github-actions-deployer
current-context: github-actions
users:
- name: github-actions-deployer
  user:
    token: $TOKEN
EOF

echo "✓ Kubeconfig generated"
echo ""

# Test the kubeconfig
echo "Step 5: Testing service account permissions..."
export KUBECONFIG=$OUTPUT_FILE

if kubectl auth can-i create deployments --all-namespaces &> /dev/null; then
    echo "✓ Service account can create deployments"
else
    echo "⚠ Warning: Service account may have limited permissions"
fi

if kubectl auth can-i create namespaces &> /dev/null; then
    echo "✓ Service account can create namespaces"
else
    echo "⚠ Warning: Service account cannot create namespaces"
fi

echo ""
echo "======================================================"
echo "Setup Complete!"
echo "======================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Add the following secret to your GitHub repository:"
echo "   Name: KUBECONFIG"
echo "   Value: (copy the base64 string below)"
echo ""
echo "2. Go to: Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "3. Copy this base64-encoded kubeconfig:"
echo ""
echo "---BEGIN KUBECONFIG---"
base64 -w 0 $OUTPUT_FILE
echo ""
echo "---END KUBECONFIG---"
echo ""
echo "4. (Optional) Set up environment protection:"
echo "   - Go to Settings → Environments"
echo "   - Create 'production' environment"
echo "   - Add required reviewers"
echo ""
echo "5. Test the deployment:"
echo "   - Go to Actions → Deploy Infrastructure"
echo "   - Run workflow with component: rbac"
echo ""
echo "The kubeconfig has been saved to: $OUTPUT_FILE"
echo "Keep this file secure and delete it after adding to GitHub Secrets!"
echo ""
echo "To test locally:"
echo "  export KUBECONFIG=$OUTPUT_FILE"
echo "  kubectl get nodes"
echo ""
