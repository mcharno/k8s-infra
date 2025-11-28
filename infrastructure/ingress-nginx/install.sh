#!/bin/bash

# Install Nginx Ingress Controller for K3s
# This script installs the official Nginx Ingress with our custom configuration
# Run with: bash install.sh

set -e

echo "=== Installing Nginx Ingress Controller ==="
echo ""

INGRESS_VERSION="v1.9.5"

# 1. Install official Nginx Ingress
echo "Installing Nginx Ingress Controller ${INGRESS_VERSION}..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_VERSION}/deploy/static/provider/baremetal/deploy.yaml

# 2. Wait for deployment
echo "Waiting for Nginx Ingress to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo ""
echo "✓ Nginx Ingress Controller installed"
echo ""

# 3. Apply custom ConfigMap
echo "Applying custom configuration..."
kubectl apply -f configmap.yaml

echo ""
echo "✓ Custom ConfigMap applied"
echo ""

# 4. Patch service for fixed NodePorts
echo "Configuring NodePorts (30280 for HTTP, 30443 for HTTPS)..."

# Patch HTTP port
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30280}]'

# Patch HTTPS port
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/1/nodePort", "value":30443}]'

echo ""
echo "✓ NodePorts configured"
echo ""

# 5. Restart controller to apply ConfigMap
echo "Restarting controller to apply configuration..."
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo ""
echo "=== Nginx Ingress Installation Complete ==="
echo ""

echo "📊 Status:"
kubectl get pods -n ingress-nginx
echo ""

echo "🌐 Service:"
kubectl get svc -n ingress-nginx ingress-nginx-controller
echo ""

PI_IP=$(hostname -I | awk '{print $1}')
echo "🔗 Access:"
echo "  HTTP:  http://${PI_IP}:30280"
echo "  HTTPS: https://${PI_IP}:30443"
echo ""

echo "⚙️  Configuration Highlights:"
echo "  • ssl-redirect: false (prevents 308 loops with Cloudflare Tunnel)"
echo "  • use-forwarded-headers: true (trusts X-Forwarded-* headers)"
echo "  • Cloudflare IP ranges configured for real IP detection"
echo ""

echo "📝 Important:"
echo "  The ssl-redirect: false setting is CRITICAL for Cloudflare Tunnel"
echo "  Without it, external access will have infinite redirect loops"
echo ""

echo "✓ Ready for ingress resources"
