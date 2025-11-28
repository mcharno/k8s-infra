#!/bin/bash

# Install cert-manager for automatic SSL certificate management
# Run with: bash install.sh

set -e

echo "=== Installing cert-manager ==="
echo ""

CERT_MANAGER_VERSION="v1.13.3"

# 1. Install cert-manager
echo "Installing cert-manager ${CERT_MANAGER_VERSION}..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml

# 2. Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

echo ""
echo "✓ cert-manager installed"
echo ""

# 3. Verify installation
echo "📊 Status:"
kubectl get pods -n cert-manager
echo ""

echo "=== cert-manager Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Create Cloudflare API token secret:"
echo "   kubectl create secret generic cloudflare-api-token \\"
echo "     --from-literal=api-token=YOUR_TOKEN \\"
echo "     -n cert-manager"
echo ""
echo "2. Apply ClusterIssuers:"
echo "   kubectl apply -f infrastructure/cert-manager/clusterissuers.yaml"
echo ""
echo "3. Apply wildcard certificates:"
echo "   kubectl apply -f infrastructure/cert-manager/certificates.yaml"
echo ""
