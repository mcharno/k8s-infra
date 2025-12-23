# Application Security Hardening - Task 1.2.4

**Status:** 🔄 In Progress
**Date Started:** 2025-12-22

## Overview

This document provides implementation steps for hardening application-level security across all deployed applications in the homelab cluster.

## Security Assessment Summary

### Current State

| Application | Current Issues | Priority |
|-------------|---------------|----------|
| **Grafana** | ❌ Default admin password ("admin") in plaintext | **CRITICAL** |
| **Home Assistant** | ⚠️ No MFA/2FA configured | High |
| **Nextcloud** | ⚠️ No 2FA enforcement, no brute-force protection visible | High |
| **n8n** | ⚠️ User management enabled but auth details unclear | Medium |
| **Jellyfin** | ⚠️ No specific hardening, DLNA may be enabled | Medium |

### Security Gaps Identified

1. **Grafana**: Default credentials hardcoded in deployment (CRITICAL)
2. **All Apps**: Missing security context hardening
3. **Home Assistant**: No MFA enforcement
4. **Nextcloud**: Missing brute-force protection configuration
5. **n8n**: Webhook security unclear
6. **Jellyfin**: Permissions and features not reviewed

---

## Implementation Plan

### Phase 1: Grafana Critical Security Fix (IMMEDIATE)

**Impact:** Critical
**Effort:** Low
**Risk:** Low

#### Issue
Grafana deployment has hardcoded default admin password `admin` in plaintext in the deployment manifest. This is a **critical security vulnerability**.

#### Step 1: Create Grafana Admin Password Secret

```bash
cd /Users/charno/projects/homelab/infra-k8s

# Generate strong password
GRAFANA_PASSWORD=$(openssl rand -base64 32)
echo "Generated password: $GRAFANA_PASSWORD"
# Save this password securely!

# Create secret
kubectl create secret generic grafana-admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --namespace=monitoring \
  --dry-run=client -o yaml > /tmp/grafana-admin-secret.yaml

# Seal it
kubeseal --format yaml \
  --cert=infrastructure/security/sealed-secrets/pub-cert.pem \
  < /tmp/grafana-admin-secret.yaml \
  > apps/grafana/base/grafana-admin-sealed-secret.yaml

# Clean up
rm /tmp/grafana-admin-secret.yaml
```

#### Step 2: Update Grafana Deployment

Update `apps/grafana/base/deployment.yaml`:

```yaml
env:
- name: GF_SECURITY_ADMIN_USER
  value: admin
- name: GF_SECURITY_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: grafana-admin
      key: admin-password
# Add additional security settings
- name: GF_USERS_ALLOW_SIGN_UP
  value: "false"
- name: GF_AUTH_ANONYMOUS_ENABLED
  value: "false"
- name: GF_AUTH_DISABLE_LOGIN_FORM
  value: "false"
- name: GF_SECURITY_DISABLE_GRAVATAR
  value: "true"
- name: GF_SNAPSHOTS_EXTERNAL_ENABLED
  value: "false"
- name: GF_SECURITY_COOKIE_SECURE
  value: "true"
- name: GF_SECURITY_COOKIE_SAMESITE
  value: "strict"
- name: GF_SECURITY_STRICT_TRANSPORT_SECURITY
  value: "true"
- name: GF_SECURITY_X_CONTENT_TYPE_OPTIONS
  value: "true"
- name: GF_SECURITY_X_XSS_PROTECTION
  value: "true"
```

#### Step 3: Apply Changes

```bash
# Apply sealed secret
kubectl apply -f apps/grafana/base/grafana-admin-sealed-secret.yaml

# Wait for secret to be created
kubectl get secret grafana-admin -n monitoring

# Apply updated deployment
kubectl apply -f apps/grafana/base/deployment.yaml

# Monitor rollout
kubectl rollout status deployment/grafana -n monitoring

# Get new admin password to login
echo $GRAFANA_PASSWORD
```

#### Step 4: Login and Change Password (Optional)

