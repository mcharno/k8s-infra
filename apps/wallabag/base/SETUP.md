# Wallabag Setup Documentation

## Overview

Wallabag is a self-hosted read-it-later application that allows you to save web articles for offline reading. This deployment runs on K3s on a Raspberry Pi 4 (8GB RAM, 4 cores).

**Current Status:** Production deployment with external and local HTTPS access

## Deployment History

### Version 1: Standalone PostgreSQL and Redis (install_wallabag.sh)

**When:** Initial deployment
**Approach:** Dedicated PostgreSQL and Redis instances in wallabag namespace

**Configuration:**
```yaml
Components:
  - Wallabag application
  - Dedicated PostgreSQL 15 (128Mi-256Mi RAM)
  - Dedicated Redis 7 (64Mi-128Mi RAM)

Storage:
  - PostgreSQL data: 10Gi PVC
  - Wallabag images: 10Gi PVC

Service: NodePort 30086
Domain: http://<PI_IP>:30086
```

**Resource Usage:**
- Wallabag: 256Mi-1Gi RAM, 250m-1000m CPU
- PostgreSQL: 128Mi-256Mi RAM, 100m-500m CPU
- Redis: 64Mi-128Mi RAM, 50m-200m CPU
- **Total: ~448Mi-1.4Gi RAM minimum**

**Limitations:**
- High resource usage for small homelab
- Dedicated database instances for single app
- No external HTTPS access
- Domain configuration required manual setup

### Version 2: Current Shared Services Deployment

**When:** Migration to shared infrastructure
**What Changed:** Using shared PostgreSQL and Redis from database namespace

**Configuration:**
```yaml
Components:
  - Wallabag application only
  - Shared PostgreSQL (postgres-lb.database.svc.cluster.local)
  - Shared Redis (redis-lb.database.svc.cluster.local)

Ingress:
  External:
    - Host: bag.charn.io (shorter URL!)
    - TLS: Let's Encrypt via Cloudflare
    - Annotations:
      - force-ssl-redirect: "false" (Cloudflare sends HTTP)

  Local:
    - Host: wallabag.local.charn.io
    - TLS: Local wildcard certificate
    - Annotations:
      - force-ssl-redirect: "true"
      - ssl-protocols: "TLSv1.2 TLSv1.3"

Environment:
  SYMFONY__ENV__DOMAIN_NAME: https://bag.charn.io
  SYMFONY__ENV__DATABASE_HOST: postgres-lb.database.svc.cluster.local
  SYMFONY__ENV__REDIS_HOST: redis-lb.database.svc.cluster.local
  TRUSTED_PROXIES: 10.42.0.0/16,127.0.0.1
  FOSUSER_REGISTRATION: "false"
  FOSUSER_CONFIRMATION: "false"
```

**Why These Changes:**

1. **Shared Database Services:**
   - Saves ~192Mi RAM minimum (PostgreSQL + Redis dedicated instances)
   - Reduces pod count from 3 to 1
   - Simplifies resource management
   - Database already running for Nextcloud

2. **Domain Name Configuration:**
   - `SYMFONY__ENV__DOMAIN_NAME` must match external URL
   - Required for asset URLs (CSS, JS, images)
   - Without this, assets fail to load due to wrong domain
   - Uses shorter "bag.charn.io" instead of "wallabag.charn.io"

3. **Trusted Proxies:**
   - `TRUSTED_PROXIES=10.42.0.0/16` allows Nginx Ingress
   - Required for proper client IP detection
   - Enables correct forwarding through ingress

4. **User Registration Disabled:**
   - `FOSUSER_REGISTRATION=false` prevents open signups
   - `FOSUSER_CONFIRMATION=false` disables email confirmation
   - Security measure for self-hosted instance

