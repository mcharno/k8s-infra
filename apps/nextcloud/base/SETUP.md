# Nextcloud Setup and Deployment Guide

This document describes how Nextcloud was deployed on the K3s cluster, including configuration decisions, troubleshooting steps, migration to shared PostgreSQL, and operational notes.

## Overview

Nextcloud is deployed as a containerized application on the K3s cluster with:
- 100Gi persistent storage for data
- Shared PostgreSQL database (saves ~256Mi RAM vs dedicated instance)
- Hybrid HTTPS access (external via Cloudflare, local direct)
- Resource limits tuned for Raspberry Pi 4
- Large file upload support (10GB limit)

## Deployment Evolution

### Version 1: Dedicated PostgreSQL Database

**Script:** `docs/install_nextcloud.sh`

**Configuration:**
```yaml
# Dedicated PostgreSQL pod
postgres:
  image: postgres:15-alpine
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m
  storage: 10Gi

# Nextcloud connected to dedicated database
env:
  - name: POSTGRES_HOST
    value: postgres  # Local service in same namespace
```

**Pros:**
- Isolated database
- Easy to deploy (all in one script)
- No dependencies on other services

**Cons:**
- Extra RAM usage (256Mi+ per instance)
- Multiple PostgreSQL instances running (Nextcloud + Wallabag = 512Mi)
- More pods to manage

**Outcome:** Worked well but consumed too much RAM on Pi

### Version 2: Migrated to Shared PostgreSQL

**Current Production Configuration**

**Configuration:**
```yaml
# Uses shared PostgreSQL in database namespace
env:
  - name: POSTGRES_HOST
    value: postgres-lb.database.svc.cluster.local
```

**Pros:**
- Saves ~256Mi RAM (no dedicated Postgres pod)
- Centralized database management
- Single backup point for multiple apps
- Better resource utilization

**Cons:**
- Dependency on shared service
- Slightly more complex setup (must create database manually)
- All apps share PostgreSQL resources

**Migration Process:**
1. Deployed shared PostgreSQL cluster
2. Created nextcloud database and user in shared instance
3. Updated Nextcloud POSTGRES_HOST to point to shared service
4. Restarted Nextcloud to connect to new database
5. Removed dedicated PostgreSQL deployment

**Outcome:** Current production configuration, saves significant RAM

## Configuration Details

### Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data
  namespace: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Gi
```

**Notes:**
- Uses `local-path` provisioner with `WaitForFirstConsumer` mode
- PVC will stay Pending until pod is scheduled (this is normal)
- Stores all Nextcloud data including uploads, apps, config
- Host location: `/mnt/lvm-storage/nextcloud-data-pvc-*`

**Data Structure:**
```
/var/www/html/
├── config/           # Nextcloud configuration files
├── data/             # User files and uploads
├── apps/             # Installed apps
├── themes/           # Custom themes
└── custom_apps/      # Custom installed apps
```

### Database Configuration

**Connection to Shared PostgreSQL:**
```yaml
env:
  - name: POSTGRES_HOST
    value: postgres-lb.database.svc.cluster.local
  - name: POSTGRES_DB
    value: nextcloud
  - name: POSTGRES_USER
    value: nextcloud
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: nextcloud-secrets
        key: db-password
```

**Database Setup (manual step required):**
```sql
-- Connect to PostgreSQL
kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres

-- Create database and user
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'your-password-here';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
\q
```

**Why Manual Setup:**
- Shared PostgreSQL is in different namespace (database)
- Can't auto-create users without elevated privileges
- One-time setup during initial deployment
- Passwords stored in Kubernetes secrets

### Proxy and Trusted Domains

**Environment Variables:**
```yaml
env:
  # Trusted domains for access
  - name: NEXTCLOUD_TRUSTED_DOMAINS
    value: "nextcloud.charn.io nextcloud.local.charn.io localhost 192.168.0.23"

  # Proxy configuration (for Ingress)
  - name: APACHE_DISABLE_REWRITE_IP
    value: "1"
  - name: TRUSTED_PROXIES
    value: "10.42.0.0/16"  # Kubernetes pod network
  - name: OVERWRITEPROTOCOL
    value: https
  - name: OVERWRITEHOST
    value: nextcloud.charn.io
  - name: OVERWRITECLIURL
    value: https://nextcloud.charn.io
