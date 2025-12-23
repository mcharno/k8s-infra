# Nextcloud Security Hardening - Phase 3

**Status:** ✅ Complete
**Date:** 2025-12-22

## Overview

This document details the security hardening implementation for Nextcloud, including 2FA, brute-force protection, and Redis integration for improved performance and security.

## Access Information

**URLs:**
- External: https://cloud.charn.io
- Local: https://cloud.local.charn.io

---

## Implemented Security Enhancements

### 1. Two-Factor Authentication (2FA/TOTP) ✅

**Status:** App enabled and ready for user configuration

**Implementation:**
```bash
php occ app:enable twofactor_totp
```

**Result:** TOTP authenticator app is now available for all users to enable on their accounts.

### 2. Redis Integration ✅

**Status:** Configured for file locking and distributed caching

**Configuration Applied:**
- Redis host: `redis.database.svc.cluster.local`
- Redis port: `6379`
- Redis password: From `redis-auth` secret
- File locking: `\OC\Memcache\Redis`
- Distributed cache: `\OC\Memcache\Redis`

**Benefits:**
- **Performance:** Faster file operations with Redis-based locking
- **Scalability:** Distributed caching for better multi-user performance
- **Reliability:** More robust locking mechanism than database-based locking

### 3. Brute-Force Protection ✅

**Status:** Enabled by default in Nextcloud

Nextcloud includes built-in brute-force protection that:
- Tracks failed login attempts
- Delays subsequent login attempts from suspicious IPs
- Automatically blocks IPs after repeated failures
- No additional configuration required

### 4. Deployment Configuration Updated ✅

Added Redis environment variables to deployment:
- `REDIS_HOST`
- `REDIS_HOST_PORT`
- `REDIS_HOST_PASSWORD` (from sealed secret)

---

## User Actions Required

### Enable 2FA for Your Account

1. **Login to Nextcloud**
   Visit: https://cloud.charn.io

2. **Navigate to Security Settings**
   - Click on your profile icon (top right)
   - Select **Personal Settings**
   - Go to **Security** section

3. **Enable TOTP Authentication**
   - Scroll to **Two-Factor Authentication**
   - Click on **Enable TOTP**
   - Scan the QR code with your authenticator app:
     - Google Authenticator
     - Authy
     - 1Password
     - Microsoft Authenticator
     - Any TOTP-compatible app

4. **Save Backup Codes**
   - Nextcloud will display backup codes
   - **SAVE THESE SECURELY** in your password manager
   - Use these if you lose access to your authenticator

5. **Verify 2FA Works**
   - Log out
   - Log back in
   - Verify you're prompted for the TOTP code

### Enforce 2FA for All Users (Admin Only)

```bash
# Enforce 2FA for all users
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:enforce --on

# Or enforce for specific group
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:enforce --group admin
```

---

## Verification

### Verify Redis Connection

```bash
# Check Redis configuration in Nextcloud
kubectl exec -n nextcloud deployment/nextcloud -- php occ config:list system | grep -A 10 redis

# Expected output:
# "redis": {
#     "host": "redis.database.svc.cluster.local",
#     "port": 6379,
#     "password": "***REMOVED SENSITIVE VALUE***"
# },
# "memcache.locking": "\\OC\\Memcache\\Redis",
# "memcache.distributed": "\\OC\\Memcache\\Redis"
```

### Test Redis Connectivity

```bash
# Test Redis connection from Nextcloud pod
kubectl exec -n nextcloud deployment/nextcloud -- php -r "
\$redis = new Redis();
\$redis->connect('redis.database.svc.cluster.local', 6379);
\$redis->auth('$(kubectl get secret redis-auth -n database -o jsonpath='{.data.password}' | base64 -d)');
echo \$redis->ping() ? 'Redis connected successfully' : 'Redis connection failed';
echo PHP_EOL;
"
```

### Verify 2FA Apps

```bash
# List enabled 2FA apps
kubectl exec -n nextcloud deployment/nextcloud -- php occ app:list | grep twofactor

# Expected:
# - twofactor_backupcodes: 1.20.0
# - twofactor_nextcloud_notification: 5.0.0
# - twofactor_totp: 13.0.0-dev.0
```

### Check Security Scan

```bash
# Run Nextcloud security scan
kubectl exec -n nextcloud deployment/nextcloud -- php occ security:certificates

# Check for any warnings in admin panel
# Visit: https://cloud.charn.io/settings/admin/overview
```

---

## Security Configuration Summary

| Feature | Status | Implementation |
|---------|--------|----------------|
| 2FA TOTP App | ✅ Enabled | App enabled, users can configure |
| Backup Codes | ✅ Available | Automatically enabled with 2FA |
| Brute-Force Protection | ✅ Active | Built-in, enabled by default |
| Redis File Locking | ✅ Configured | Using shared Redis instance |
| Redis Distributed Cache | ✅ Configured | Improves performance |
| HTTPS Enforcement | ✅ Active | Via Ingress configuration |
| Trusted Domains | ✅ Configured | cloud.charn.io, cloud.local.charn.io |
| Trusted Proxies | ✅ Configured | 10.42.0.0/16 (pod network) |