**Benefits:**
- Reduced RAM usage (~448Mi → 256Mi for Wallabag only)
- Secure external access via HTTPS
- Fast local access when at home
- Professional setup with automatic certificates
- Shared infrastructure reduces complexity

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    External Access                          │
│                                                             │
│  Internet → Cloudflare Tunnel → HTTP → Nginx Ingress       │
│             (bag.charn.io)               ↓                  │
│                                          ↓                  │
│                    Local Access          ↓                  │
│                                          ↓                  │
│  Home Network → HTTPS → Nginx Ingress → Wallabag Pod       │
│  (wallabag.local.charn.io)               ↓                  │
│                                          ↓                  │
│                                    ┌─────────────┐          │
│                                    │  Wallabag   │          │
│                                    │  Container  │          │
│                                    │    :80      │          │
│                                    └─────────────┘          │
│                                          │                  │
│                     ┌────────────────────┼─────────────┐    │
│                     │                    │             │    │
│                ┌────▼────┐         ┌─────▼──┐    ┌─────▼──┐│
│                │ Images  │         │ PostgreSQL │ │ Redis  ││
│                │  PVC    │         │  (shared)  │ │(shared)││
│                │  10Gi   │         │  database  │ │  cache ││
│                └─────────┘         │  namespace │ │   ns   ││
│                                    └────────────┘ └────────┘│
│                                                             │
│          NodePort Backup: http://<PI_IP>:30086             │
└─────────────────────────────────────────────────────────────┘
```

## Storage Configuration

Wallabag uses one PVC for images:

### Images PVC (10Gi) - wallabag-images
- **Mount Point:** `/var/www/wallabag/web/assets/images`
- **Purpose:** Article images, user avatars, saved media
- **Contents:**
  - Downloaded article images
  - User profile pictures
  - Cached web assets
- **Backup Priority:** MEDIUM - Contains saved images from articles
- **Growth Rate:** Depends on articles saved and image retention

**Note:** Configuration and database are stored in the shared PostgreSQL database, not in local PVCs.

## Database Configuration

Wallabag uses the shared PostgreSQL database in the `database` namespace:

### Database Setup

1. **Create Database and User** (manual step during install):
   ```sql
   CREATE DATABASE wallabag;
   CREATE USER wallabag WITH PASSWORD 'your-password-here';
   GRANT ALL PRIVILEGES ON DATABASE wallabag TO wallabag;
   ```

2. **Database Tables:**
   - Wallabag automatically creates ~30 tables on first run
   - Includes users, entries, tags, annotations, config
   - Migrations run automatically on startup

3. **Connection Details:**
   ```yaml
   Host: postgres-lb.database.svc.cluster.local
   Port: 5432
   Database: wallabag
   User: wallabag
   Password: (from wallabag-secrets)
   ```

### Redis Configuration

Wallabag uses the shared Redis instance for:
- Session storage
- Queue processing for async tasks
- Cache for fetched articles

```yaml
Host: redis-lb.database.svc.cluster.local
Port: 6379
No authentication required (internal cluster only)
```

## Application Configuration

### Default Credentials

**CRITICAL SECURITY NOTICE:**
Wallabag ships with default credentials that MUST be changed immediately:

```
Username: wallabag
Password: wallabag
```

**First login checklist:**
1. Access https://bag.charn.io
2. Login with wallabag/wallabag
3. Go to Config → User management
4. Change password immediately
5. Create additional users if needed
6. Verify registration is disabled

### Environment Variables

```yaml
# Database (shared PostgreSQL)
SYMFONY__ENV__DATABASE_DRIVER: pdo_pgsql
SYMFONY__ENV__DATABASE_HOST: postgres-lb.database.svc.cluster.local
SYMFONY__ENV__DATABASE_PORT: "5432"
SYMFONY__ENV__DATABASE_NAME: wallabag
SYMFONY__ENV__DATABASE_USER: wallabag
SYMFONY__ENV__DATABASE_PASSWORD: (from secret)

# Redis (shared cache)
SYMFONY__ENV__REDIS_HOST: redis-lb.database.svc.cluster.local
SYMFONY__ENV__REDIS_PORT: "6379"

# Application
SYMFONY__ENV__SECRET: (from secret - used for encryption)
SYMFONY__ENV__DOMAIN_NAME: https://bag.charn.io
  # CRITICAL: Must match external URL for assets to load correctly