```

**Why These Settings:**
- `TRUSTED_DOMAINS`: Prevents "untrusted domain" errors
- `APACHE_DISABLE_REWRITE_IP`: Stops Apache from rewriting IPs (breaks behind proxy)
- `TRUSTED_PROXIES`: Trusts Nginx Ingress to forward real client IP
- `OVERWRITEPROTOCOL`/`OVERWRITEHOST`: Generates correct URLs in emails/shares

### Networking

**Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nextcloud
  namespace: nextcloud
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

**External Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud-external
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"  # Important!
    nginx.ingress.kubernetes.io/proxy-body-size: "10G"       # Large file uploads
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - nextcloud.charn.io
      secretName: charn-io-wildcard-tls
  rules:
    - host: nextcloud.charn.io
      http:
        paths:
          - path: /
            backend:
              service:
                name: nextcloud
                port:
                  number: 80
```

**Local Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud-local
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"   # Can force SSL locally
    nginx.ingress.kubernetes.io/proxy-body-size: "10G"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - nextcloud.local.charn.io
      secretName: local-charn-io-wildcard-tls
  rules:
    - host: nextcloud.local.charn.io
      http:
        paths:
          - path: /
            backend:
              service:
                name: nextcloud
                port:
                  number: 80
```

**Key Annotations:**
- `proxy-body-size: 10G` - Allows large file uploads (default is 1MB!)
- `proxy-buffering: off` - Better for large file uploads/downloads
- `force-ssl-redirect: false` (external) - Cloudflare Tunnel sends HTTP, Nginx shouldn't redirect
- `force-ssl-redirect: true` (local) - Can safely redirect to HTTPS for local access

### Resource Configuration

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 2Gi
```

**Reasoning:**
- **Requests (500m/512Mi)**: Ensures pod can schedule and run basic operations
- **Limits (2 cores/2Gi)**: Allows bursts during file uploads, photo processing
- **Testing showed**: Initial setup needs ~800Mi, regular use 512-768Mi, heavy uploads can spike to 1.5Gi

**Observed Usage:**
- Idle: 400-500Mi RAM, 5-10% CPU
- File upload: 600-1000Mi RAM, 20-50% CPU
- Photo scanning: 800-1500Mi RAM, 50-100% CPU
- Multiple users: Up to 1.5Gi RAM, 100%+ CPU

### Health Probes

```yaml
startupProbe:
  httpGet:
    path: /status.php
    port: 80
    httpHeaders:
    - name: Host
      value: "192.168.0.23"
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 60  # 10 minutes total for first start

livenessProbe:
  httpGet:
    path: /status.php
    port: 80
    httpHeaders:
    - name: Host
      value: "192.168.0.23"
  initialDelaySeconds: 600  # 10 minutes
  periodSeconds: 30
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /status.php
    port: 80
    httpHeaders:
    - name: Host
      value: "192.168.0.23"
  initialDelaySeconds: 300  # 5 minutes
  periodSeconds: 10
  failureThreshold: 3
```

**Why Long Delays:**
- Initial startup takes 5-10 minutes (database migrations, app setup)
- Without long delays, pod gets killed before initialization completes
- Learned from troubleshooting - short timeouts caused CrashLoopBackOff

**Why httpHeaders with IP:**
- Nextcloud validates Host header against TRUSTED_DOMAINS
- Using IP bypasses domain validation for health checks
- Prevents probe failures when accessing via pod IP

