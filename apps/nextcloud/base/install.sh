#!/bin/bash

# Install Nextcloud on K3s using Kustomize
# This script deploys Nextcloud with shared PostgreSQL database
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Nextcloud on K3s ==="
echo ""

# Check if shared PostgreSQL is running
echo "Checking PostgreSQL database..."
if ! kubectl get deployment postgres-lb -n database >/dev/null 2>&1; then
    echo "❌ Shared PostgreSQL not found!"
    echo ""
    echo "Nextcloud requires the shared PostgreSQL database."
    echo "Please deploy it first:"
    echo "  kubectl apply -k infrastructure/databases/postgres/"
    echo ""
    exit 1
fi

PG_STATUS=$(kubectl get pods -n database -l app=postgres-lb -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
if [ "$PG_STATUS" != "Running" ]; then
    echo "❌ PostgreSQL is not running (status: $PG_STATUS)"
    echo "Please ensure PostgreSQL is healthy before deploying Nextcloud."
    exit 1
fi

echo "✓ PostgreSQL database is running"
echo ""

# Check if secrets exist
echo "Checking for nextcloud-secrets..."
if ! kubectl get secret nextcloud-secrets -n nextcloud >/dev/null 2>&1; then
    echo "⚠️  nextcloud-secrets not found. Creating new secrets..."
    echo ""

    # Generate passwords
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    # Create namespace first
    kubectl create namespace nextcloud --dry-run=client -o yaml | kubectl apply -f -

    # Create secret
    kubectl create secret generic nextcloud-secrets -n nextcloud \
        --from-literal=db-password="$DB_PASSWORD" \
        --from-literal=admin-password="$ADMIN_PASSWORD"

    echo "✓ Secrets created"
    echo ""
    echo "🔐 IMPORTANT: Save these credentials!"
    echo "   Admin Username: admin"
    echo "   Admin Password: $ADMIN_PASSWORD"
    echo "   DB Password: $DB_PASSWORD"
    echo ""
    echo "   Saved to: nextcloud-credentials.txt"
    echo ""

    # Save credentials
    cat > nextcloud-credentials.txt <<CREDS
Nextcloud Credentials
=====================
URL (External): https://nextcloud.charn.io
URL (Local): https://nextcloud.local.charn.io
URL (NodePort): http://$(hostname -I | awk '{print $1}'):30080

Admin Username: admin
Admin Password: $ADMIN_PASSWORD
Database Password: $DB_PASSWORD

Retrieve passwords later:
kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d
kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.db-password}' | base64 -d
CREDS

else
    echo "✓ Using existing nextcloud-secrets"
    echo ""
fi

# Deploy using Kustomize
echo "Deploying Nextcloud with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# Add nextcloud database user to PostgreSQL
echo "Configuring PostgreSQL database user..."
echo ""
echo "IMPORTANT: You need to manually create the Nextcloud database user in PostgreSQL."
echo ""
echo "Run these commands:"
echo ""
echo "# Get database password:"
echo "kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.db-password}' | base64 -d"
echo ""
echo "# Connect to PostgreSQL:"
echo "kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres"
echo ""
echo "# Then run these SQL commands (replace PASSWORD with the password above):"
echo "CREATE DATABASE nextcloud;"
echo "CREATE USER nextcloud WITH PASSWORD 'PASSWORD';"
echo "GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;"
echo "\\q"
echo ""

read -p "Press Enter after you've created the database user..."

# Monitor startup
echo ""
echo "Monitoring Nextcloud startup..."
echo "This will take 5-10 minutes for initial setup..."
echo ""

for i in {1..60}; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Get ready status
    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n nextcloud $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n nextcloud $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/60] Status: $POD_STATUS | Ready: $READY | $REASON"

    # Check for success
    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Nextcloud is ready!"
        break
    fi

    # Check for persistent failures
    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Nextcloud failed to start"
        echo ""
        echo "Pod events:"
        kubectl get events -n nextcloud --sort-by='.lastTimestamp' | tail -10
        echo ""
        echo "Pod logs:"
        kubectl logs -n nextcloud -l app=nextcloud --tail=50 2>/dev/null || echo "No logs available"
        exit 1
    fi

    sleep 15
done

echo ""
echo "=== Nextcloud Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n nextcloud -o wide
echo ""

echo "💾 Storage:"
kubectl get pvc -n nextcloud
echo ""

echo "🌐 Access Nextcloud:"
echo ""
echo "  External (from anywhere):"
echo "    https://nextcloud.charn.io"
echo ""
echo "  Local (faster when at home):"
echo "    https://nextcloud.local.charn.io"
echo ""
echo "  Direct NodePort (for testing):"
echo "    http://${PI_IP}:30080"
echo ""

echo "🔐 Admin Credentials:"
echo "  Username: admin"
echo "  Password: (saved in nextcloud-credentials.txt)"
echo ""
echo "  Retrieve password:"
echo "  kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d"
echo ""

echo "📝 Useful Commands:"
echo "  • View logs:        kubectl logs -f -n nextcloud -l app=nextcloud"
echo "  • Check status:     kubectl get pods -n nextcloud"
echo "  • Check events:     kubectl get events -n nextcloud --sort-by='.lastTimestamp'"
echo "  • Restart:          kubectl rollout restart deployment/nextcloud -n nextcloud"
echo "  • Shell access:     kubectl exec -it -n nextcloud deployment/nextcloud -- bash"
echo "  • Delete:           kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "⚙️ Configuration:"
echo "  • Database:         Shared PostgreSQL (postgres-lb.database.svc.cluster.local)"
echo "  • Data location:    /var/www/html"
echo "  • PVC mount:        /mnt/lvm-storage/nextcloud-data-pvc-*"
echo "  • Storage:          100Gi"
echo ""

echo "⚠️  Post-Installation Steps:"
echo "  1. Wait 2-3 minutes for full initialization"
echo "  2. Access https://nextcloud.charn.io (or local URL)"
echo "  3. Login with admin credentials"
echo "  4. Complete any setup wizard steps"
echo "  5. Install recommended apps (Files, Calendar, Contacts)"
echo "  6. Configure desktop/mobile sync clients"
echo ""

echo "📖 Documentation:"
echo "  • Application docs: docs/applications/nextcloud.md"
echo "  • Setup guide:      apps/nextcloud/base/SETUP.md"
echo "  • Manifests:        apps/nextcloud/base/"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n nextcloud -l app=nextcloud --tail=20 2>/dev/null || echo "Waiting for logs..."
