#!/bin/bash

# Install Home Assistant on K3s
# This script deploys Home Assistant using Kustomize
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Home Assistant on K3s ==="
echo ""

# 1. Deploy using Kustomize
echo "Deploying Home Assistant with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# 2. Monitor startup
echo "Monitoring Home Assistant startup..."
echo "This will take 2-3 minutes for initial setup..."
echo ""

for i in {1..40}; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n homeassistant -l app=homeassistant -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n homeassistant -l app=homeassistant -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Get ready status
    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n homeassistant $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n homeassistant $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/40] Status: $POD_STATUS | Ready: $READY | $REASON"

    # Check for success
    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Home Assistant is ready!"
        break
    fi

    # Check for persistent failures
    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Home Assistant failed to start"
        echo ""
        echo "Pod events:"
        kubectl get events -n homeassistant --sort-by='.lastTimestamp' | tail -10
        echo ""
        echo "Pod logs:"
        kubectl logs -n homeassistant -l app=homeassistant --tail=50 2>/dev/null || echo "No logs available"
        exit 1
    fi

    # Check for OOMKilled
    if [ "$REASON" = "OOMKilled" ]; then
        echo ""
        echo "❌ Container was killed due to Out of Memory"
        echo ""
        echo "Your Pi doesn't have enough free memory. Try:"
        echo "  1. Reboot the Pi to free up memory"
        echo "  2. Reduce resource limits in deployment.yaml"
        echo "  3. Stop other applications temporarily"
        exit 1
    fi

    sleep 15
done

echo ""
echo "=== Home Assistant Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n homeassistant -o wide
echo ""

echo "💾 Storage:"
kubectl get pvc -n homeassistant
echo ""

echo "🌐 Access Home Assistant:"
echo ""
echo "  External (from anywhere):"
echo "    https://home.charn.io"
echo ""
echo "  Local (faster when at home):"
echo "    https://home.local.charn.io"
echo ""
echo "  Direct NodePort (for testing):"
echo "    http://${PI_IP}:30123"
echo ""

echo "📝 Useful Commands:"
echo "  • View logs:        kubectl logs -f -n homeassistant -l app=homeassistant"
echo "  • Check status:     kubectl get pods -n homeassistant"
echo "  • Check events:     kubectl get events -n homeassistant --sort-by='.lastTimestamp'"
echo "  • Restart:          kubectl rollout restart deployment/homeassistant -n homeassistant"
echo "  • Shell access:     kubectl exec -it -n homeassistant deployment/homeassistant -- bash"
echo "  • Delete:           kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "⚙️ Configuration:"
echo "  • Config location:  /config (inside container)"
echo "  • PVC mount:        /mnt/lvm-storage/homeassistant-config-pvc-*"
echo "  • Timezone:         America/New_York"
echo ""

echo "📱 Next Steps:"
echo "  1. Wait 1-2 minutes for full initialization"
echo "  2. Open https://home.charn.io (or local URL)"
echo "  3. Complete the Home Assistant setup wizard"
echo "  4. Add your smart home devices and integrations"
echo ""

echo "📖 Documentation:"
echo "  • Application docs: docs/applications/home-assistant.md"
echo "  • Manifests:        apps/homeassistant/base/"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n homeassistant -l app=homeassistant --tail=20 2>/dev/null || echo "Waiting for logs..."