## Common Issues and Solutions

### Issue 1: HTTP 500 Errors on First Access

**Symptoms:**
- Pod is Running but returns HTTP 500
- Logs show database connection errors or initialization failures

**Cause:**
- Nextcloud initialization not complete
- Database not ready
- Config files being written

**Solution from fix_nextcloud_500.sh:**
```bash
# Temporarily disable probes to allow initialization
kubectl patch deployment nextcloud -n nextcloud --type=json -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"},
  {"op": "remove", "path": "/spec/template/spec/containers/0/readinessProbe"}
]'

# Delete pod to recreate without probes
kubectl delete pod -n nextcloud -l app=nextcloud

# Wait for initialization to complete (monitor logs)
kubectl logs -f -n nextcloud -l app=nextcloud

# Once working, re-enable probes
kubectl apply -k apps/nextcloud/base/
```

**Prevention:**
- Use long initialDelaySeconds in probes (current config has this)
- Ensure database is ready before deploying Nextcloud
- Don't scale replicas >1 during initial setup

### Issue 2: Untrusted Domain Errors

**Symptoms:**
- "Access through untrusted domain" error in browser
- Works on one URL but not another

**Cause:**
- NEXTCLOUD_TRUSTED_DOMAINS doesn't include the accessed domain

**Solution:**
```bash
# Update deployment.yaml
env:
  - name: NEXTCLOUD_TRUSTED_DOMAINS
    value: "nextcloud.charn.io nextcloud.local.charn.io localhost 192.168.0.23 newdomain.com"

# Apply changes
kubectl apply -k apps/nextcloud/base/

# Or edit config.php directly
kubectl exec -n nextcloud deployment/nextcloud -- vi /var/www/html/config/config.php
```

### Issue 3: Large File Upload Failures

**Symptoms:**
- Uploads fail for files >1GB
- 413 Request Entity Too Large errors

**Cause:**
- Nginx default body size is 1MB
- Missing proxy-body-size annotation

**Solution:**
```yaml
# In ingress.yaml annotations
nginx.ingress.kubernetes.io/proxy-body-size: "10G"  # Or higher
nginx.ingress.kubernetes.io/proxy-buffering: "off"
nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
```

**Also check Nextcloud config:**
```bash
# Increase PHP upload limits (if needed)
kubectl exec -n nextcloud deployment/nextcloud -- bash -c '
  echo "upload_max_filesize = 10G" >> /usr/local/etc/php/conf.d/uploads.ini
  echo "post_max_size = 10G" >> /usr/local/etc/php/conf.d/uploads.ini
  apache2ctl graceful
'
```

### Issue 4: Database Connection Failures After Restart

**Symptoms:**
- Nextcloud can't connect to database after pod restart
- "SQLSTATE[08006]" errors in logs

**Cause:**
- PostgreSQL pod restarted and IP changed
- DNS resolution issue
- Database not accepting connections

**Solution:**
```bash
# Check PostgreSQL is running
kubectl get pods -n database

# Test database connection from Nextcloud pod
kubectl exec -n nextcloud deployment/nextcloud -- bash -c '
  apt-get update && apt-get install -y postgresql-client
  psql -h postgres-lb.database.svc.cluster.local -U nextcloud -d nextcloud -c "SELECT version();"
'

# If connection fails, check PostgreSQL logs
kubectl logs -n database -l app=postgres-lb

# Restart Nextcloud after database is healthy
kubectl rollout restart deployment/nextcloud -n nextcloud
```

### Issue 5: CrashLoopBackOff on Deploy

**Symptoms:**
- Pod repeatedly crashes
- Never reaches Running state

**Common Causes & Solutions:**

**1. PVC not binding:**
```bash
kubectl get pvc -n nextcloud
# If Pending, check if pod is scheduled (WaitForFirstConsumer)
kubectl get pods -n nextcloud
```

