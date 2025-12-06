#!/bin/bash

# Install Homer Dashboard on K3s using Kustomize
# This script deploys Homer as a central dashboard for all homelab apps
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Homer Dashboard on K3s ==="
echo ""

# Deploy using Kustomize
echo "Deploying Homer with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# Monitor startup
echo "Monitoring Homer startup..."
echo "Homer is very lightweight and should start in ~10 seconds..."
echo ""

for i in {1..15}; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n homer -l app=homer -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n homer -l app=homer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Get ready status
    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n homer $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n homer $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/15] Status: $POD_STATUS | Ready: $READY | $REASON"

    # Check for success
    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Homer is ready!"
        break
    fi

    # Check for persistent failures
    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Homer failed to start"
        echo ""
        echo "Pod events:"
        kubectl get events -n homer --sort-by='.lastTimestamp' | tail -10
        echo ""
        echo "Pod logs:"
        kubectl logs -n homer -l app=homer --tail=50 2>/dev/null || echo "No logs available"
        exit 1
    fi

    sleep 2
done

echo ""
echo "=== Homer Dashboard Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n homer -o wide
echo ""

echo "🌐 Access Homer Dashboard:"
echo ""
echo "  External (from anywhere):"
echo "    https://homer.charn.io"
echo ""
echo "  Local (faster when at home):"
echo "    https://homer.local.charn.io"
echo ""
echo "  Direct NodePort (for testing):"
echo "    http://${PI_IP}:30800"
echo ""

echo "⚙️  Configuration:"
echo "  • Config stored in: ConfigMap (homer-config)"
echo "  • No persistent storage needed (static site)"
echo "  • Very lightweight: 10m CPU, 32Mi RAM"
echo ""

echo "📝 Customization:"
echo "  • Edit dashboard config:"
echo "    kubectl edit configmap homer-config -n homer"
echo "  • Apply changes:"
echo "    kubectl rollout restart deployment/homer -n homer"
echo "  • View current config:"
echo "    kubectl get configmap homer-config -n homer -o yaml"
echo ""

echo "💡 Useful Commands:"
echo "  • View logs:        kubectl logs -f -n homer -l app=homer"
echo "  • Check status:     kubectl get pods -n homer"
echo "  • Restart:          kubectl rollout restart deployment/homer -n homer"
echo "  • Delete:           kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "📖 Documentation:"
echo "  • Setup guide:      apps/homer/base/SETUP.md"
echo "  • Manifests:        apps/homer/base/"
echo "  • Official docs:    https://github.com/bastienwirtz/homer"
echo ""

echo "💡 Tip: Bookmark https://homer.charn.io as your home page!"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n homer -l app=homer --tail=10 2>/dev/null || echo "Waiting for logs..."