1. Visit https://grafana.charn.io
2. Login with:
   - Username: `admin`
   - Password: `<generated password from sealed secret>`
3. Change password via UI if desired
4. Update sealed secret with new password

---

### Phase 2: Home Assistant MFA Setup

**Impact:** High
**Effort:** Low
**Risk:** Low

#### Overview

Home Assistant MFA must be configured through the UI as it's a user-specific setting.

#### Step 1: Enable MFA for Admin User

1. Access Home Assistant: https://home.charn.io
2. Navigate to user profile (click on username in sidebar)
3. Scroll to **Multi-factor Authentication**
4. Click **Add** and select **Authenticator app (TOTP)**
5. Scan QR code with authenticator app (Google Authenticator, Authy, 1Password, etc.)
6. Enter verification code
7. Save backup codes securely

#### Step 2: Disable Unused Integrations

Review and disable/remove unused integrations:

```bash
# Access Home Assistant pod
kubectl exec -it -n homeassistant deployment/homeassistant -- /bin/bash

# Review configuration
cat /config/configuration.yaml

# Check integrations directory
ls -la /config/.storage/core.config_entries
```

**Recommended actions:**
- Disable **DLNA** if not used (Settings → Integrations → DLNA)
- Disable **SSDP** if not used
- Remove any cloud integrations not actively used
- Review and remove test/experimental integrations

#### Step 3: Configure Login Attempts Limit

Add to Home Assistant `configuration.yaml` (via ConfigMap or direct edit):

```yaml
homeassistant:
  auth_providers:
    - type: homeassistant
      # Limit failed login attempts
    - type: trusted_networks
      trusted_networks:
        - 10.42.0.0/16  # Pod network
        - 10.43.0.0/16  # Service network
      allow_bypass_login: false

recorder:
  # Limit data retention to reduce attack surface
  purge_keep_days: 7
  auto_purge: true
```

#### Step 4: Enable Prometheus Integration

Add Prometheus metrics for monitoring:

1. Navigate to Settings → Integrations
2. Add **Prometheus** integration
3. Configure to expose on default port
4. Create ServiceMonitor for Prometheus scraping

---

### Phase 3: Nextcloud Security Hardening

**Impact:** High
**Effort:** Medium
**Risk:** Medium

#### Step 1: Enable Two-Factor Authentication (2FA)

**Option A: Enable via OCC Command (Recommended)**

```bash
# Access Nextcloud pod
kubectl exec -it -n nextcloud deployment/nextcloud -- /bin/bash

# Enable 2FA TOTP app
php occ app:enable twofactor_totp

# Check status
php occ app:list | grep twofactor

# Enforce 2FA for specific groups (optional)
php occ twofactorauth:enforce --on
# OR for specific group:
# php occ group:adduser admin <your-username>
# php occ twofactorauth:enforce --group admin
```

**Option B: Enable via Web UI**

1. Access Nextcloud: https://cloud.charn.io
2. Navigate to Apps
3. Search for "Two-Factor TOTP Provider"
4. Enable the app
5. Go to Personal Settings → Security
6. Configure TOTP authenticator

#### Step 2: Configure Brute-Force Protection

Nextcloud has built-in brute-force protection. Verify it's active:

```bash
kubectl exec -it -n nextcloud deployment/nextcloud -- /bin/bash

# Check brute-force protection status
php occ config:system:get auth.bruteforce.protection.enabled
# Should return: true (enabled by default)

# Configure thresholds (optional)
php occ config:system:set auth.bruteforce.protection.testing --value=false

# View current settings
php occ config:list system
```

#### Step 3: Enable Redis for File Locking

Update `apps/nextcloud/base/deployment.yaml`:

```yaml
env:
# Add Redis configuration
- name: REDIS_HOST
  value: redis.database.svc.cluster.local
- name: REDIS_HOST_PORT
  value: "6379"
- name: REDIS_HOST_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-auth
      key: password
```

Then configure in Nextcloud:

```bash
kubectl exec -it -n nextcloud deployment/nextcloud -- /bin/bash

# Configure Redis for file locking
php occ config:system:set redis host --value="redis.database.svc.cluster.local"
php occ config:system:set redis port --value="6379"
php occ config:system:set redis password --value="<password from redis-auth secret>"
php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"
php occ config:system:set memcache.distributed --value="\OC\Memcache\Redis"
```

#### Step 4: Security Headers Configuration

Add to Nextcloud config.php (via ConfigMap or exec):

```bash
kubectl exec -it -n nextcloud deployment/nextcloud -- /bin/bash

# Edit config
php occ config:system:set overwriteprotocol --value="https"
php occ config:system:set overwrite.cli.url --value="https://cloud.charn.io"

# Additional security
php occ config:system:set htaccess.RewriteBase --value="/"
php occ config:system:set check_for_working_htaccess --value=true
```

#### Step 5: Verify Security Scan

```bash
# Run Nextcloud security scan
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ security:scan

# Check for security warnings
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ security:certificates
```

---

### Phase 4: n8n Webhook Security

**Impact:** Medium
**Effort:** Low
**Risk:** Low

#### Step 1: Verify User Management is Enabled

The deployment already has `N8N_USER_MANAGEMENT_DISABLED=false`, which is good.

#### Step 2: Configure Webhook Security

Add to `apps/n8n/base/deployment.yaml`:

```yaml
env:
# Webhook security settings
- name: N8N_PAYLOAD_SIZE_MAX
  value: "16"  # Max 16MB payload
- name: N8N_METRICS
  value: "true"  # Enable Prometheus metrics
- name: N8N_DIAGNOSTICS_ENABLED
  value: "false"  # Disable diagnostics for privacy
- name: N8N_HIRING_BANNER_ENABLED
  value: "false"
- name: N8N_PERSONALIZATION_ENABLED
  value: "false"  # Disable telemetry
```

#### Step 3: Create First User and Secure Access

1. Access n8n: https://auto.charn.io
2. Create admin user account
3. Enable 2FA in user settings
4. Review webhook workflows and add authentication where needed

#### Step 4: Configure Webhook Authentication

For workflows with webhooks:
1. Use **Authentication** header validation
2. Implement **API key** requirement
3. Use **HMAC signatures** for sensitive webhooks
4. Enable **IP whitelisting** if possible

Example webhook authentication in n8n:
- Add "HTTP Request" node after webhook
- Validate `Authorization` header
- Reject requests without valid token

---

### Phase 5: Jellyfin Security Review

**Impact:** Medium
**Effort:** Low
**Risk:** Low

#### Step 1: Disable DLNA (If Not Used)

```bash
# Access Jellyfin dashboard
# https://jellyfin.charn.io

# Navigate to: Dashboard → Networking
# Disable:
# - "Enable DLNA server" (if not using DLNA devices)
# - "Enable DLNA Play To" (if not needed)
# - "Public HTTPS port" (already using Ingress)
# - "Public HTTP port" (already using Ingress)
```

#### Step 2: Review Library Permissions

1. Navigate to **Dashboard → Users**
2. Review each user's library access
3. Apply **principle of least privilege**:
   - Only grant access to necessary libraries
   - Disable admin access for regular users
   - Enable parental controls if needed

#### Step 3: Configure Authentication

```bash
# Dashboard → Networking → Advanced
# Enable:
# - "Require authentication to access server" ✓
# - "Require HTTPS" ✓ (enforced by Ingress)

# Disable:
# - "Allow remote connections without authentication" ✗
```

#### Step 4: Enable Hardware Acceleration (Optional, for Performance)

Update `apps/jellyfin/base/deployment.yaml`:

```yaml
# Add device access for hardware transcoding on Raspberry Pi
securityContext:
  privileged: true  # Required for /dev/video* access
volumeMounts:
- name: video-devices
  mountPath: /dev/dri
  readOnly: false
volumes:
- name: video-devices
  hostPath:
    path: /dev/dri
    type: Directory
```