**2. Database not ready:**
```bash
# Ensure PostgreSQL is running first
kubectl get pods -n database
kubectl wait --for=condition=Ready pod -l app=postgres-lb -n database --timeout=120s
```

**3. Memory limit too low:**
```bash
# Check for OOMKilled
kubectl describe pod -n nextcloud -l app=nextcloud | grep -i oom

# If found, increase limits in deployment.yaml
resources:
  limits:
    memory: 2Gi  # Increase if needed
```

**4. Probes killing pod too early:**
```bash
# Check probe failure in events
kubectl get events -n nextcloud --sort-by='.lastTimestamp' | grep probe

# Increase initialDelaySeconds or disable temporarily
```

## Deployment Process

### Fresh Installation

1. **Prerequisites:**
```bash
# Ensure shared PostgreSQL is running
kubectl get pods -n database

# Create namespace
kubectl create namespace nextcloud
```

2. **Create Secrets:**
```bash
# Generate passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Create secret
kubectl create secret generic nextcloud-secrets -n nextcloud \
  --from-literal=db-password="$DB_PASSWORD" \
  --from-literal=admin-password="$ADMIN_PASSWORD"

# Save passwords securely!
echo "Admin: $ADMIN_PASSWORD" > nextcloud-credentials.txt
echo "DB: $DB_PASSWORD" >> nextcloud-credentials.txt
```

3. **Setup Database:**
```bash
# Connect to PostgreSQL
kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres

# Create database and user
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'paste-db-password-here';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
\q
```

4. **Deploy Nextcloud:**
```bash
# Deploy using Kustomize
kubectl apply -k apps/nextcloud/base/

# Or use install script
bash apps/nextcloud/base/install.sh
```

5. **Monitor Startup:**
```bash
# Watch pod creation
kubectl get pods -n nextcloud -w

# Follow logs
kubectl logs -f -n nextcloud -l app=nextcloud

# Wait for Ready status (can take 5-10 minutes)
kubectl wait --for=condition=Ready pod -l app=nextcloud -n nextcloud --timeout=600s
```

6. **Access Nextcloud:**
```bash
# Get access URL
echo "https://nextcloud.charn.io"

# Get admin password
kubectl get secret nextcloud-secrets -n nextcloud -o jsonpath='{.data.admin-password}' | base64 -d
```

### Installation Script

The `install.sh` script automates most of this:
- Checks PostgreSQL is running
- Creates/checks for secrets
- Deploys via Kustomize
- Guides you through manual database setup
- Monitors startup
- Displays access info and credentials

## Operational Notes

### File Uploads and Performance

**Large File Handling:**
- 10GB upload limit configured (via Ingress annotation)
- Direct local access is faster for large files
- Chunked uploading used automatically by clients

**Performance Tips:**
- Use local URL (nextcloud.local.charn.io) when at home - much faster
- External URL (nextcloud.charn.io) goes through Cloudflare - adds latency
- Desktop sync client caches locally - recommended for frequent access

### Desktop and Mobile Clients

**Desktop Sync:**
- Download from: https://nextcloud.com/install/#install-clients
- Server URL: `https://nextcloud.charn.io` (or local)
- Use app-specific password (not admin password)

**Mobile Apps:**
- iOS: Nextcloud from App Store
- Android: Nextcloud from Google Play or F-Droid
- Better than web interface for photos

**App-Specific Passwords:**
```
Settings → Personal → Security → Create new app password
```

### Maintenance Tasks

**Update Nextcloud:**
```bash
# Pull latest stable image
kubectl rollout restart deployment/nextcloud -n nextcloud

# Watch update
kubectl rollout status deployment/nextcloud -n nextcloud

# Check version after restart
# Via web UI: Settings → Overview
```

**Database Maintenance:**
```bash
# Run Nextcloud's database maintenance
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ db:add-missing-indices
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ db:add-missing-columns

# Clean up old file versions
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ versions:cleanup
```