SYMFONY__ENV__SERVER_NAME: Wallabag
  # Display name shown in UI
APP_ENV: prod
  # Production mode (not dev/test)

# Proxy configuration
TRUSTED_PROXIES: 10.42.0.0/16,127.0.0.1
  # Allows Nginx Ingress to forward requests properly

# User management
SYMFONY__ENV__FOSUSER_REGISTRATION: "false"
  # Disables open registration (security)
SYMFONY__ENV__FOSUSER_CONFIRMATION: "false"
  # No email confirmation required

# Database initialization
POPULATE_DATABASE: "false"
  # Don't populate with demo data

# Legacy compatibility
POSTGRES_HOST: postgres-lb.database.svc.cluster.local
POSTGRES_PORT: "5432"
```

### Resource Limits

```yaml
resources:
  requests:
    cpu: 250m        # Minimum: 0.25 cores
    memory: 256Mi    # Minimum: 256MB
  limits:
    cpu: "1"         # Maximum: 1 core (25% of Pi)
    memory: 1Gi      # Maximum: 1GB (12.5% of Pi)
```

**Why These Values:**
- **Requests:** Baseline for normal operation
- **Limits:** Prevent runaway processes
- **CPU:** Article fetching is CPU-intensive
- **Memory:** Symfony framework + article processing

### Health Probes

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 120    # 2 minutes to start
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 60     # 1 minute for readiness
  periodSeconds: 5
  failureThreshold: 3
```

**Why These Settings:**
- Wallabag startup: ~60-90 seconds (database migrations, cache warmup)
- Liveness: 120s delay ensures migrations complete
- Readiness: 60s allows basic functionality to initialize

## Troubleshooting

### Pod Stuck in Pending

**Symptoms:**
```bash
$ kubectl get pods -n wallabag
NAME                        READY   STATUS    RESTARTS   AGE
wallabag-5f9c8d7b6c-xyz     0/1     Pending   0          5m
```

**Causes:**

1. **PVC Not Bound:**
   ```bash
   kubectl get pvc -n wallabag
   # If STATUS is "Pending", PVC is waiting
   ```
   - **Solution:** This is normal with WaitForFirstConsumer. PVC binds when pod schedules.

2. **Insufficient Storage:**
   ```bash
   df -h /var/lib/rancher/k3s/storage
   ```
   - **Solution:** Free up space

3. **Shared Services Not Running:**
   ```bash
   kubectl get pods -n database
   # Check postgres-lb and redis-lb are Running
   ```
   - **Solution:** Deploy shared PostgreSQL and Redis first

### Pod Crashes (CrashLoopBackOff)

**Check Logs:**
```bash
kubectl logs -n wallabag -l app=wallabag --tail=100
```

**Common Issues:**

1. **Database Connection Failed:**
   ```
   SQLSTATE[08006] [7] could not connect to server
   ```
   - **Cause:** PostgreSQL not running or database not created
   - **Solution:**
     ```bash
     # Check PostgreSQL
     kubectl get pods -n database -l app=postgres-lb

     # Connect and create database
     kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres
     CREATE DATABASE wallabag;
     CREATE USER wallabag WITH PASSWORD 'password';
     GRANT ALL PRIVILEGES ON DATABASE wallabag TO wallabag;
     ```

2. **Permission Denied Writing to Images:**
   ```
   Unable to write to /var/www/wallabag/web/assets/images
   ```
   - **Cause:** PVC permissions incorrect
   - **Solution:**
     ```bash
     # SSH to Pi
     PVC_PATH=$(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.name=="wallabag-images")].spec.local.path}')
     sudo chown -R 1000:1000 $PVC_PATH
     ```

3. **Secret Missing:**
   ```
   Environment variable SYMFONY__ENV__SECRET not set
   ```
   - **Cause:** wallabag-secrets not created
   - **Solution:**
     ```bash
     SECRET=$(openssl rand -hex 32)
     DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
     kubectl create secret generic wallabag-secrets -n wallabag \
       --from-literal=db-password="$DB_PASSWORD" \
       --from-literal=secret="$SECRET"
     ```

