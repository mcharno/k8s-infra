#!/bin/bash

# Create Cloudflare API token secret for cert-manager
# Run with: bash create-cloudflare-secret.sh

set -e

echo "=== Creating Cloudflare API Token Secret ==="
echo ""

echo "You need a Cloudflare API token with DNS:Edit permissions."
echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
echo ""
echo "Token permissions required:"
echo "  • Zone - DNS - Edit (for both charn.io and charno.net zones)"
echo ""

read -p "Enter your Cloudflare API token: " -s CLOUDFLARE_TOKEN
echo ""

if [ -z "$CLOUDFLARE_TOKEN" ]; then
    echo "❌ Error: Token cannot be empty"
    exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

# Create secret
echo "Creating secret..."
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="${CLOUDFLARE_TOKEN}" \
  -n cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret created: cloudflare-api-token in namespace cert-manager"
echo ""

# Verify
echo "Verifying secret..."
kubectl get secret cloudflare-api-token -n cert-manager > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Secret verified"
else
    echo "❌ Error: Secret not found"
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Apply ClusterIssuers:"
echo "   kubectl apply -f infrastructure/cert-manager/clusterissuers.yaml"
echo ""
echo "2. Apply wildcard certificates:"
echo "   kubectl apply -f infrastructure/cert-manager/certificates.yaml"
echo ""
echo "3. Monitor certificate issuance:"
echo "   kubectl get certificate -n cert-manager -w"
echo ""
