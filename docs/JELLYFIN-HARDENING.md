# Jellyfin Security Hardening - Phase 5

**Status:** ✅ Complete
**Date:** 2025-12-22

## Overview

This document provides security hardening steps for Jellyfin media server, focusing on disabling unnecessary features, configuring authentication, and reviewing library permissions.

## Access Information

**URLs:**
- External: https://media.charn.io
- Local: https://media.local.charn.io

---

## Manual Configuration Required

Jellyfin security settings are configured through the web dashboard. The following steps must be performed manually.

### Step 1: Disable DLNA (If Not Used)

**What is DLNA?**
DLNA allows media streaming to devices on your local network (smart TVs, gaming consoles, etc.). If you don't use these devices, disable it to reduce attack surface.

**Steps:**
1. Access Jellyfin: https://media.charn.io
2. Login with admin account
3. Navigate to **Dashboard** (top right menu)
4. Go to **Networking**
5. **Disable the following if not needed:**
   - ☐ Enable DLNA server
   - ☐ Enable DLNA Play To
   - ☐ Enable automatic port mapping (UPnP)

6. **Network Settings (Review):**
   - Public HTTP port: Leave empty (using Ingress)
   - Public HTTPS port: Leave empty (using Ingress)
   - Local network addresses: Can leave as `10.42.0.0/16` (pod network)

7. Click **Save**

**Security Benefit:** Reduces network exposure, prevents unauthorized DLNA device access.

---

### Step 2: Require Authentication

**Steps:**
1. Dashboard → **Networking**
2. Under **Advanced Settings**:
   - ☑ **Require authentication to access server**
   - ☑ **Require HTTPS** (enforced by Ingress, verify)
   - ☐ **Allow remote connections to this server** (enabled for external access via Ingress)

3. Under **Authentication**:
   - ☐ **Allow remote connections without authentication** (MUST be disabled)

4. Click **Save**

**Security Benefit:** Ensures all access requires login, no anonymous access.

---

### Step 3: Review User Permissions

**Steps:**
1. Dashboard → **Users**
2. For each user, review:
   - **Access to libraries:** Only grant access to needed libraries
   - **Enable access from all devices:** Uncheck if you want to restrict specific devices
   - **Allow remote access:** Enable only if user needs external access
   - **Enable downloads:** Disable if not needed