### Assets Not Loading (CSS/JS Missing)

**Symptoms:** Page loads but looks broken, no styling

**Diagnosis:**
```bash
# Check page source
curl -s https://bag.charn.io | grep -E "<link|<script"

# Asset URLs should show: https://bag.charn.io/bundles/...
# NOT: http://localhost or http://192.168.0.23
```

**Cause:** `SYMFONY__ENV__DOMAIN_NAME` not set correctly

**Solution:**
```bash
# Update deployment
kubectl edit deployment -n wallabag wallabag

# Set:
- name: SYMFONY__ENV__DOMAIN_NAME
  value: https://bag.charn.io

# Restart
kubectl rollout restart -n wallabag deployment/wallabag
```

### Cannot Login / Session Issues

**Symptoms:** Login form doesn't work, session expires immediately

**Causes:**

1. **Redis Not Connected:**
   ```bash
   kubectl exec -it -n wallabag deployment/wallabag -- wget -O- http://redis-lb.database.svc.cluster.local:6379
   # Should connect (will show Redis protocol output)
   ```
   - **Solution:** Ensure shared Redis is running

2. **Cookie Domain Mismatch:**
   - Check you're accessing via correct domain (bag.charn.io)
   - Not via IP or localhost

3. **Trusted Proxies Not Set:**
   ```bash
   kubectl get deployment wallabag -n wallabag -o yaml | grep TRUSTED_PROXIES
   # Should show: 10.42.0.0/16,127.0.0.1
   ```

### Article Fetching Fails

**Symptoms:** "Unable to fetch content" when saving articles

**Diagnosis:**
```bash
# Test internet access from pod
kubectl exec -it -n wallabag deployment/wallabag -- curl -I https://www.example.com
```

**Common Issues:**

1. **No Internet Access:**
   - Check firewall rules
   - Verify DNS resolution

2. **Site Blocks Wallabag:**
   - Some sites block scrapers
   - Try different article URL
   - Check Wallabag logs for specific error

3. **Memory Limit:**
   - Article fetching can use significant RAM
   - Check pod memory: `kubectl top pod -n wallabag`
   - Increase limits if near 1Gi

## Browser Extensions and Mobile Apps

### Browser Extensions

**Chrome/Chromium:**
1. Install from Chrome Web Store: "Wallabag v2"
2. Configure:
   - Wallabag URL: https://bag.charn.io
   - Username: your-username
   - Password: your-password
3. Click extension icon to save current page

**Firefox:**
1. Install from Firefox Add-ons: "Wallabag"
2. Configure same as Chrome

**Safari:**
1. No official extension
2. Use bookmarklet from Config → Feeds

### Mobile Apps

**Android:**
- App: "Wallabag" (Google Play)
- Configuration:
  - Server: https://bag.charn.io
  - Username/Password: your credentials
  - Features: Offline reading, article sync, tags

**iOS:**
- App: "Wallabag 2" (App Store)
- Configuration same as Android
- Features: Share extension, offline sync

### API Access

**Generate API Credentials:**
1. Login to https://bag.charn.io
2. Go to Config → API clients management
3. Create new client
4. Note Client ID and Client Secret
5. Use for programmatic access

**API Documentation:**
- URL: https://bag.charn.io/api/doc
- Format: REST API with OAuth2
- Endpoints: Create entry, retrieve entries, tags, annotations

## Backup and Recovery

### What to Backup

**Critical (Must Backup):**
1. **PostgreSQL Database:**
   - All articles, tags, annotations, users
   - Backup the wallabag database in shared PostgreSQL

**Important (Should Backup):**
2. **wallabag-secrets:**
   - DB password and encryption secret
   ```bash
   kubectl get secret wallabag-secrets -n wallabag -o yaml > wallabag-secrets-backup.yaml
   ```

3. **Images PVC:**
   - Article images and media
   - Can be regenerated by re-fetching articles (tedious)

