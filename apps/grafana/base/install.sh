#!/bin/bash

# Install Grafana on K3s using Kustomize
# Grafana requires Prometheus to be deployed first
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Grafana on K3s ==="
echo ""

# Check if Prometheus is running
echo "Checking Prometheus..."
if ! kubectl get deployment prometheus -n monitoring >/dev/null 2>&1; then
    echo "⚠️  Prometheus not found"
    echo ""
    echo "Grafana requires Prometheus as a data source."
    echo "You can deploy Prometheus first, or continue anyway."
    echo ""
    read -p "Continue without Prometheus? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Please deploy Prometheus first:"
        echo "  kubectl apply -k apps/prometheus/base/"
        exit 1
    fi
else
    PROM_STATUS=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
    if [ "$PROM_STATUS" = "Running" ]; then
        echo "✓ Prometheus is running"
    else
        echo "⚠️  Prometheus status: $PROM_STATUS"
    fi
fi
echo ""

# Deploy using Kustomize
echo "Deploying Grafana with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# Monitor startup
echo "Monitoring Grafana startup..."
echo "This will take 30-60 seconds..."
echo ""

for i in {1..30}; do
    POD_STATUS=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n monitoring $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n monitoring $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/30] Status: $POD_STATUS | Ready: $READY | $REASON"

    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Grafana is ready!"
        break
    fi

    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Grafana failed to start"
        echo ""
        kubectl logs -n monitoring -l app=grafana --tail=50
        exit 1
    fi

    sleep 3
done

echo ""
echo "=== Grafana Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n monitoring -l app=grafana -o wide
echo ""

echo "💾 Storage:"
kubectl get pvc -n monitoring | grep grafana
echo ""

echo "🌐 Access Grafana:"
echo ""
echo "  External: https://grafana.charn.io"
echo "  Local:    https://grafana.local.charn.io"
echo "  NodePort: http://${PI_IP}:30300"
echo ""

echo "🔐 Default Login:"
echo "  Username: admin"
echo "  Password: admin"
echo "  (You'll be prompted to change on first login)"
echo ""

echo "📈 Next Steps:"
echo "  1. Login at https://grafana.charn.io"
echo "  2. Change default password"
echo "  3. Go to Dashboards → Import"
echo "  4. Import popular dashboards:"
echo "     • 315  - Kubernetes Cluster Monitoring"
echo "     • 6417 - Kubernetes Pod Resources"
echo "     • 1860 - Node Exporter Full"
echo "     • 7249 - Kubernetes Cluster"
echo "  5. Prometheus datasource is pre-configured"
echo ""

echo "📝 Useful Commands:"
echo "  • View logs:    kubectl logs -f -n monitoring -l app=grafana"
echo "  • Check status: kubectl get pods -n monitoring"
echo "  • Restart:      kubectl rollout restart deployment/grafana -n monitoring"
echo "  • Delete:       kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "📖 Documentation:"
echo "  • Setup guide: apps/grafana/base/SETUP.md"
echo "  • Official:    https://grafana.com/docs/"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n monitoring -l app=grafana --tail=10 2>/dev/null || echo "Waiting for logs..."
