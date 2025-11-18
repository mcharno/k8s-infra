#!/bin/bash
# Script to create GitHub Container Registry pull secret in k3s

set -e

echo "Setting up GHCR pull secret for k3s cluster..."
echo ""

# Prompt for GitHub credentials
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -sp "Enter your GitHub Personal Access Token (with read:packages scope): " GITHUB_TOKEN
echo ""

# Create namespace if it doesn't exist
kubectl create namespace charno-web --dry-run=client -o yaml | kubectl apply -f -

# Create Docker registry secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USERNAME" \
  --docker-password="$GITHUB_TOKEN" \
  --docker-email="$GITHUB_USERNAME@users.noreply.github.com" \
  --namespace=charno-web \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==================================================================="
echo "GHCR pull secret created successfully!"
echo "==================================================================="
echo ""
echo "The secret 'ghcr-secret' has been created in the 'charno-web' namespace."
echo ""