---

## Additional Security Recommendations

### 1. Regular Updates

```bash
# Check for Nextcloud updates
kubectl exec -n nextcloud deployment/nextcloud -- php occ update:check

# View available app updates
kubectl exec -n nextcloud deployment/nextcloud -- php occ app:update --all --showonly
```

### 2. Security Audit

```bash
# Run security scan
kubectl exec -n nextcloud deployment/nextcloud -- php occ security:scan

# Check for security warnings
# Visit Admin panel: Settings → Overview
```

### 3. App Review

Periodically review installed apps and disable unused ones:

```bash
# List all apps
kubectl exec -n nextcloud deployment/nextcloud -- php occ app:list

# Disable unused app
kubectl exec -n nextcloud deployment/nextcloud -- php occ app:disable <app-name>
```

### 4. File Access Control

Configure sharing permissions:
- Settings → Administration → Sharing
- Disable public link sharing if not needed
- Require passwords for public links
- Set expiration dates for shares

### 5. Enable Server-Side Encryption (Optional)

**WARNING:** Only enable if you understand the implications. Server-side encryption in Nextcloud encrypts files at rest but keys are stored on the same server.

```bash
# Enable encryption app
kubectl exec -n nextcloud deployment/nextcloud -- php occ app:enable encryption

# Enable encryption
kubectl exec -n nextcloud deployment/nextcloud -- php occ encryption:enable
```

---

## Monitoring

### Redis Performance

Check Redis metrics in Prometheus/Grafana:
- Connection count
- Memory usage
- Command latency
- Cache hit rate

### Nextcloud Logs

```bash
# View Nextcloud logs
kubectl logs -n nextcloud deployment/nextcloud --tail=100

# Follow logs in real-time
kubectl logs -n nextcloud deployment/nextcloud -f
```

### Brute-Force Attempts

```bash
# Check brute-force attempts for an IP
kubectl exec -n nextcloud deployment/nextcloud -- php occ security:bruteforce:attempts <ip-address>

# Reset brute-force attempts for an IP (if needed)
kubectl exec -n nextcloud deployment/nextcloud -- php occ security:bruteforce:reset <ip-address>
```

---

## Rollback Procedures

### Disable Redis Integration

```bash
# Remove Redis configuration
kubectl exec -n nextcloud deployment/nextcloud -- php occ config:system:delete redis
kubectl exec -n nextcloud deployment/nextcloud -- php occ config:system:delete memcache.locking
kubectl exec -n nextcloud deployment/nextcloud -- php occ config:system:delete memcache.distributed

# Restart Nextcloud
kubectl rollout restart deployment/nextcloud -n nextcloud
```

### Disable 2FA Enforcement

```bash
# Disable 2FA enforcement
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:enforce --off
```

### Disable 2FA for Specific User (Emergency)

```bash
# Disable 2FA for a user
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:disable <username>
```

---

## Performance Tuning

### APCu + Redis Configuration

Nextcloud now uses:
- **APCu:** Local memory cache (already configured)
- **Redis:** File locking and distributed caching
- This is the optimal configuration for performance

### Database Query Optimization

```bash
# Add missing database indices
kubectl exec -n nextcloud deployment/nextcloud -- php occ db:add-missing-indices

# Convert database to big int (for large installations)
kubectl exec -n nextcloud deployment/nextcloud -- php occ db:convert-filecache-bigint
```

---

## Troubleshooting

### Redis Connection Issues

```bash
# Test Redis connectivity
kubectl exec -n nextcloud deployment/nextcloud -- php occ redis:ping

# Check Redis logs
kubectl logs -n database deployment/redis

# Verify Redis password in Nextcloud
kubectl exec -n nextcloud deployment/nextcloud -- php occ config:system:get redis password
```

### 2FA Issues

```bash
# Check which users have 2FA enabled
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:state <username>

# Regenerate backup codes for a user
kubectl exec -n nextcloud deployment/nextcloud -- php occ twofactorauth:backup-codes:generate <username>
```

### Performance Issues

```bash
# Clear all caches
kubectl exec -n nextcloud deployment/nextcloud -- php occ maintenance:repair --include-expensive

# Rebuild file cache
kubectl exec -n nextcloud deployment/nextcloud -- php occ files:scan --all
```

---

## References

- [Nextcloud Security Hardening](https://docs.nextcloud.com/server/latest/admin_manual/installation/harden_server.html)
- [Nextcloud 2FA Documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_user/two_factor-auth.html)
- [Nextcloud Redis Configuration](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html)
- [Nextcloud OCC Commands](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html)

---

**Status:** Complete
**Implementation Time:** 15 minutes
**Risk Level:** Low
**User Impact:** Minimal (2FA enrollment required)