**Clear Caches:**
```bash
# Clear Redis cache (if using)
kubectl exec -n nextcloud deployment/nextcloud -- php /var/www/html/occ files:cleanup

# Clear app cache
kubectl exec -n nextcloud deployment/nextcloud -- rm -rf /var/www/html/data/appdata_*/css/*
kubectl exec -n nextcloud deployment/nextcloud -- rm -rf /var/www/html/data/appdata_*/js/*
```

## Backup and Recovery

### What to Backup

1. **Nextcloud Data PVC** (100Gi - user files)
2. **Nextcloud Database** (in shared PostgreSQL)
3. **Secrets** (nextcloud-secrets)

### Backup Process

```bash
# 1. Backup data directory
kubectl exec -n nextcloud deployment/nextcloud -- tar czf /tmp/nextcloud-data.tar.gz /var/www/html
kubectl cp nextcloud/$(kubectl get pod -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].metadata.name}'):/tmp/nextcloud-data.tar.gz ./nextcloud-data-backup.tar.gz

# 2. Backup database
kubectl exec -n database deployment/postgres-lb -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql

# 3. Backup secrets
kubectl get secret nextcloud-secrets -n nextcloud -o yaml > nextcloud-secrets.yaml
```

### Recovery Process

```bash
# 1. Deploy fresh Nextcloud (creates PVC)
kubectl apply -k apps/nextcloud/base/

# 2. Restore database
kubectl cp nextcloud-db-backup.sql database/$(kubectl get pod -n database -l app=postgres-lb -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n database deployment/postgres-lb -- psql -U nextcloud -d nextcloud -f /tmp/nextcloud-db-backup.sql

# 3. Restore data files
kubectl cp nextcloud-data-backup.tar.gz nextcloud/$(kubectl get pod -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n nextcloud deployment/nextcloud -- tar xzf /tmp/nextcloud-data-backup.tar.gz -C /

# 4. Restart Nextcloud
kubectl rollout restart deployment/nextcloud -n nextcloud
```

## Security Considerations

### Change Default Admin Password

**CRITICAL**: Change admin password after first login:
```
Settings → Personal → Security → Change password
```

### Enable Two-Factor Authentication

```
Settings → Security → Two-factor authentication
```

Options:
- TOTP (Google Authenticator, Authy)
- WebAuthn (hardware keys)
- Backup codes

### Secure File Sharing

- Set expiration dates on shares
- Use password protection
- Review active shares regularly
- Disable public upload if not needed

### App-Specific Passwords

Create app passwords instead of using main password:
```
Settings → Security → Create new app password
```

Use for:
- Desktop sync clients
- Mobile apps
- DAV clients

## Resources and References

- **Application Documentation:** [docs/applications/nextcloud.md](../../../docs/applications/nextcloud.md)
- **Official Docs:** https://docs.nextcloud.com/
- **Admin Manual:** https://docs.nextcloud.com/server/stable/admin_manual/
- **Installation Scripts:**
  - Current: `apps/nextcloud/base/install.sh`
  - Original (dedicated DB): `docs/install_nextcloud.sh`
  - Fix script: `docs/fix_nextcloud_500.sh`
- **Kubernetes Manifests:** `apps/nextcloud/base/`
- **Shared PostgreSQL:** `infrastructure/databases/postgres/`

## Related Documentation

- [Main README](README.md) - Quick reference and operations
- [Application Documentation](../../../docs/applications/nextcloud.md) - User-facing docs
- [PostgreSQL Documentation](../../../docs/infrastructure/postgres.md) - Shared database configuration
- [Disaster Recovery](../../../docs/disaster-recovery.md) - Cluster rebuild procedures
- [Storage Documentation](../../../docs/infrastructure/storage.md) - PVC and storage class
- [Network Documentation](../../../docs/infrastructure/network.md) - Ingress and Cloudflare setup
