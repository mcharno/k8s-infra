# Nextcloud

Nextcloud is a self-hosted file sync and share platform deployed on the K3s homelab cluster.

## Overview

**Deployment:** apps/nextcloud/base/
**Namespace:** nextcloud
**Image:** nextcloud:stable
**Database:** Shared PostgreSQL (postgres-lb.database.svc.cluster.local)
**Documentation:** [docs/applications/nextcloud.md](../../../docs/applications/nextcloud.md)

## Quick Deploy

```bash
# Deploy using Kustomize
kubectl apply -k apps/nextcloud/base/

# Or use the install script (recommended for first-time setup)
bash apps/nextcloud/base/install.sh
```

**Prerequisites:**
- Shared PostgreSQL must be running (`kubectl get pods -n database`)
- Secrets must exist or will be created by install script

## Access URLs

- **External (from anywhere):** https://nextcloud.charn.io
- **Local (faster at home):** https://nextcloud.local.charn.io
- **Direct NodePort:** http://PI_IP:30080

## Key Configuration

### Database

Uses shared PostgreSQL database (saves ~256Mi RAM vs dedicated instance):
- Host: `postgres-lb.database.svc.cluster.local`
- Database: `nextcloud`
- User: `nextcloud`
- Password: Stored in `nextcloud-secrets` secret

**Manual Database Setup Required:**
```bash
# Get database password
kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.db-password}' | base64 -d

# Connect to PostgreSQL
kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres

# Create database and user
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'your-password-here';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
\q
```

### Storage

- **Size:** 100Gi
- **StorageClass:** local-path
- **Mount:** /var/www/html
- **Host Location:** /mnt/lvm-storage/nextcloud-data-pvc-*

### Resources

```yaml
requests:
  cpu: 500m
  memory: 512Mi
limits:
  cpu: 2 cores
  memory: 2Gi
```

### Important Environment Variables

```yaml
NEXTCLOUD_TRUSTED_DOMAINS: "nextcloud.charn.io nextcloud.local.charn.io localhost 192.168.0.23"
OVERWRITEPROTOCOL: https
OVERWRITEHOST: nextcloud.charn.io
TRUSTED_PROXIES: "10.42.0.0/16"  # Kubernetes pod network
```

### Ingress Annotations

```yaml
nginx.ingress.kubernetes.io/proxy-body-size: "10G"        # Large file uploads
nginx.ingress.kubernetes.io/proxy-buffering: "off"
nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
nginx.ingress.kubernetes.io/force-ssl-redirect: "false"   # External only
```

## Common Operations

### View Logs

```bash
kubectl logs -f -n nextcloud -l app=nextcloud
```

### Restart

```bash
kubectl rollout restart deployment/nextcloud -n nextcloud
```

### Get Admin Password

```bash
kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d
```

### Access Shell

```bash
kubectl exec -it -n nextcloud deployment/nextcloud -- bash
```

### Run occ Commands

```bash
# Check status
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ status

# Add missing database indices
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ db:add-missing-indices

# Clean up file versions
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ versions:cleanup
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n nextcloud

# View events
kubectl describe pod -n nextcloud -l app=nextcloud

# Check logs
kubectl logs -n nextcloud -l app=nextcloud --tail=100
```

**Common issues:**
- Database not ready: Ensure PostgreSQL is running
- PVC pending: Normal with WaitForFirstConsumer, binds when pod schedules
- HTTP 500 on first access: Initialization takes 5-10 minutes

### Untrusted Domain Error

If you see "Access through untrusted domain":

```bash
# Add domain to NEXTCLOUD_TRUSTED_DOMAINS in deployment.yaml
# Or edit config directly:
kubectl exec -n nextcloud deployment/nextcloud -- vi /var/www/html/config/config.php
```

### Large File Upload Fails

Ensure Ingress has correct annotations:
```yaml
nginx.ingress.kubernetes.io/proxy-body-size: "10G"
```

## Migration from Dedicated to Shared PostgreSQL

Nextcloud was migrated from a dedicated PostgreSQL instance to the shared database:

**Before:**
- Dedicated postgres:15-alpine pod (256Mi RAM)
- Total: 2 PostgreSQL instances (Nextcloud + Wallabag = 512Mi)

**After:**
- Uses shared postgres-lb.database.svc.cluster.local
- Saves: ~256Mi RAM

See [SETUP.md](SETUP.md) for migration details.

## Desktop and Mobile Clients

**Download:** https://nextcloud.com/install/#install-clients

**Setup:**
- Server URL: `https://nextcloud.charn.io` (or local URL)
- Username: admin (or your user)
- Password: Use app-specific password (Settings → Security)

## Post-Installation

After first deployment:

1. **Access Nextcloud:** https://nextcloud.charn.io
2. **Login:** Use admin credentials from secret
3. **Complete Setup Wizard:** Follow any prompts
4. **Change Admin Password:** Settings → Personal → Security
5. **Enable 2FA:** Settings → Security → Two-factor authentication
6. **Install Apps:** Files, Calendar, Contacts, etc.
7. **Setup Desktop Sync:** Download client and configure

## Backup

Critical data to backup:
- Nextcloud data PVC (100Gi user files)
- Database (in shared PostgreSQL)
- Secrets (nextcloud-secrets)

See [SETUP.md](SETUP.md) for backup procedures.

## Documentation

- **[SETUP.md](SETUP.md)** - Complete deployment history, troubleshooting, migration details
- **[Application Docs](../../../docs/applications/nextcloud.md)** - User-facing documentation
- **[PostgreSQL Docs](../../../docs/infrastructure/postgres.md)** - Shared database info

## Related

- [Shared PostgreSQL](../../../infrastructure/databases/postgres/)
- [Storage Configuration](../../../docs/infrastructure/storage.md)
- [Network Configuration](../../../docs/infrastructure/network.md)
- [Disaster Recovery](../../../docs/disaster-recovery.md)