### Backup Methods

**Method 1: Database Backup via PostgreSQL**
```bash
# Backup wallabag database
kubectl exec -n database deployment/postgres-lb -- \
  pg_dump -U postgres wallabag | gzip > wallabag-db-$(date +%Y%m%d).sql.gz

# Restore database
gunzip < wallabag-db-20250101.sql.gz | \
  kubectl exec -i -n database deployment/postgres-lb -- \
  psql -U postgres wallabag
```

**Method 2: Images PVC Backup**
```bash
# Backup images
kubectl exec -n wallabag deployment/wallabag -- \
  tar czf /tmp/images-backup.tar.gz -C /var/www/wallabag/web/assets/images .
kubectl cp wallabag/<pod-name>:/tmp/images-backup.tar.gz ./wallabag-images-$(date +%Y%m%d).tar.gz

# Restore images
kubectl cp ./wallabag-images-20250101.tar.gz wallabag/<pod-name>:/tmp/
kubectl exec -n wallabag deployment/wallabag -- \
  tar xzf /tmp/images-backup.tar.gz -C /var/www/wallabag/web/assets/images
```

**Method 3: Complete Backup Script**
```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/backup/wallabag"

# 1. Backup database
kubectl exec -n database deployment/postgres-lb -- \
  pg_dump -U postgres wallabag | gzip > $BACKUP_DIR/db-$DATE.sql.gz

# 2. Backup secrets
kubectl get secret wallabag-secrets -n wallabag -o yaml > $BACKUP_DIR/secrets-$DATE.yaml

# 3. Backup images PVC
POD=$(kubectl get pod -n wallabag -l app=wallabag -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n wallabag $POD -- \
  tar czf /tmp/images-$DATE.tar.gz -C /var/www/wallabag/web/assets/images .
kubectl cp wallabag/$POD:/tmp/images-$DATE.tar.gz $BACKUP_DIR/images-$DATE.tar.gz

echo "Backup complete: $BACKUP_DIR"
```

## Monitoring

### Resource Usage
```bash
# Pod resources
kubectl top pod -n wallabag

# Storage usage
kubectl exec -n wallabag deployment/wallabag -- df -h /var/www/wallabag/web/assets/images

# Database size
kubectl exec -n database deployment/postgres-lb -- \
  psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('wallabag'));"
```

### Application Logs
```bash
# Recent logs
kubectl logs -n wallabag -l app=wallabag --tail=100

# Follow logs
kubectl logs -f -n wallabag -l app=wallabag

# Filter for errors
kubectl logs -n wallabag -l app=wallabag | grep -i error
```

### Database Statistics
```bash
# Number of saved articles
kubectl exec -n database deployment/postgres-lb -- \
  psql -U postgres wallabag -c "SELECT COUNT(*) FROM wallabag_entry;"

# Number of users
kubectl exec -n database deployment/postgres-lb -- \
  psql -U postgres wallabag -c "SELECT COUNT(*) FROM wallabag_user;"
```

## Common Operations

### Restart Wallabag
```bash
kubectl rollout restart -n wallabag deployment/wallabag
```

### View Logs
```bash
kubectl logs -f -n wallabag -l app=wallabag
```

### Shell Access
```bash
kubectl exec -it -n wallabag deployment/wallabag -- bash

# Inside pod
cd /var/www/wallabag
ls -la web/assets/images
```

### Clear Cache
```bash
kubectl exec -it -n wallabag deployment/wallabag -- \
  bin/console cache:clear --env=prod
```

### Update Image
```bash
# Edit deployment to change image tag
kubectl edit deployment -n wallabag wallabag

# Or use kubectl set image
kubectl set image deployment/wallabag wallabag=wallabag/wallabag:2.6.9 -n wallabag

# Check rollout
kubectl rollout status deployment/wallabag -n wallabag
```

### Add New User (Console)
```bash
kubectl exec -it -n wallabag deployment/wallabag -- \
  bin/console fos:user:create newuser email@example.com password --super-admin
```