**Note:** Only add if you need transcoding and have GPU available.

---

## Security Context Hardening (All Applications)

### Recommended Security Context for All Pods

Add to each deployment's `spec.template.spec`:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

containers:
- name: <container-name>
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
    readOnlyRootFilesystem: false  # Set to true if app supports it
```

**Application-Specific Notes:**
- **Grafana**: Can run as non-root with UID/GID 472
- **Home Assistant**: Requires privileged access for some integrations (GPIO, USB devices)
- **Nextcloud**: Can run as www-data (UID 33) or create custom user
- **n8n**: Can run as node user (UID 1000)
- **Jellyfin**: May require privileged for hardware transcoding

---

## Verification Checklist

### Grafana
- [ ] Admin password changed from default
- [ ] Anonymous access disabled
- [ ] Sign-up disabled
- [ ] Security headers enabled
- [ ] HTTPS enforced via Ingress

### Home Assistant
- [ ] MFA enabled for admin user
- [ ] Unused integrations disabled
- [ ] Login attempt limits configured
- [ ] Prometheus integration enabled

### Nextcloud
- [ ] 2FA TOTP app installed and enabled
- [ ] Brute-force protection verified active
- [ ] Redis integration configured
- [ ] Security scan passed
- [ ] All users have 2FA enabled

### n8n
- [ ] User management enabled
- [ ] Admin user created with strong password
- [ ] 2FA enabled for admin
- [ ] Webhook authentication reviewed
- [ ] Metrics enabled

### Jellyfin
- [ ] DLNA disabled (if not used)
- [ ] Library permissions reviewed
- [ ] Authentication required
- [ ] Remote access secured
- [ ] Users have appropriate access levels

---

## Post-Implementation Testing

```bash
# Test Grafana login
curl -u admin:<password> https://grafana.charn.io/api/health

# Test Home Assistant (should redirect to login)
curl -I https://home.charn.io

# Test Nextcloud (should enforce auth)
curl -I https://cloud.charn.io/status.php

# Test n8n (should require auth)
curl -I https://auto.charn.io

# Test Jellyfin (should require auth)
curl -I https://jellyfin.charn.io/health
```

---

## Backup Reminders

Before making changes:
1. Backup persistent volumes for each app
2. Export configurations where possible
3. Document current admin credentials
4. Take screenshots of current settings

---

## Rollback Procedures

### Grafana Rollback
```bash
# Revert to old deployment
git checkout apps/grafana/base/deployment.yaml
kubectl apply -f apps/grafana/base/deployment.yaml

# Delete sealed secret
kubectl delete secret grafana-admin -n monitoring
```

### Home Assistant Rollback
- MFA can be disabled from user profile
- Integrations can be re-enabled from UI
- Configuration changes can be reverted in YAML

### Nextcloud Rollback
```bash
# Disable 2FA
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ app:disable twofactor_totp
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ twofactorauth:enforce --off

# Remove Redis config
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ config:system:delete redis
kubectl exec -it -n nextcloud deployment/nextcloud -- php occ config:system:delete memcache.locking
```

---

## Timeline

- **Phase 1 (Grafana)**: 15 minutes (IMMEDIATE)
- **Phase 2 (Home Assistant)**: 30 minutes
- **Phase 3 (Nextcloud)**: 45 minutes
- **Phase 4 (n8n)**: 20 minutes
- **Phase 5 (Jellyfin)**: 20 minutes

**Total Estimated Time**: 2-3 hours

---

## Success Metrics

- ✅ No default passwords in any deployment
- ✅ All admin accounts use MFA/2FA
- ✅ Brute-force protection active on all apps
- ✅ Security headers configured
- ✅ Unused features disabled
- ✅ All apps require authentication
- ✅ Security scans pass for all applications

---

**Status**: Ready for Implementation
**Next Step**: Start with Phase 1 (Grafana Critical Fix)
