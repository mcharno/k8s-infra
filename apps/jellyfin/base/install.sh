#!/bin/bash

# Install Jellyfin on K3s using Kustomize
# This script deploys Jellyfin media server
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Jellyfin on K3s ==="
echo ""

# Check available storage
echo "Checking available storage..."
AVAILABLE_STORAGE=$(df -h /var/lib/rancher/k3s/storage | awk 'NR==2 {print $4}')
echo "Available storage: $AVAILABLE_STORAGE"
echo ""
echo "⚠️  Jellyfin requires significant storage for media:"
echo "   - Config: 20Gi"
echo "   - Cache: 10Gi"
echo "   - Media: 500Gi"
echo "   Total: ~530Gi"
echo ""

# Deploy using Kustomize
echo "Deploying Jellyfin with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# Monitor startup
echo "Monitoring Jellyfin startup..."
echo "This will take 2-3 minutes for initial setup..."
echo ""

for i in {1..30}; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Get ready status
    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n jellyfin $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n jellyfin $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/30] Status: $POD_STATUS | Ready: $READY | $REASON"

    # Check for success
    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Jellyfin is ready!"
        break
    fi

    # Check for persistent failures
    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Jellyfin failed to start"
        echo ""
        echo "Pod events:"
        kubectl get events -n jellyfin --sort-by='.lastTimestamp' | tail -10
        echo ""
        echo "Pod logs:"
        kubectl logs -n jellyfin -l app=jellyfin --tail=50 2>/dev/null || echo "No logs available"
        exit 1
    fi

    sleep 10
done

echo ""
echo "=== Jellyfin Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n jellyfin -o wide
echo ""

echo "💾 Storage:"
kubectl get pvc -n jellyfin
echo ""

echo "🌐 Access Jellyfin:"
echo ""
echo "  External (from anywhere):"
echo "    https://jellyfin.charn.io"
echo ""
echo "  Local (faster when at home):"
echo "    https://jellyfin.local.charn.io"
echo ""
echo "  Direct NodePort (for testing):"
echo "    http://${PI_IP}:30096"
echo "    https://${PI_IP}:30920"
echo ""

echo "📺 First-Time Setup:"
echo "  1. Access Jellyfin via any URL above"
echo "  2. Create admin account on first visit"
echo "  3. Configure media libraries (see below)"
echo "  4. Install any desired plugins"
echo "  5. Configure remote access settings"
echo ""

echo "📁 Adding Media Files:"
echo "  Media is stored in PVC jellyfin-media (500Gi)"
echo ""
echo "  Option 1: Copy files directly to PVC (when pod is running):"
echo "    kubectl cp /path/to/media jellyfin/<pod-name>:/media/movies/"
echo ""
echo "  Option 2: Access PVC on the node:"
echo "    # Find the PVC path:"
echo "    kubectl get pv | grep jellyfin-media"
echo "    # Then on the node:"
echo "    sudo cp -r /path/to/media /var/lib/rancher/k3s/storage/pvc-*/movies/"
echo ""
echo "  Recommended directory structure:"
echo "    /media/movies/    - Movie files"
echo "    /media/tv/        - TV show files"
echo "    /media/music/     - Music files"
echo "    /media/photos/    - Photo files"
echo ""

echo "📝 Useful Commands:"
echo "  • View logs:        kubectl logs -f -n jellyfin -l app=jellyfin"
echo "  • Check status:     kubectl get pods -n jellyfin"
echo "  • Check events:     kubectl get events -n jellyfin --sort-by='.lastTimestamp'"
echo "  • Restart:          kubectl rollout restart deployment/jellyfin -n jellyfin"
echo "  • Shell access:     kubectl exec -it -n jellyfin deployment/jellyfin -- bash"
echo "  • Copy media:       kubectl cp /local/path jellyfin/<pod-name>:/media/folder/"
echo "  • Delete:           kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "⚙️  Configuration:"
echo "  • Config location:  /config (20Gi PVC)"
echo "  • Cache location:   /cache (10Gi PVC)"
echo "  • Media location:   /media (500Gi PVC)"
echo "  • Published URL:    https://jellyfin.charn.io"
echo "  • Timezone:         America/New_York"
echo ""

echo "🎬 Media Library Setup:"
echo "  1. In Jellyfin web UI, go to Dashboard → Libraries"
echo "  2. Click 'Add Media Library'"
echo "  3. Select content type (Movies, TV Shows, Music, etc.)"
echo "  4. Add folder: /media/movies (or appropriate subfolder)"
echo "  5. Configure metadata providers"
echo "  6. Jellyfin will scan and download metadata automatically"
echo ""

echo "⚠️  Performance Notes:"
echo "  • Running on Raspberry Pi 4 (limited CPU)"
echo "  • Hardware transcoding NOT available (requires GPU)"
echo "  • Recommend 'Direct Play' for best performance"
echo "  • Transcoding may cause buffering/slow performance"
echo "  • Use compatible media formats (H.264, AAC) to avoid transcoding"
echo ""

echo "📖 Documentation:"
echo "  • Application docs: docs/applications/jellyfin.md"
echo "  • Setup guide:      apps/jellyfin/base/SETUP.md"
echo "  • Manifests:        apps/jellyfin/base/"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n jellyfin -l app=jellyfin --tail=20 2>/dev/null || echo "Waiting for logs..."