### Reset User Password
```bash
kubectl exec -it -n wallabag deployment/wallabag -- \
  bin/console fos:user:change-password username newpassword
```

## Security Considerations

### Default Credentials
- **CRITICAL:** Change default wallabag/wallabag immediately
- Use strong passwords (20+ characters)
- Create separate accounts for each user

### User Registration
- Disabled by default (`FOSUSER_REGISTRATION=false`)
- Only admins can create users
- Prevents unauthorized access

### Network Access
- External: Secured via Cloudflare Tunnel + TLS
- Local: Direct HTTPS with TLS certificate
- NodePort: HTTP only, use for testing only
- No public database or Redis ports

### API Security
- OAuth2 authentication required
- Create separate API clients per application
- Revoke unused API clients regularly

### Data Privacy
- All articles stored on your server
- Article fetching uses your IP
- No telemetry sent to Wallabag developers (open source)

## Lessons Learned

### 1. Shared Services Save Resources
- **Mistake:** Initially deployed dedicated PostgreSQL + Redis per app
- **Learning:** Shared services save 192Mi+ RAM per app
- **Recommendation:** Use shared database/cache infrastructure

### 2. Domain Configuration is Critical
- **Issue:** Assets didn't load, page looked broken
- **Cause:** `SYMFONY__ENV__DOMAIN_NAME` was http://localhost
- **Solution:** Set to actual external URL (https://bag.charn.io)
- **Impact:** Without correct domain, Wallabag unusable

### 3. Shorter Domain Name is Better
- **Decision:** Use "bag.charn.io" instead of "wallabag.charn.io"
- **Benefit:** Easier to type, remember, share
- **Note:** Wallabag still works fine with shorter domain

### 4. Disable User Registration by Default
- **Security:** Open registration = security risk
- **Solution:** `FOSUSER_REGISTRATION=false` in deployment
- **Alternative:** Create users via admin panel or console

### 5. Trusted Proxies Required for Ingress
- **Issue:** Client IPs showed as ingress controller IP
- **Solution:** Set `TRUSTED_PROXIES=10.42.0.0/16`
- **Impact:** Proper logging, security features work correctly

### 6. Health Probes Need Adequate Delays
- **Issue:** Pod restarted during database migrations
- **Solution:** 120s liveness delay, 60s readiness delay
- **Reason:** Migrations can take 1-2 minutes on first run

### 7. Database Migrations are Automatic
- **Benefit:** No manual migration steps needed
- **Caution:** First startup takes 2-3 minutes
- **Note:** Subsequent starts are much faster (~30 seconds)

## Next Steps

### Short Term
- [ ] Configure automatic article cleanup (old/read articles)
- [ ] Set up scheduled database backups
- [ ] Configure RSS feed generation for saved articles
- [ ] Add monitoring dashboard

### Long Term
- [ ] Implement automated backup to external storage
- [ ] Configure article sharing features
- [ ] Set up fail2ban for login protection
- [ ] Explore Wallabag plugins/extensions

## References

- **Wallabag Documentation:** https://doc.wallabag.org/
- **Wallabag GitHub:** https://github.com/wallabag/wallabag
- **Docker Image:** https://hub.docker.com/r/wallabag/wallabag
- **Browser Extensions:** https://addons.mozilla.org/firefox/addon/wallabag-v2/
- **Mobile Apps:**
  - Android: https://play.google.com/store/apps/details?id=fr.gaulupeau.apps.InThePoche
  - iOS: https://apps.apple.com/app/wallabag-2/id1170800946
- **API Documentation:** https://app.wallabag.it/api/doc (example instance)

## Support

For issues specific to this deployment:
- Check logs: `kubectl logs -n wallabag -l app=wallabag`
- Review events: `kubectl get events -n wallabag`
- See troubleshooting section above

For Wallabag application issues:
- Documentation: https://doc.wallabag.org/
- GitHub Issues: https://github.com/wallabag/wallabag/issues
- Community Support: https://github.com/wallabag/wallabag/discussions
