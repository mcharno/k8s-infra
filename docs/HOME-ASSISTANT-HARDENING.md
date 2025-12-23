# Home Assistant Security Hardening - Phase 2

**Status:** 🔄 In Progress
**Date Started:** 2025-12-22

## Overview

This document provides step-by-step instructions for hardening Home Assistant security, including MFA setup, disabling unused integrations, and configuring security settings.

## Current Configuration

**Access URLs:**
- External: https://home.charn.io
- Local: https://homeassistant.local.charn.io

**Current State:**
- ✅ External/internal URL configured
- ✅ Trusted proxies configured (Ingress nginx)
- ✅ IP ban currently disabled
- ❌ MFA/2FA not enabled
- ⚠️ `default_config:` includes many integrations (may have unused ones)

---

## Phase 2: Home Assistant MFA & Security

### Step 1: Enable Multi-Factor Authentication (MFA)

**IMPORTANT:** MFA in Home Assistant is a per-user setting configured through the web UI. It cannot be configured via YAML.

#### Enable MFA for Admin User

1. **Access Home Assistant**
   Navigate to https://home.charn.io

2. **Go to User Profile**
   - Click on your username in the bottom-left sidebar
   - Or go to: Settings → People → Your User Account

3. **Enable Multi-Factor Authentication**
   - Scroll to **Multi-factor Authentication** section
   - Click **Add** or **Enable**
   - Select **Authenticator app (TOTP)**

4. **Scan QR Code**
   - Open your authenticator app:
     - Google Authenticator
     - Authy
     - 1Password
     - Microsoft Authenticator
     - Any TOTP-compatible app
   - Scan the QR code displayed
   - Enter the 6-digit verification code

5. **Save Backup Codes**
   - Home Assistant will display backup codes
   - **SAVE THESE SECURELY** (password manager, encrypted file)
   - You'll need these if you lose access to your authenticator app

6. **Test MFA**
   - Log out of Home Assistant
   - Log back in
   - Verify you're prompted for the TOTP code

#### Create Additional Users (Optional)

If you have multiple users accessing Home Assistant:

