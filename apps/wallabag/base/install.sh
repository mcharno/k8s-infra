#!/bin/bash

# Install Wallabag on K3s using Kustomize
# This script deploys Wallabag with shared PostgreSQL and Redis
# Run with: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Wallabag on K3s ==="
echo ""

# Check if shared PostgreSQL is running
echo "Checking PostgreSQL database..."
if ! kubectl get deployment postgres-lb -n database >/dev/null 2>&1; then
    echo "❌ Shared PostgreSQL not found!"
    echo ""
    echo "Wallabag requires the shared PostgreSQL database."
    echo "Please deploy it first:"
    echo "  kubectl apply -k infrastructure/databases/postgres/"
    echo ""
    exit 1
fi

PG_STATUS=$(kubectl get pods -n database -l app=postgres-lb -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
if [ "$PG_STATUS" != "Running" ]; then
    echo "❌ PostgreSQL is not running (status: $PG_STATUS)"
    echo "Please ensure PostgreSQL is healthy before deploying Wallabag."
    exit 1
fi

echo "✓ PostgreSQL database is running"
echo ""

# Check if shared Redis is running
echo "Checking Redis cache..."
if ! kubectl get deployment redis-lb -n database >/dev/null 2>&1; then
    echo "❌ Shared Redis not found!"
    echo ""
    echo "Wallabag requires the shared Redis cache."
    echo "Please deploy it first:"
    echo "  kubectl apply -k infrastructure/databases/redis/"
    echo ""
    exit 1
fi

REDIS_STATUS=$(kubectl get pods -n database -l app=redis-lb -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
if [ "$REDIS_STATUS" != "Running" ]; then
    echo "❌ Redis is not running (status: $REDIS_STATUS)"
    echo "Please ensure Redis is healthy before deploying Wallabag."
    exit 1
fi

echo "✓ Redis cache is running"
echo ""

# Check if secrets exist
echo "Checking for wallabag-secrets..."
if ! kubectl get secret wallabag-secrets -n wallabag >/dev/null 2>&1; then
    echo "⚠️  wallabag-secrets not found. Creating new secrets..."
    echo ""

    # Generate passwords
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    SECRET=$(openssl rand -hex 32)

    # Create namespace first
    kubectl create namespace wallabag --dry-run=client -o yaml | kubectl apply -f -

    # Create secret
    kubectl create secret generic wallabag-secrets -n wallabag \
        --from-literal=db-password="$DB_PASSWORD" \
        --from-literal=secret="$SECRET"

    echo "✓ Secrets created"
    echo ""
    echo "🔐 IMPORTANT: Save these credentials!"
    echo "   DB Password: $DB_PASSWORD"
    echo "   Secret: $SECRET"
    echo ""
    echo "   Saved to: wallabag-credentials.txt"
    echo ""

    # Save credentials
    cat > wallabag-credentials.txt <<CREDS
Wallabag Credentials
====================
URL (External): https://bag.charn.io
URL (Local): https://wallabag.local.charn.io
URL (NodePort): http://$(hostname -I | awk '{print $1}'):30086

Default Login (CHANGE THIS IMMEDIATELY!):
Username: wallabag
Password: wallabag

Database Password: $DB_PASSWORD
Secret: $SECRET

Retrieve passwords later:
kubectl get secret wallabag-secrets -n wallabag -o jsonpath='{.data.db-password}' | base64 -d
kubectl get secret wallabag-secrets -n wallabag -o jsonpath='{.data.secret}' | base64 -d

API Docs: https://bag.charn.io/api/doc
CREDS

else
    echo "✓ Using existing wallabag-secrets"
    echo ""
fi

# Deploy using Kustomize
echo "Deploying Wallabag with Kustomize..."
kubectl apply -k "$SCRIPT_DIR/"

echo "✓ Resources created"
echo ""

# Add wallabag database user to PostgreSQL
echo "Configuring PostgreSQL database user..."
echo ""
echo "IMPORTANT: You need to manually create the Wallabag database user in PostgreSQL."
echo ""
echo "Run these commands:"
echo ""
echo "# Get database password:"
echo "kubectl get secret wallabag-secrets -n wallabag -o jsonpath='{.data.db-password}' | base64 -d"
echo ""
echo "# Connect to PostgreSQL:"
echo "kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres"
echo ""
echo "# Then run these SQL commands (replace PASSWORD with the password above):"
echo "CREATE DATABASE wallabag;"
echo "CREATE USER wallabag WITH PASSWORD 'PASSWORD';"
echo "GRANT ALL PRIVILEGES ON DATABASE wallabag TO wallabag;"
echo "\\q"
echo ""

read -p "Press Enter after you've created the database user..."

# Monitor startup
echo ""
echo "Monitoring Wallabag startup..."
echo "This will take 2-3 minutes for database migrations..."
echo ""

for i in {1..40}; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n wallabag -l app=wallabag -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Waiting")
    POD_NAME=$(kubectl get pods -n wallabag -l app=wallabag -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Get ready status
    if [ -n "$POD_NAME" ]; then
        READY=$(kubectl get pod -n wallabag $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        REASON=$(kubectl get pod -n wallabag $POD_NAME -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    else
        READY="False"
        REASON=""
    fi

    echo "[$i/40] Status: $POD_STATUS | Ready: $READY | $REASON"

    # Check for success
    if [ "$POD_STATUS" = "Running" ] && [ "$READY" = "True" ]; then
        echo ""
        echo "✅ Wallabag is ready!"
        break
    fi

    # Check for persistent failures
    if [ "$POD_STATUS" = "Failed" ] || [ "$REASON" = "CrashLoopBackOff" ]; then
        echo ""
        echo "❌ Wallabag failed to start"
        echo ""
        echo "Pod events:"
        kubectl get events -n wallabag --sort-by='.lastTimestamp' | tail -10
        echo ""
        echo "Pod logs:"
        kubectl logs -n wallabag -l app=wallabag --tail=50 2>/dev/null || echo "No logs available"
        exit 1
    fi

    sleep 10
done

echo ""
echo "=== Wallabag Installation Complete! ==="
echo ""

PI_IP=$(hostname -I | awk '{print $1}')

echo "📊 Status:"
kubectl get pods -n wallabag -o wide
echo ""

echo "💾 Storage:"
kubectl get pvc -n wallabag
echo ""

echo "🌐 Access Wallabag:"
echo ""
echo "  External (from anywhere):"
echo "    https://bag.charn.io"
echo ""
echo "  Local (faster when at home):"
echo "    https://wallabag.local.charn.io"
echo ""
echo "  Direct NodePort (for testing):"
echo "    http://${PI_IP}:30086"
echo ""

echo "🔐 Default Login (CHANGE IMMEDIATELY!):"
echo "  Username: wallabag"
echo "  Password: wallabag"
echo ""
echo "  ⚠️  CHANGE THE DEFAULT PASSWORD AFTER FIRST LOGIN!"
echo ""

echo "📝 Useful Commands:"
echo "  • View logs:        kubectl logs -f -n wallabag -l app=wallabag"
echo "  • Check status:     kubectl get pods -n wallabag"
echo "  • Check events:     kubectl get events -n wallabag --sort-by='.lastTimestamp'"
echo "  • Restart:          kubectl rollout restart deployment/wallabag -n wallabag"
echo "  • Shell access:     kubectl exec -it -n wallabag deployment/wallabag -- bash"
echo "  • Delete:           kubectl delete -k $SCRIPT_DIR/"
echo ""

echo "⚙️  Configuration:"
echo "  • Database:         Shared PostgreSQL (postgres-lb.database.svc.cluster.local)"
echo "  • Cache:            Shared Redis (redis-lb.database.svc.cluster.local)"
echo "  • Images location:  /var/www/wallabag/web/assets/images"
echo "  • PVC mount:        /mnt/lvm-storage/wallabag-images-pvc-*"
echo "  • Storage:          10Gi"
echo ""

echo "📱 Mobile Apps & Extensions:"
echo "  • Browser extensions: Chrome, Firefox, Safari"
echo "  • Mobile apps: iOS (App Store), Android (Google Play)"
echo "  • API documentation: https://bag.charn.io/api/doc"
echo ""

echo "⚠️  Post-Installation Steps:"
echo "  1. Access https://bag.charn.io (or local URL)"
echo "  2. Login with wallabag/wallabag"
echo "  3. IMMEDIATELY change password in Settings → User management"
echo "  4. Create additional user accounts if needed"
echo "  5. Install browser extensions for easy article saving"
echo "  6. Configure mobile apps with API credentials"
echo "  7. Disable user registration (already done via FOSUSER_REGISTRATION=false)"
echo ""

echo "📖 Documentation:"
echo "  • Application docs: docs/applications/wallabag.md"
echo "  • Setup guide:      apps/wallabag/base/SETUP.md"
echo "  • Manifests:        apps/wallabag/base/"
echo ""

# Show recent logs
echo "Recent logs:"
kubectl logs -n wallabag -l app=wallabag --tail=20 2>/dev/null || echo "Waiting for logs..."
