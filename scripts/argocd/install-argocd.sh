#!/bin/bash
# Script to install ArgoCD on k3s cluster

set -e

echo "Installing ArgoCD on k3s cluster..."

# Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Applying ArgoCD manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get initial admin password
echo ""
echo "==================================================================="
echo "ArgoCD installed successfully!"
echo "==================================================================="
echo ""
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "To access ArgoCD UI, you have several options:"
echo ""
echo "1. Port forward (temporary access):"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then visit: https://localhost:8080"
echo ""
echo "2. Expose via Ingress (recommended for permanent access):"
echo "   kubectl apply -f infrastructure/argocd/argocd-ingress.yaml"
echo ""
echo "==================================================================="
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: (shown above)"
echo ""
echo "IMPORTANT: Change the admin password after first login!"
echo ""