1. Go to Settings → People
2. Create separate user accounts (don't share admin)
3. Enable MFA for each user account
4. Assign appropriate permissions (admin vs regular user)

---

### Step 2: Enable IP Ban Protection

Currently `ip_ban_enabled: false` in configuration. Enable it to protect against brute-force attacks.

#### Update Configuration

```bash
# Access the pod
kubectl exec -it -n homeassistant deployment/homeassistant -- /bin/bash

# Edit configuration.yaml
vi /config/configuration.yaml
```

Update the `http:` section:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.42.0.0/16
    - 127.0.0.1
    - ::1
  ip_ban_enabled: true
  login_attempts_threshold: 5
```

**Configuration Details:**
- `ip_ban_enabled: true` - Enable IP banning
- `login_attempts_threshold: 5` - Ban IP after 5 failed attempts

#### Restart Home Assistant

```bash
# Restart the deployment
kubectl rollout restart deployment/homeassistant -n homeassistant

# Monitor restart
kubectl rollout status deployment/homeassistant -n homeassistant

# Check logs for any errors
kubectl logs -n homeassistant deployment/homeassistant --tail=50
```

---

### Step 3: Review and Disable Unused Integrations

The `default_config:` includes many integrations. Review and disable unused ones.

#### Check Active Integrations

1. **Via Web UI:**
   - Go to Settings → Devices & Services → Integrations
   - Review all active integrations
   - Remove or disable integrations you don't use

2. **Via Configuration:**
   ```bash
   kubectl exec -n homeassistant deployment/homeassistant -- cat /config/.storage/core.config_entries
   ```

#### Common Integrations to Review

**Potentially Unused (disable if not needed):**
- **DLNA** - Media streaming to DLNA devices
- **SSDP** - Service discovery
- **UPnP** - Universal Plug and Play
- **Zeroconf** - Network service discovery
- **Mobile App** - If not using HA mobile app
- **Cloud** - If not using Nabu Casa Cloud

**Keep Enabled (usually needed):**
- **HTTP** - Web interface
- **Lovelace** - Dashboard UI
- **Frontend** - User interface
- **History** - Historical data
- **Logbook** - Event logging
- **Recorder** - Database recording
- **Automation** - Automations
- **Person** - Person tracking
- **Zone** - Location zones

#### Disable Integrations via Configuration

To disable specific integrations from `default_config`, replace it with explicit includes:

```yaml
# Instead of:
# default_config:

# Use explicit configuration:
homeassistant:
  name: Home
  # ... other settings ...

# Core integrations (keep these)
frontend:
lovelace:
config:
http:
  # ... http config ...
history:
logbook:
recorder:
  purge_keep_days: 7
  auto_purge: true
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
person:
zone:
sun:
updater:
mobile_app:

# Disable cloud if not using Nabu Casa
# cloud:

# Disable DHCP/SSDP/Zeroconf if not needed
# dhcp:
# ssdp:
# zeroconf:
```

---

### Step 4: Configure Recorder Purge Settings

Limit data retention to reduce attack surface and improve performance.

Add or update in `configuration.yaml`:

```yaml
recorder:
  purge_keep_days: 7
  auto_purge: true
  commit_interval: 1
```

This keeps only 7 days of history and automatically purges old data.

---

### Step 5: Enable Prometheus Integration (for Monitoring)

Add metrics endpoint for Prometheus scraping:

#### Via Web UI (Recommended)

1. Go to Settings → Devices & Services → Integrations
2. Click **+ Add Integration**
3. Search for **Prometheus**
4. Click to add
5. Configure:
   - Port: 8123 (default HTTP port)
   - Namespace: `homeassistant`
   - No authentication needed (internal cluster only)

#### Create ServiceMonitor for Prometheus

Create file: `apps/homeassistant/base/servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: homeassistant
  namespace: homeassistant
  labels:
    app: homeassistant
spec:
  selector:
    matchLabels:
      app: homeassistant
  endpoints:
  - port: http
    path: /api/prometheus
    interval: 30s
```

Apply:
```bash
kubectl apply -f apps/homeassistant/base/servicemonitor.yaml
```

---

### Step 6: Review Trusted Networks Configuration

Currently trusting the entire pod network (`10.42.0.0/16`). This is fine for internal cluster access.

**Security Note:**
The `trusted_proxies` configuration allows Home Assistant to see the real client IP behind the ingress nginx proxy. This is required for IP banning to work correctly.

**Current configuration is secure:**
```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.42.0.0/16  # Pod network (nginx ingress)
    - 127.0.0.1
    - ::1
```

Do NOT add external IPs to trusted_proxies.

---

### Step 7: Verify HTTPS Enforcement

Check that both ingresses enforce HTTPS:

```bash
# Check external ingress
kubectl get ingress homeassistant-external -n homeassistant -o yaml | grep -A 2 annotations

# Check local ingress
kubectl get ingress homeassistant-local -n homeassistant -o yaml | grep -A 2 annotations
```

Ensure `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` is present.

---

## Security Checklist

After completing all steps:

- [ ] MFA enabled for admin user
- [ ] Backup codes saved securely
- [ ] IP ban protection enabled (`ip_ban_enabled: true`)
- [ ] Login attempts threshold configured
- [ ] Unused integrations disabled
- [ ] Recorder purge settings configured (7 days)
- [ ] Prometheus integration enabled
- [ ] ServiceMonitor created for metrics
- [ ] HTTPS enforcement verified on both ingresses
- [ ] Tested MFA login

---

## Testing

### Test MFA

1. Log out of Home Assistant
2. Log back in with username and password
3. Verify TOTP code is required
4. Enter code from authenticator app
5. Confirm successful login

### Test IP Ban

```bash
# Check IP ban list (should be empty initially)
kubectl exec -n homeassistant deployment/homeassistant -- cat /config/ip_bans.yaml

# After failed login attempts, banned IPs appear here
```

### Test Prometheus Metrics

```bash
# Test metrics endpoint
kubectl exec -n homeassistant deployment/homeassistant -- curl -s http://localhost:8123/api/prometheus | head -20

# Should see metrics like:
# homeassistant_sensor_temperature_c
# homeassistant_switch_state
# etc.
```

---

## Backup Important Files

Before making changes, backup:

```bash
# Backup configuration
kubectl exec -n homeassistant deployment/homeassistant -- tar -czf /tmp/ha-config-backup.tar.gz /config

# Copy backup to local machine
kubectl cp homeassistant/homeassistant-<pod-id>:/tmp/ha-config-backup.tar.gz ./ha-config-backup.tar.gz
```

---

## Rollback Procedures

### Revert Configuration Changes

```bash
# Restore configuration.yaml from backup
kubectl cp ./configuration.yaml.backup homeassistant/homeassistant-<pod-id>:/config/configuration.yaml

# Restart Home Assistant
kubectl rollout restart deployment/homeassistant -n homeassistant
```

### Disable MFA (Emergency Only)

If locked out and backup codes lost:

```bash
# Access the database
kubectl exec -it -n homeassistant deployment/homeassistant -- /bin/bash

# Disable MFA via sqlite3
sqlite3 /config/home-assistant_v2.db

# Find user ID
SELECT id, name FROM users;

# Disable MFA for user (replace USER_ID)
DELETE FROM auth_module_user WHERE user_id = 'USER_ID' AND auth_module_id = 'totp';

# Exit
.quit
exit

# Restart Home Assistant
kubectl rollout restart deployment/homeassistant -n homeassistant
```

**WARNING:** Only use this in emergencies. You'll need to re-enable MFA afterward.

---

## Additional Security Recommendations

### 1. Regular Updates

Keep Home Assistant updated:
- Check for updates monthly
- Review release notes for security fixes
- Test in non-production first if possible

### 2. Audit Automations

Review automations for security issues:
- Don't expose sensitive data in automation actions
- Be careful with shell commands in automations
- Use secrets for API keys/passwords

### 3. Network Segmentation

Consider:
- Separate VLAN for IoT devices
- Firewall rules limiting IoT device internet access
- Monitor traffic for suspicious activity

### 4. Access Logging

Enable detailed logging:

```yaml
logger:
  default: info
  logs:
    homeassistant.components.http.ban: warning
    homeassistant.components.auth: info
```

---

## References

- [Home Assistant Security Documentation](https://www.home-assistant.io/docs/configuration/securing/)
- [Home Assistant Authentication](https://www.home-assistant.io/docs/authentication/)
- [HTTP Integration](https://www.home-assistant.io/integrations/http/)
- [Recorder Integration](https://www.home-assistant.io/integrations/recorder/)

---

**Status**: Ready for Implementation
**Estimated Time**: 30 minutes
**Risk Level**: Low (mostly UI-based configuration)
