#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="prometheus"
NAMESPACE="monitoring"

echo "=================================================="
echo "Installing Prometheus"
echo "=================================================="
echo ""

# Check if monitoring namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist."
    echo "Please create the namespace first:"
    echo "  kubectl create namespace $NAMESPACE"
    exit 1
fi

# Apply the kustomization
echo "Applying Kustomize configuration..."
kubectl apply -k "$SCRIPT_DIR"
echo ""

# Wait for deployment to be available
echo "Waiting for Prometheus deployment to be ready..."
kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s
echo ""

# Get pod status
echo "Prometheus Pod Status:"
kubectl get pods -n $NAMESPACE -l app=$APP_NAME
echo ""

# Display access information
echo "=================================================="
echo "Prometheus Installation Complete!"
echo "=================================================="
echo ""
echo "Access URLs:"
echo "  External: https://p8s.charn.io"
echo "  Local:    https://prometheus.local.charn.io"
echo "  NodePort: http://192.168.0.23:30090"
echo ""
echo "Default Configuration:"
echo "  - No authentication (configure via ingress annotations)"
echo "  - 30-day metric retention"
echo "  - 20Gi storage for metrics"
echo "  - Kubernetes service discovery enabled"
echo ""
echo "Useful Commands:"
echo "  View logs:        kubectl logs -n $NAMESPACE -l app=$APP_NAME -f"
echo "  Restart:          kubectl rollout restart deployment/$APP_NAME -n $NAMESPACE"
echo "  Check status:     kubectl get all -n $NAMESPACE -l app=$APP_NAME"
echo "  Edit config:      kubectl edit configmap prometheus-config -n $NAMESPACE"
echo "  Port forward:     kubectl port-forward -n $NAMESPACE svc/$APP_NAME 9090:9090"
echo ""
echo "Configuration:"
echo "  - Edit prometheus.yml: kubectl edit configmap prometheus-config -n $NAMESPACE"
echo "  - After editing, restart: kubectl rollout restart deployment/$APP_NAME -n $NAMESPACE"
echo ""
echo "For detailed setup instructions, see SETUP.md"
echo "For quick reference, see README.md"
echo ""
