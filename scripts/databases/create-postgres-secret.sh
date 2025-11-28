#!/bin/bash

# Create PostgreSQL password secret
# Run with: bash create-postgres-secret.sh

set -e

echo "=== Creating PostgreSQL Password Secret ==="
echo ""

# Generate secure passwords
echo "Generating passwords..."
ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
NEXTCLOUD_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
WALLABAG_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Create namespace if it doesn't exist
kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -

# Create secret
echo "Creating secret..."
kubectl create secret generic postgres-passwords \
  --from-literal=admin-password="${ADMIN_PASSWORD}" \
  --from-literal=nextcloud-password="${NEXTCLOUD_PASSWORD}" \
  --from-literal=wallabag-password="${WALLABAG_PASSWORD}" \
  -n database \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret created: postgres-passwords in namespace database"
echo ""

# Save credentials to file (for backup purposes)
CREDENTIALS_FILE="postgres-credentials-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CREDENTIALS_FILE" <<EOF
PostgreSQL Credentials
Generated: $(date)
======================

Admin Access:
Host: postgres-lb.database.svc.cluster.local
Port: 5432
User: postgres
Password: ${ADMIN_PASSWORD}

Application Databases:
----------------------

Nextcloud:
  Database: nextcloud
  User: nextcloud
  Password: ${NEXTCLOUD_PASSWORD}
  Connection: postgresql://nextcloud:${NEXTCLOUD_PASSWORD}@postgres-lb.database.svc.cluster.local:5432/nextcloud

Wallabag:
  Database: wallabag
  User: wallabag
  Password: ${WALLABAG_PASSWORD}
  Connection: postgresql://wallabag:${WALLABAG_PASSWORD}@postgres-lb.database.svc.cluster.local:5432/wallabag

To retrieve passwords later:
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.admin-password}' | base64 -d
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.nextcloud-password}' | base64 -d
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.wallabag-password}' | base64 -d

Connect to database:
kubectl exec -it -n database postgres-0 -- psql -U postgres

Backup command:
kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup.sql
EOF

echo "📝 Credentials saved to: $CREDENTIALS_FILE"
echo ""
echo "⚠️  IMPORTANT: Store this file securely and delete it from the server!"
echo "   Consider moving it to a password manager or secure backup location."
echo ""
