# Wallabag

Self-hosted read-it-later application for saving web articles.

**Status:** Production deployment on K3s (Raspberry Pi 4)
**Access:** https://bag.charn.io (external) | https://wallabag.local.charn.io (local)

## Quick Start

```bash
# Deploy Wallabag
bash apps/wallabag/base/install.sh

# Or manually
kubectl apply -k apps/wallabag/base/

# Monitor startup
kubectl logs -f -n wallabag -l app=wallabag
```

## Access URLs

- **External:** https://bag.charn.io (via Cloudflare Tunnel)
- **Local:** https://wallabag.local.charn.io (faster when at home)
- **NodePort:** http://192.168.0.23:30086 (testing only)

## Default Credentials

**⚠️ CHANGE IMMEDIATELY AFTER FIRST LOGIN!**

```
Username: wallabag
Password: wallabag
```

**First Login Steps:**
1. Access https://bag.charn.io
2. Login with wallabag/wallabag
3. Go to Config → User management
4. Change password immediately

## Storage

One PVC for article images:
- **Images:** 10Gi - Article images, user avatars, cached media
- **Database:** Shared PostgreSQL (postgres-lb.database.svc.cluster.local)
- **Cache:** Shared Redis (redis-lb.database.svc.cluster.local)

## Common Operations

```bash
# View logs
kubectl logs -f -n wallabag -l app=wallabag

# Check status
kubectl get pods,pvc,ingress -n wallabag

# Restart Wallabag
kubectl rollout restart -n wallabag deployment/wallabag

# Shell access
kubectl exec -it -n wallabag deployment/wallabag -- bash

# Check resource usage
kubectl top pod -n wallabag

# View events (troubleshooting)
kubectl get events -n wallabag --sort-by='.lastTimestamp'

# Clear cache
kubectl exec -it -n wallabag deployment/wallabag -- bin/console cache:clear --env=prod
```

## Browser Extensions

**Chrome/Chromium:**
- Install: [Wallabag v2 - Chrome Web Store](https://chrome.google.com/webstore)
- Configure: Server: https://bag.charn.io

**Firefox:**
- Install: [Wallabag - Firefox Add-ons](https://addons.mozilla.org/firefox/addon/wallabag-v2/)
- Configure: Server: https://bag.charn.io

**Safari:**
- Use bookmarklet from Config → Feeds

## Mobile Apps

- **Android:** "Wallabag" (Google Play)
- **iOS:** "Wallabag 2" (App Store)

Configuration:
- Server: https://bag.charn.io
- Username/Password: your credentials
- Features: Offline reading, sync, tags

## User Management

### Add New User (Admin Panel)
1. Login as admin
2. Go to Config → User management
3. Click "Create new user"

### Add New User (Console)
```bash
kubectl exec -it -n wallabag deployment/wallabag -- \
  bin/console fos:user:create username email@example.com password --super-admin
```

### Reset Password
```bash
kubectl exec -it -n wallabag deployment/wallabag -- \
  bin/console fos:user:change-password username newpassword
```

## Troubleshooting

### Assets Not Loading (Page Looks Broken)
Check domain configuration:
```bash
kubectl get deployment wallabag -n wallabag -o yaml | grep DOMAIN_NAME
# Should show: https://bag.charn.io
```

If wrong, update and restart:
```bash
kubectl edit deployment -n wallabag wallabag
# Set SYMFONY__ENV__DOMAIN_NAME: https://bag.charn.io
kubectl rollout restart -n wallabag deployment/wallabag
```

### Cannot Save Articles
Test internet access:
```bash
kubectl exec -it -n wallabag deployment/wallabag -- curl -I https://www.example.com
```

### Database Connection Issues
Check shared PostgreSQL is running:
```bash
kubectl get pods -n database -l app=postgres-lb
```

Verify database exists:
```bash
kubectl exec -it -n database deployment/postgres-lb -- psql -U postgres -c "\l" | grep wallabag
```

## API Access

**Generate API Credentials:**
1. Login to https://bag.charn.io
2. Config → API clients management
3. Create new client
4. Note Client ID and Secret

**API Documentation:** https://bag.charn.io/api/doc

## Backup

```bash
# Backup database (critical)
kubectl exec -n database deployment/postgres-lb -- \
  pg_dump -U postgres wallabag | gzip > wallabag-db-$(date +%Y%m%d).sql.gz

# Backup images
POD=$(kubectl get pod -n wallabag -l app=wallabag -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n wallabag $POD -- tar czf /tmp/images-backup.tar.gz -C /var/www/wallabag/web/assets/images .
kubectl cp wallabag/$POD:/tmp/images-backup.tar.gz ./wallabag-images-$(date +%Y%m%d).tar.gz

# Backup secrets
kubectl get secret wallabag-secrets -n wallabag -o yaml > wallabag-secrets-backup.yaml
```

## Resources

- **CPU:** 250m request, 1 core limit
- **Memory:** 256Mi request, 1Gi limit
- **Storage:** 10Gi images

## Dependencies

**Required Shared Services:**
- PostgreSQL: postgres-lb.database.svc.cluster.local:5432
- Redis: redis-lb.database.svc.cluster.local:6379

Deploy these first if not already running:
```bash
kubectl apply -k infrastructure/databases/postgres/
kubectl apply -k infrastructure/databases/redis/
```

## Documentation

- **Detailed Setup Guide:** [SETUP.md](SETUP.md)
- **Application Docs:** [../../docs/applications/wallabag.md](../../docs/applications/wallabag.md)
- **Official Docs:** https://doc.wallabag.org/
- **GitHub:** https://github.com/wallabag/wallabag

## Related

- **Installation Script:** [install.sh](install.sh) - Automated deployment with monitoring
- **Manifests:** All Kubernetes manifests in this directory
- **Kustomize:** [kustomization.yaml](kustomization.yaml)

## Security Notes

- **User registration disabled** (FOSUSER_REGISTRATION=false)
- **Change default password immediately** (wallabag/wallabag)
- **Use strong passwords** (20+ characters recommended)
- **Create separate users** for each person
- **API clients** should be unique per application