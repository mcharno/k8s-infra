# n8n Security Hardening - Phase 4

**Status:** ✅ Complete
**Date:** 2025-12-22

## Overview

This document details the security hardening implementation for n8n, including webhook security, payload limits, metrics enablement, and privacy controls.

## Access Information

**URLs:**
- External: https://auto.charn.io
- Local: https://auto.local.charn.io

---

## Implemented Security Enhancements

### 1. Payload Size Limits ✅

**Configuration:**
- `N8N_PAYLOAD_SIZE_MAX: 16` (MB)

**Purpose:**
- Prevents DoS attacks via large payloads
- Limits webhook payload size to 16MB
- Protects against memory exhaustion

### 2. Prometheus Metrics Enabled ✅

**Configuration:**
- `N8N_METRICS: true`

**Purpose:**
- Exposes metrics endpoint at `/metrics`
- Enables monitoring of:
  - Workflow executions
  - Active workflows
  - Webhook calls
  - Database connections
  - Memory usage

### 3. Privacy Controls ✅

**Configuration:**
- `N8N_DIAGNOSTICS_ENABLED: false` - Disable diagnostic data collection
- `N8N_PERSONALIZATION_ENABLED: false` - Disable telemetry
- `N8N_HIRING_BANNER_ENABLED: false` - Disable external banners

**Purpose:**
- No data sent to n8n.io
- Enhanced privacy
- Cleaner UI

### 4. Existing Security Settings (Verified) ✅

**Already Configured:**
- `N8N_USER_MANAGEMENT_DISABLED: false` - Multi-user mode enabled
- `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: true` - File permission enforcement
- `N8N_ENCRYPTION_KEY` - Stored securely in sealed secret
- `N8N_PROXY_HOPS: 1` - Correct for single reverse proxy (Ingress)
- Database credentials from sealed secret

---

## User Actions Required

### 1. Create Admin User Account

If you haven't already created an admin user:

1. **Access n8n**
   Visit: https://auto.charn.io

2. **Create First User**
   - On first access, you'll be prompted to create an admin account
   - Email: Your email address
   - Password: Strong password (use password manager)
   - First name / Last name

3. **Enable 2FA (if available)**
   - Check Settings → Security for 2FA options
   - n8n may support 2FA in newer versions

### 2. Review and Secure Webhooks

For workflows with webhook nodes:

#### Best Practices:

**A. Use Authentication Headers**
```javascript
// In webhook workflow, add Function node to validate:
if (!$request.headers['authorization']) {
  throw new Error('Unauthorized');
}

const expectedToken = 'Bearer YOUR_SECRET_TOKEN';
if ($request.headers['authorization'] !== expectedToken) {
  throw new Error('Invalid token');
}
```

**B. Implement HMAC Signatures**
```javascript
// For services that support HMAC (like GitHub, Stripe):
const crypto = require('crypto');
const signature = $request.headers['x-hub-signature-256'];
const payload = JSON.stringify($request.body);
const secret = 'YOUR_WEBHOOK_SECRET';

const hash = crypto
  .createHmac('sha256', secret)
  .update(payload)
  .digest('hex');

const expectedSignature = `sha256=${hash}`;
if (signature !== expectedSignature) {
  throw new Error('Invalid signature');
}
```

**C. IP Whitelisting (Optional)**
```javascript
// Restrict webhooks to specific IPs:
const allowedIPs = ['1.2.3.4', '5.6.7.8'];
const clientIP = $request.headers['x-forwarded-for'] || $request.connection.remoteAddress;

if (!allowedIPs.includes(clientIP)) {
  throw new Error('IP not allowed');
}
```

**D. Use POST-only Webhooks**
- Configure webhooks to accept only POST requests
- Prevents accidental GET requests from browsers

### 3. Configure Workflow Permissions

1. **User Roles**
   - Settings → Users → Manage roles
   - Assign appropriate permissions (Admin, Member, etc.)
   - Don't give everyone admin access

2. **Workflow Sharing**
   - Review workflow sharing settings
   - Limit access to sensitive workflows
   - Use credentials sharing carefully

---

## Verification

### Check Security Settings

```bash
# Verify n8n is running
kubectl get pods -n n8n

# Check environment variables
kubectl exec -n n8n deployment/n8n -- env | grep N8N_

# Expected output should include:
# N8N_PAYLOAD_SIZE_MAX=16
# N8N_METRICS=true
# N8N_DIAGNOSTICS_ENABLED=false
# N8N_PERSONALIZATION_ENABLED=false
```

### Test Metrics Endpoint

```bash
# Access metrics endpoint
kubectl exec -n n8n deployment/n8n -- curl -s http://localhost:5678/metrics | head -20

# Should see Prometheus metrics like:
# n8n_workflow_executions_total
# n8n_active_workflows
# process_cpu_seconds_total
# etc.
```

### Verify Webhook Limits

```bash
# Test with large payload (should fail if > 16MB)
curl -X POST https://auto.charn.io/webhook/test \
  -H "Content-Type: application/json" \
  -d @large_file.json

# Should return error if payload > 16MB
```

---

## Create ServiceMonitor for Prometheus

