#!/bin/bash

# Copy wildcard certificates to application namespaces
# This allows applications to use the wildcard certs in their ingresses
# Run with: bash copy-certs-to-namespace.sh NAMESPACE

set -e

NAMESPACE=$1

if [ -z "$NAMESPACE" ]; then
    echo "Usage: bash copy-certs-to-namespace.sh NAMESPACE"
    exit 1
fi

echo "=== Copying Wildcard Certificates to ${NAMESPACE} ==="
echo ""

# Ensure namespace exists
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

# Copy charn.io wildcard cert
echo "Copying charn.io wildcard certificate..."
kubectl get secret charn-io-wildcard-tls -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Copy local.charn.io wildcard cert
echo "Copying local.charn.io wildcard certificate..."
kubectl get secret local-charn-io-wildcard-tls -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Copy charno.net wildcard cert (if needed)
echo "Copying charno.net wildcard certificate..."
kubectl get secret charno-net-wildcard-tls -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

echo ""
echo "✓ Certificates copied to namespace: $NAMESPACE"
echo ""

# Verify
echo "Verifying certificates in $NAMESPACE:"
kubectl get secret -n "$NAMESPACE" | grep wildcard-tls

echo ""
echo "Note: Certificates will need to be copied again after renewal."
echo "Consider using cert-manager's Certificate resource in each namespace instead."
echo ""