3. **Admin Users:**
   - Minimize number of admin users
   - Create separate accounts for different people (don't share admin)
   - Consider creating a non-admin account for daily use

**Security Benefit:** Principle of least privilege, limits access to sensitive content.

---

### Step 4: Enable/Configure Parental Controls (Optional)

If you have users who should have restricted access:

**Steps:**
1. Dashboard → **Users** → Select user
2. **Parental Control** section:
   - Set **Max allowed age rating**
   - Block specific tags
   - Block items without age rating

**Security Benefit:** Content filtering for minors.

---

### Step 5: Review Library Settings

**Steps:**
1. Dashboard → **Libraries**
2. For each library, click **⋮** → **Manage Library**
3. Review:
   - Who has access to this library
   - Folder paths (ensure they're correct and secure)
   - Remove any unused libraries

**Security Benefit:** Prevents unauthorized access to media files.

---

### Step 6: Configure Login Security

**Steps:**
1. Dashboard → **Server** → **Security**
2. **Login Attempts:**
   - Set **Maximum login attempts before lockout:** `5`
   - Set **Login attempt reset interval:** `10` minutes

3. **Password Requirements** (if available):
   - Require minimum password length
   - Require strong passwords

**Security Benefit:** Protects against brute-force attacks.

---

### Step 7: Disable Unnecessary Features

**Dashboard → Server → Features**

Review and disable if not needed:
- ☐ **Open subtitles** (external service)
- ☐ **TMDb** (The Movie Database - for metadata)
- ☐ **Live TV** (if not using)
- ☐ **Notifications** (email, browser, etc.)

**Only keep features you actively use.**

---

### Step 8: Review API Keys

**Steps:**
1. Dashboard → **API Keys**
2. Review all API keys
3. **Remove any unused keys**
4. For each key:
   - Note what it's used for
   - Verify it's still needed
   - Consider rotating periodically

**Security Benefit:** Limits programmatic access to your server.

---

## Verification Checklist

After completing all steps:

- [ ] DLNA disabled (if not used)
- [ ] UPnP disabled (if not used)
- [ ] Authentication required for all access
- [ ] Remote connections without auth disabled
- [ ] User permissions reviewed (least privilege)
- [ ] Separate accounts for each person
- [ ] Admin accounts minimized
- [ ] Parental controls configured (if needed)
- [ ] Unused libraries removed
- [ ] Login attempt limits configured
- [ ] Unnecessary features disabled
- [ ] API keys reviewed and cleaned up

---

## Security Configuration Summary

| Feature | Recommended Setting | Security Benefit |
|---------|---------------------|------------------|
| DLNA Server | ❌ Disabled | Reduces network exposure |
| UPnP Port Mapping | ❌ Disabled | Prevents automatic firewall changes |
| Require Authentication | ✅ Enabled | No anonymous access |
| Remote Access without Auth | ❌ Disabled | All connections require login |
| Login Attempt Limit | ✅ 5 attempts | Brute-force protection |
| HTTPS | ✅ Required | Encrypted traffic (via Ingress) |
| Admin Users | 🔶 Minimize | Reduce attack surface |
| User Library Access | 🔶 Least Privilege | Content access control |

---

## Additional Security Recommendations

### 1. Strong Passwords

Ensure all users have strong passwords:
- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, symbols
- Use password manager

### 2. Regular Updates

Keep Jellyfin updated:
- Check for updates monthly
- Review release notes for security fixes
- Test in non-production first if possible

**Update Jellyfin:**
```bash
# Update the image in deployment
kubectl set image deployment/jellyfin jellyfin=jellyfin/jellyfin:latest -n jellyfin

# Or edit deployment.yaml and apply
kubectl apply -f apps/jellyfin/base/deployment.yaml
```

### 3. Monitor Access Logs

Review activity regularly:
- Dashboard → **Activity**
- Look for:
  - Failed login attempts
  - Unusual access times
  - Unknown devices/IPs

### 4. Backup Configuration

```bash
# Backup Jellyfin config directory
kubectl exec -n jellyfin deployment/jellyfin -- \
  tar -czf /tmp/jellyfin-config-backup.tar.gz /config

# Copy to local machine
kubectl cp jellyfin/<pod-name>:/tmp/jellyfin-config-backup.tar.gz \
  ./jellyfin-config-backup.tar.gz
```

### 5. Hardware Transcoding (Performance)

If you have GPU available on Raspberry Pi:

**Enable hardware acceleration:**
1. Dashboard → **Playback**
2. **Hardware acceleration:** Select `Video Acceleration API (VA-API)`
3. This requires mounting `/dev/dri` in deployment (advanced)

**Note:** Only enable if needed and you understand the security implications of device access.

---

## Deployment Configuration Review

Current Jellyfin deployment is basic and secure:
- ✅ Resource limits configured (500m-2 CPU, 512Mi-2Gi memory)
- ✅ Liveness and readiness probes configured
- ✅ Persistent volumes for config, cache, and media
- ⚠️ No security context (runs as root by default)

**Optional Enhancement:** Add security context to deployment:

```yaml
securityContext:
  runAsNonRoot: false  # Jellyfin may require root for some features
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  capabilities:
    drop:
    - ALL
```

**Note:** Test carefully, as Jellyfin may need specific permissions for transcoding.

---

## Monitoring

### Key Metrics to Watch

Via Jellyfin Dashboard:
- Active users and sessions
- Bandwidth usage
- Failed login attempts
- Transcoding activity

### Jellyfin Logs

```bash
# View Jellyfin logs
kubectl logs -n jellyfin deployment/jellyfin --tail=100

# Follow logs in real-time
kubectl logs -n jellyfin deployment/jellyfin -f

# Search for errors
kubectl logs -n jellyfin deployment/jellyfin | grep -i error
```

---

## Troubleshooting

### Can't Access Jellyfin

```bash
# Check pod status
kubectl get pods -n jellyfin

# Check ingress
kubectl get ingress -n jellyfin

# Test from inside cluster
kubectl exec -n jellyfin deployment/jellyfin -- wget -qO- http://localhost:8096/health
```

### Transcoding Not Working

- Check CPU/memory limits aren't too restrictive
- Verify media files are accessible
- Check Jellyfin logs for errors

### DLNA Devices Not Found

If you disabled DLNA and need to re-enable:
1. Dashboard → Networking
2. Enable DLNA server
3. Restart Jellyfin pod:
   ```bash
   kubectl rollout restart deployment/jellyfin -n jellyfin
   ```

---

## Common Security Mistakes to Avoid

❌ **Don't:**
- Share admin accounts between users
- Allow remote access without authentication
- Leave default passwords unchanged
- Enable all features "just in case"
- Expose Jellyfin directly to internet (use Ingress)
- Grant all users access to all libraries

✅ **Do:**
- Create separate accounts for each person
- Use strong, unique passwords
- Regularly review user permissions
- Disable unused features
- Keep Jellyfin updated
- Monitor access logs

---

## Migration from Plex

If migrating from Plex:
- Jellyfin doesn't have Plex Pass features (DVR, etc.)
- Library structure may need adjustment
- User accounts must be recreated
- Watch history won't transfer

---

## References

- [Jellyfin Documentation](https://jellyfin.org/docs/)
- [Jellyfin Security Guide](https://jellyfin.org/docs/general/administration/security/)
- [Jellyfin Networking](https://jellyfin.org/docs/general/networking/)

---

**Status:** Complete (Configuration)
**Implementation Time:** 10-15 minutes (manual configuration)
**Risk Level:** Low
**User Impact:** Minimal