Create file: `apps/n8n/base/servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  selector:
    matchLabels:
      app: n8n
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

Apply:
```bash
kubectl apply -f apps/n8n/base/servicemonitor.yaml
```

---

## Security Configuration Summary

| Feature | Status | Configuration |
|---------|--------|---------------|
| User Management | ✅ Enabled | Multi-user mode active |
| Payload Size Limit | ✅ Configured | Max 16MB |
| Metrics | ✅ Enabled | Prometheus endpoint available |
| Diagnostics | ✅ Disabled | No data collection |
| Telemetry | ✅ Disabled | Privacy enhanced |
| Encryption Key | ✅ Secured | In sealed secret |
| Database Credentials | ✅ Secured | In sealed secret |
| HTTPS | ✅ Enforced | Via Ingress |
| Reverse Proxy | ✅ Configured | N8N_PROXY_HOPS=1 |

---

## Webhook Security Checklist

For each workflow with webhooks:

- [ ] Webhook URL is not easily guessable (use UUIDs)
- [ ] Authentication header validation implemented
- [ ] HMAC signature verification (if supported by sender)
- [ ] IP whitelisting configured (if applicable)
- [ ] POST-only requests enforced
- [ ] Payload size is reasonable (don't accept unlimited data)
- [ ] Error messages don't leak sensitive information
- [ ] Logs don't contain sensitive data
- [ ] Rate limiting considered (if high-volume webhooks)

---

## Monitoring

### Key Metrics to Watch

```bash
# Workflow execution metrics
kubectl exec -n n8n deployment/n8n -- curl -s http://localhost:5678/metrics | grep workflow

# Memory usage
kubectl top pod -n n8n

# Database connections
kubectl exec -n n8n deployment/n8n -- curl -s http://localhost:5678/metrics | grep db_connections
```

### Recommended Alerts

Create Prometheus alerts for:
- High failure rate on workflow executions
- Memory usage > 80%
- Database connection errors
- Webhook timeouts

---

## Advanced Security Configuration

### 1. Credential Management

**Best Practices:**
- Store credentials in n8n's credential system (encrypted)
- Don't hardcode API keys in workflows
- Use environment variables for sensitive data
- Regularly rotate credentials

### 2. Network Segmentation

**Current Setup:**
- n8n runs in dedicated namespace
- Database access via service DNS
- Ingress for external access only

**Enhancement Options:**
- NetworkPolicy to restrict n8n → internet (allow specific APIs only)
- Separate namespace for production vs development workflows

### 3. Audit Logging

```bash
# View n8n logs
kubectl logs -n n8n deployment/n8n --tail=100

# Follow logs in real-time
kubectl logs -n n8n deployment/n8n -f

# Search for failed authentications
kubectl logs -n n8n deployment/n8n | grep -i "auth\|login\|failed"
```

---

## Common Webhook Security Patterns

### Pattern 1: API Key Validation

```javascript
// In HTTP Request node before processing:
const apiKey = $request.headers['x-api-key'];
const validKeys = ['key1', 'key2']; // Store in credentials instead

if (!apiKey || !validKeys.includes(apiKey)) {
  return {
    statusCode: 401,
    body: { error: 'Unauthorized' }
  };
}
```

### Pattern 2: Timestamp Validation

```javascript
// Reject old requests (prevent replay attacks):
const timestamp = parseInt($request.headers['x-timestamp']);
const now = Date.now();
const maxAge = 5 * 60 * 1000; // 5 minutes

if (Math.abs(now - timestamp) > maxAge) {
  return {
    statusCode: 400,
    body: { error: 'Request too old' }
  };
}
```

### Pattern 3: Request Origin Validation

```javascript
// Validate Origin header:
const allowedOrigins = ['https://trusted-site.com'];
const origin = $request.headers['origin'];

if (!allowedOrigins.includes(origin)) {
  return {
    statusCode: 403,
    body: { error: 'Origin not allowed' }
  };
}
```

---

## Troubleshooting

### Webhook Not Receiving Data

```bash
# Check n8n logs
kubectl logs -n n8n deployment/n8n --tail=50

# Test webhook URL is accessible
curl -v https://auto.charn.io/webhook/YOUR_WEBHOOK_ID

# Check Ingress configuration
kubectl get ingress -n n8n
```

### Metrics Not Available

```bash
# Verify N8N_METRICS is set
kubectl exec -n n8n deployment/n8n -- env | grep N8N_METRICS

# Test metrics endpoint
kubectl exec -n n8n deployment/n8n -- curl -s http://localhost:5678/metrics
```

### Payload Too Large Error

```bash
# Check current limit
kubectl exec -n n8n deployment/n8n -- env | grep PAYLOAD_SIZE

# Increase if needed (update deployment.yaml)
# N8N_PAYLOAD_SIZE_MAX: "32"  # 32MB
```

---

## Backup and Restore

### Backup Workflows

```bash
# Export all workflows
# Via n8n UI: Settings → Import/Export → Export

# Or via API (requires auth token)
curl -H "X-N8N-API-KEY: YOUR_API_KEY" \
  https://auto.charn.io/api/v1/workflows \
  > workflows_backup.json
```

### Backup Database

```bash
# Backup n8n PostgreSQL database
kubectl exec -n database postgres-0 -- \
  pg_dump -U n8n n8n > n8n_database_backup.sql
```

---

## References

- [n8n Security Documentation](https://docs.n8n.io/hosting/security/)
- [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [n8n Webhook Documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)
- [n8n API Documentation](https://docs.n8n.io/api/)

---

**Status:** Complete
**Implementation Time:** 10 minutes
**Risk Level:** Low
**User Impact:** Minimal (requires webhook review)
