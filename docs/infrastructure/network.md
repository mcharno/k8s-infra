# Network Infrastructure - Hybrid HTTPS Setup

Cloudflare Tunnel configuration for secure external access + direct local access.

## Overview

**Hybrid Network Architecture:**
- **External Access**: Cloudflare Tunnel → Hidden IP, DDoS protection, zero trust
- **Local Access**: Direct connection → Fast, low latency, works offline
- **Multi-Domain**: charn.io (external + local), charno.net (external only)
- **Wildcard SSL**: Automatic HTTPS with Let's Encrypt via DNS-01 challenge

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    EXTERNAL USERS (Internet)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Cloudflare Network                      │
│  • DDoS Protection                                          │
│  • SSL/TLS Termination (Full Strict mode)                  │
│  • WAF & Bot Protection                                     │
│  • CDN & Caching                                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓ Cloudflare Tunnel (encrypted)
┌─────────────────────────────────────────────────────────────┐
│                    cloudflared (on Pi)                       │
│  Port 443 outbound → Cloudflare Edge                        │
│  Receives: *.charn.io, *.charno.net                        │
│  Forwards to: localhost:30280 (Nginx Ingress HTTP)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓

┌─────────────────────────────────────────────────────────────┐
│                     LOCAL USERS (Home Network)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓ Direct HTTPS
┌─────────────────────────────────────────────────────────────┐
│                      Router Port Forward                     │
│  443 → Pi:30443                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓

                    ┌─────────────────┐
                    │  Nginx Ingress  │
                    │  Port 30280 (HTTP)  │
                    │  Port 30443 (HTTPS) │
                    │                 │
                    │  • SSL Termination │
                    │  • Host-based Routing │
                    │  • Load Balancing │
                    └─────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ↓                   ↓                   ↓
    ┌──────────┐       ┌──────────┐       ┌──────────┐
    │ Homer    │       │ Nextcloud│       │ Jellyfin │
    │ :8080    │       │ :80      │       │ :8096    │
    └──────────┘       └──────────┘       └──────────┘
```

## Traffic Flow

### External Traffic (*.charn.io, *.charno.net)
```
User → Cloudflare Edge → Tunnel → cloudflared → Nginx Ingress:30280 → App Pod
```

### Local Traffic (*.local.charn.io)
```
User → Router:443 → Pi:30443 → Nginx Ingress:30443 → App Pod
```

## Key Design Decisions

### Why Cloudflare Tunnel?
- ✅ No port forwarding needed for external access
- ✅ Hidden home IP address
- ✅ Built-in DDoS protection
- ✅ Zero Trust security model
- ✅ Works behind CGNAT/double NAT
- ✅ No dynamic DNS updates needed

### Why Hybrid (Tunnel + Local)?
- ✅ External users get Cloudflare security
- ✅ Local users get fast, direct connection
- ✅ Local access works even if internet is down
- ✅ Lower latency for streaming media locally
- ✅ No bandwidth limits on local traffic

### Why Nginx Ingress Gets HTTP from Tunnel?
- ✅ Cloudflare already terminates SSL/TLS
- ✅ Tunnel connection is encrypted
- ✅ Simplifies Nginx configuration
- ✅ Avoids certificate management issues
- ⚠️  **CRITICAL**: Nginx must have `ssl-redirect: false` to prevent 308 loops

## Prerequisites

### Cloudflare Account
- Two domains managed by Cloudflare:
  - `charn.io` - For applications (external + local access)
  - `charno.net` - For websites (external only)
- Cloudflare API token with DNS:Edit permissions for both zones

### Kubernetes Infrastructure
- K3s cluster running on Raspberry Pi
- Nginx Ingress Controller installed (ports 30280, 30443)
- cert-manager installed with Cloudflare DNS-01 solver
- Wildcard certificates issued for:
  - `*.charn.io` and `charn.io`
  - `*.local.charn.io` and `local.charn.io`
  - `*.charno.net` and `charno.net`

### Network Requirements
- Static local IP for Pi (e.g., 192.168.0.23)
- Router admin access (for local port forwarding)
- Outbound port 443 access (for Cloudflare Tunnel)

## Installation

### Step 1: Install cloudflared

**Automated Installation:**
```bash
# Run interactive installer
bash infrastructure/network/install-cloudflared.sh
```

**Manual Installation:**
```bash
# Download cloudflared for ARM64
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb

# Install
sudo dpkg -i cloudflared-linux-arm64.deb

# Verify
cloudflared --version
```

### Step 2: Authenticate with Cloudflare

```bash
# Opens browser for authentication
cloudflared tunnel login

# This creates: ~/.cloudflared/cert.pem
```

### Step 3: Create Tunnel

```bash
# Create tunnel named "pi-hybrid"
cloudflared tunnel create pi-hybrid

# Note the Tunnel ID from output!
# Example: "Created tunnel pi-hybrid with id: 12345678-1234-1234-1234-123456789abc"

# List tunnels
cloudflared tunnel list
```

### Step 4: Configure Tunnel

```bash
# Create config directory
sudo mkdir -p /etc/cloudflared

# Copy template config
sudo cp infrastructure/network/cloudflared-config.yml /etc/cloudflared/config.yml

# Edit with your tunnel ID
sudo nano /etc/cloudflared/config.yml
# Replace YOUR_TUNNEL_ID with actual tunnel ID (two places)
```

**Configuration explanation:**
- `tunnel`: Your unique tunnel ID
- `credentials-file`: Path to tunnel credentials JSON
- `ingress`: Rules mapping hostnames to backend services
- `metrics`: Prometheus metrics endpoint (optional)

### Step 5: Copy Credentials File

```bash
# The credentials file is created in ~/.cloudflared/ when you create the tunnel
# It needs to be in /root/.cloudflared/ for the service

# Replace YOUR_TUNNEL_ID with actual ID
TUNNEL_ID="12345678-1234-1234-1234-123456789abc"
sudo mkdir -p /root/.cloudflared
sudo cp ~/.cloudflared/$TUNNEL_ID.json /root/.cloudflared/
```

### Step 6: Route DNS

```bash
# Route charn.io services through tunnel
cloudflared tunnel route dns pi-hybrid homer.charn.io
cloudflared tunnel route dns pi-hybrid nextcloud.charn.io
cloudflared tunnel route dns pi-hybrid jellyfin.charn.io
cloudflared tunnel route dns pi-hybrid grafana.charn.io
cloudflared tunnel route dns pi-hybrid prometheus.charn.io
cloudflared tunnel route dns pi-hybrid wallabag.charn.io
cloudflared tunnel route dns pi-hybrid home.charn.io
cloudflared tunnel route dns pi-hybrid k8s.charn.io

# Route charno.net through tunnel
cloudflared tunnel route dns pi-hybrid charno.net
cloudflared tunnel route dns pi-hybrid www.charno.net
```

**What this does:**
- Creates CNAME records in Cloudflare DNS
- Points: `subdomain.domain.com` → `YOUR_TUNNEL_ID.cfargotunnel.com`
- Automatically configures routing in Cloudflare

### Step 7: Test Configuration

```bash
# Test tunnel manually (Ctrl+C to stop)
sudo cloudflared tunnel --config /etc/cloudflared/config.yml run pi-hybrid

# Watch for:
# ✓ "Connection registered" messages (should see 4 connections)
# ✓ No errors
# ✓ Metrics endpoint accessible: curl http://localhost:2000/metrics
```

### Step 8: Install as System Service

```bash
# Install systemd service
sudo cloudflared service install

# Start service
sudo systemctl start cloudflared

# Enable on boot
sudo systemctl enable cloudflared

# Check status
sudo systemctl status cloudflared
```

## Router Configuration (Local Access)

### Port Forwarding

Configure these rules in your router:

| Service | External Port | Internal IP | Internal Port | Protocol |
|---------|--------------|-------------|---------------|----------|
| HTTPS   | 443          | 192.168.0.23 | 30443        | TCP      |
| HTTP*   | 80           | 192.168.0.23 | 30280        | TCP      |

*HTTP port forwarding is optional (for auto-redirects)

### Local DNS Configuration

For `*.local.charn.io` to work, you need local DNS:

**Option A: Pi-hole or Local DNS Server**
```
DNS Record: *.local.charn.io → 192.168.0.23
Type: A record (or wildcard)
```

**Option B: Router DNS Override**
```
Some routers support custom DNS entries
Add: *.local.charn.io → 192.168.0.23
```

**Option C: Hosts File (Per Device)**

Linux/Mac: `/etc/hosts`
```
192.168.0.23  homer.local.charn.io
192.168.0.23  nextcloud.local.charn.io
192.168.0.23  jellyfin.local.charn.io
192.168.0.23  grafana.local.charn.io
192.168.0.23  prometheus.local.charn.io
192.168.0.23  recipes.local.charn.io
192.168.0.23  wallabag.local.charn.io
192.168.0.23  home.local.charn.io
```

Windows: `C:\Windows\System32\drivers\etc\hosts` (same format)

## Verification

### Check Tunnel Status

```bash
# Service status
sudo systemctl status cloudflared

# Real-time logs
sudo journalctl -u cloudflared -f

# Should show:
# ✓ "Connection registered" (4 connections)
# ✓ "Metrics server listening" on :2000
```

### Check DNS Records

Log into Cloudflare Dashboard → DNS:

**charn.io zone should have:**
```
homer.charn.io       CNAME  YOUR_TUNNEL_ID.cfargotunnel.com
nextcloud.charn.io   CNAME  YOUR_TUNNEL_ID.cfargotunnel.com
jellyfin.charn.io    CNAME  YOUR_TUNNEL_ID.cfargotunnel.com
# ... etc
```

**charno.net zone should have:**
```
charno.net       CNAME  YOUR_TUNNEL_ID.cfargotunnel.com
www.charno.net   CNAME  YOUR_TUNNEL_ID.cfargotunnel.com
```

### Test External Access

From a device NOT on your home network (mobile on cellular):

```bash
# Test HTTP to HTTPS redirect
curl -I http://homer.charn.io
# Should return: 301 or 308 redirect to https://

# Test HTTPS
curl -I https://homer.charn.io
# Should return: 200 OK

# Test charno.net
curl -I https://charno.net
# Should return: 200 OK
```

### Test Local Access

From a device on your home network:

```bash
# Test local DNS resolution
nslookup homer.local.charn.io
# Should resolve to: 192.168.0.23

# Test HTTPS
curl -I https://homer.local.charn.io
# Should return: 200 OK

# Test direct to NodePort (bypassing ingress)
curl -k https://192.168.0.23:30443
# Should return: default backend - 404 (expected)
```

## Configuration Files

### cloudflared-config.yml

**Location**: `/etc/cloudflared/config.yml`

**Key sections:**
- `tunnel`: Unique tunnel identifier
- `credentials-file`: Path to tunnel credentials
- `ingress`: Hostname routing rules (order matters!)
- `metrics`: Prometheus metrics endpoint

**Adding new services:**
```yaml
ingress:
  # Add before catch-all rule
  - hostname: newapp.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: newapp.charn.io
      noTLSVerify: false

  # Catch-all MUST be last
  - service: http_status:404
```

**Important notes:**
- All services route to same backend: `http://localhost:30280`
- Nginx Ingress handles routing based on `Host` header
- `httpHostHeader` ensures correct header is passed
- `noTLSVerify: false` verifies internal SSL (not needed since Nginx speaks HTTP)

### Credentials File

**Location**: `/root/.cloudflared/YOUR_TUNNEL_ID.json`

**Format**:
```json
{
  "AccountTag": "abc123...",
  "TunnelSecret": "xyz789...",
  "TunnelID": "12345678-1234-1234-1234-123456789abc"
}
```

**Security**:
- ✅ Automatically created by cloudflared
- ✅ Contains secret credentials
- ⚠️  **Do NOT commit to git**
- ⚠️  Restricted to root user (600 permissions)

## Common Operations

### Add New Service

**1. Add to Cloudflare Tunnel config:**
```bash
sudo nano /etc/cloudflared/config.yml
```

Add before catch-all:
```yaml
- hostname: newservice.charn.io
  service: http://localhost:30280
  originRequest:
    httpHostHeader: newservice.charn.io
```

**2. Route DNS:**
```bash
cloudflared tunnel route dns pi-hybrid newservice.charn.io
```

**3. Restart tunnel:**
```bash
sudo systemctl restart cloudflared
```

**4. Create Kubernetes Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: newservice-external
  namespace: newservice
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - newservice.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: newservice.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: newservice
            port:
              number: 80
```

**5. Test:**
```bash
# External
curl -I https://newservice.charn.io

# Local (if desired)
curl -I https://newservice.local.charn.io
```

### Restart Tunnel

```bash
# Restart service
sudo systemctl restart cloudflared

# Check status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -n 50
```

### Update cloudflared

```bash
# Download latest
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb

# Install update
sudo dpkg -i cloudflared-linux-arm64.deb

# Restart service
sudo systemctl restart cloudflared

# Verify version
cloudflared --version
```

### View Tunnel Info

```bash
# List all tunnels
cloudflared tunnel list

# Info about specific tunnel
cloudflared tunnel info pi-hybrid

# Show tunnel credentials
cloudflared tunnel info pi-hybrid --show-credentials
```

## Monitoring

### Systemd Service

```bash
# Status check
sudo systemctl status cloudflared

# Real-time logs
sudo journalctl -u cloudflared -f

# Last 100 lines
sudo journalctl -u cloudflared -n 100

# Filter for errors
sudo journalctl -u cloudflared | grep -i error
```

### Metrics Endpoint

If metrics are enabled (`metrics: localhost:2000`):

```bash
# View all metrics
curl http://localhost:2000/metrics

# Prometheus scrape config
scrape_configs:
  - job_name: 'cloudflared'
    static_configs:
      - targets: ['localhost:2000']
```

**Key metrics:**
- `cloudflared_tunnel_connections_total`: Number of connections to edge
- `cloudflared_tunnel_requests_total`: Total requests through tunnel
- `cloudflared_tunnel_response_time_seconds`: Response time histogram

### Cloudflare Dashboard

**Tunnel Status:**
1. Log into Cloudflare Zero Trust dashboard
2. Go to **Access** → **Tunnels**
3. Find your tunnel: should show "Healthy" with 4 connections

**Analytics:**
1. Go to domain in Cloudflare dashboard
2. **Analytics & Logs** → **Traffic**
3. View requests, bandwidth, response codes

### Health Check Script

```bash
#!/bin/bash
# Check tunnel health

# Check service
if systemctl is-active --quiet cloudflared; then
    echo "✓ Service is running"
else
    echo "✗ Service is NOT running"
    exit 1
fi

# Check metrics endpoint
if curl -s http://localhost:2000/metrics > /dev/null; then
    echo "✓ Metrics endpoint accessible"
else
    echo "✗ Metrics endpoint unreachable"
fi

# Check external connectivity
if curl -s -o /dev/null -w "%{http_code}" https://homer.charn.io | grep -q "200"; then
    echo "✓ External access working"
else
    echo "✗ External access failed"
fi
```

## Troubleshooting

### Tunnel Won't Start

**Symptoms:**
```bash
sudo systemctl status cloudflared
# Shows: failed or inactive
```

**Diagnostic steps:**
```bash
# Check logs
sudo journalctl -u cloudflared -n 50

# Common errors and fixes:

# Error: "tunnel credentials not found"
# Fix: Verify credentials file exists
ls -la /root/.cloudflared/*.json
sudo cp ~/.cloudflared/YOUR_TUNNEL_ID.json /root/.cloudflared/

# Error: "tunnel not found"
# Fix: Verify tunnel ID in config matches actual tunnel
cloudflared tunnel list
sudo nano /etc/cloudflared/config.yml  # Update tunnel ID

# Error: "permission denied"
# Fix: Ensure config file is readable
sudo chmod 600 /etc/cloudflared/config.yml
sudo chown root:root /etc/cloudflared/config.yml
```

### Tunnel Connects But Site Unreachable

**Symptoms:**
- Tunnel shows "healthy" in Cloudflare dashboard
- But accessing https://homer.charn.io returns error

**Diagnostic steps:**
```bash
# 1. Check DNS records
nslookup homer.charn.io
# Should return: CNAME pointing to tunnel

# 2. Check if Nginx Ingress is running
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
# Nginx should be running on ports 30280/30443

# 3. Test Nginx directly
curl -H "Host: homer.charn.io" http://localhost:30280
# Should return response from homer

# 4. Check Ingress resource exists
kubectl get ingress -A | grep homer

# 5. Check cloudflared logs for errors
sudo journalctl -u cloudflared -f
# Make a request and watch for errors
```

### 502 Bad Gateway

**Symptoms:**
- Cloudflare returns 502 error

**Causes and fixes:**

**1. Backend service not running**
```bash
# Check application pod
kubectl get pods -n homer
# Should be Running

# If not, check logs
kubectl logs -n homer -l app=homer
```

**2. Wrong service name/port in Ingress**
```bash
# Check ingress
kubectl describe ingress homer-external -n homer

# Verify service exists
kubectl get svc homer -n homer

# Check endpoints
kubectl get endpoints homer -n homer
# Should show IP:port of running pod
```

**3. Nginx can't reach pod**
```bash
# Check Nginx logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Look for connection refused or timeout errors
```

### 308 Redirect Loop

**Symptoms:**
- Browser shows "Too many redirects"
- curl shows infinite 308 responses

**Cause:**
- Nginx ConfigMap has `ssl-redirect: true` globally
- Cloudflare sends HTTP to Nginx
- Nginx redirects to HTTPS
- Loop continues

**Fix:**
```bash
# Check Nginx ConfigMap
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep ssl-redirect

# Should show: ssl-redirect: "false"

# If not, fix it:
kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
  --patch '{"data":{"ssl-redirect":"false"}}'

# Restart Nginx
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

**Per-ingress SSL redirect:**
If you want SSL redirect for local access only:
```yaml
# External ingress (via tunnel) - NO redirect
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"

# Local ingress - YES redirect
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

### Local Access Not Working

**Symptoms:**
- External access works
- Local access (*.local.charn.io) fails

**Diagnostic steps:**

**1. Check DNS resolution**
```bash
nslookup homer.local.charn.io
# Should resolve to Pi's local IP (192.168.0.23)

# If not, configure local DNS (see earlier section)
```

**2. Check port forwarding**
```bash
# From another device on network
nc -zv 192.168.0.23 30443
# Should show: Connection succeeded

# If not, verify router port forwarding
```

**3. Check Nginx is listening**
```bash
# On Pi
kubectl get svc -n ingress-nginx
# Should show NodePort 30443

# Test directly
curl -k https://192.168.0.23:30443
# Should return: default backend - 404 (expected)
```

**4. Check local ingress exists**
```bash
kubectl get ingress -A | grep local
# Should show ingresses for *.local.charn.io

kubectl get ingress homer-local -n homer
# Should show host: homer.local.charn.io
```

### Certificate Errors

**Symptoms:**
- Browser shows "Invalid certificate"
- SSL handshake errors

**Causes:**

**1. Certificate not issued**
```bash
kubectl get certificate -n cert-manager
# Should all show READY=True

# If not, check cert-manager
kubectl describe certificate charn-io-wildcard -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

**2. Wrong certificate used in ingress**
```bash
kubectl describe ingress homer-external -n homer
# Check tls.secretName matches certificate secretName

# For external: charn-io-wildcard-tls
# For local: local-charn-io-wildcard-tls
```

**3. Certificate not in correct namespace**
```bash
# Certificates are in cert-manager namespace
# Must be copied to app namespaces

kubectl get secret charn-io-wildcard-tls -n homer
# If not found, copy it

bash scripts/cert-manager/copy-certs-to-namespace.sh homer
```

## Security Considerations

### Current Security

✅ **Strengths:**
- Home IP hidden behind Cloudflare
- Tunnel connection encrypted (TLS)
- Cloudflare WAF and bot protection
- Valid SSL certificates (no self-signed)
- HSTS can be enabled
- Network isolation (K8s network policies)

⚠️ **Weaknesses:**
- Tunnel → Nginx uses HTTP (no end-to-end encryption)
- No authentication on tunnel (relies on Cloudflare)
- Single point of failure (tunnel service)
- Metrics endpoint unauthenticated

### Recommendations

**1. Enable Cloudflare Access (Zero Trust)**
```
Add authentication before reaching apps:
- Go to Cloudflare Zero Trust dashboard
- Create Access policies
- Require login (Google, GitHub, email OTP)
- Apply to sensitive services (grafana, prometheus)
```

**2. Restrict Access by Geography**
```
Cloudflare Firewall Rules:
- Block traffic from unwanted countries
- Allow only known IP ranges for admin panels
```

**3. Rate Limiting**
```
Protect login endpoints:
- /login → 5 requests/minute
- /admin → 10 requests/hour
- Automatic bans for repeated failures
```

**4. Monitor Access Logs**
```bash
# Cloudflare dashboard shows all requests
# Set up alerts for:
- Unusual traffic patterns
- 4xx/5xx error spikes
- Geographic anomalies
```

**5. Backup Credentials**
```bash
# Backup tunnel credentials securely
cp /root/.cloudflared/*.json /mnt/k3s-storage/backups/
# Encrypt if storing off-site

# Also backup config
cp /etc/cloudflared/config.yml /mnt/k3s-storage/backups/
```

## Performance Tuning

### Tunnel Connections

By default, cloudflared creates 4 connections to Cloudflare edge.

**Increase for high traffic:**
```yaml
# In config.yml
connections: 8  # More connections = better load distribution
```

### Compression

Enable compression for text resources:

```yaml
# In config.yml
ingress:
  - hostname: homer.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: homer.charn.io
      noTLSVerify: false
      disableChunkedEncoding: false  # Enable compression
```

### Connection Tuning

```yaml
# In config.yml
connectionAttempts: 3
connectionTimeout: 30s
gracePeriod: 30s
```

## Backup & Disaster Recovery

### Backup Tunnel Configuration

```bash
# Backup config file
sudo cp /etc/cloudflared/config.yml ~/backups/cloudflared-config-$(date +%Y%m%d).yml

# Backup credentials
sudo cp /root/.cloudflared/*.json ~/backups/

# Backup to external location
scp ~/backups/cloudflared-* user@backup-server:/backups/
```

### Restore Tunnel

If you need to rebuild the Pi:

```bash
# 1. Reinstall cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb

# 2. Restore config
sudo mkdir -p /etc/cloudflared /root/.cloudflared
sudo cp backups/cloudflared-config.yml /etc/cloudflared/config.yml
sudo cp backups/YOUR_TUNNEL_ID.json /root/.cloudflared/

# 3. Install service
sudo cloudflared service install

# 4. Start
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# DNS routes persist in Cloudflare, no need to re-route
```

### Alternative: Recreate Tunnel

If credentials are lost:

```bash
# 1. Delete old tunnel
cloudflared tunnel list
cloudflared tunnel delete pi-hybrid

# 2. Delete DNS records in Cloudflare dashboard

# 3. Create new tunnel
bash infrastructure/network/install-cloudflared.sh

# 4. Update all ingresses (if tunnel ID changed)
# Certificate secrets remain valid
```

## Files

- `cloudflared-config.yml` - Tunnel configuration template
- `install-cloudflared.sh` - Automated installation script
- `README.md` - This file

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Zero Trust Dashboard](https://one.dash.cloudflare.com/)
- [Nginx Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Network Architecture Guide](../../docs/network-setup.md)

## Summary

**What You Have:**
- ✅ Secure external access via Cloudflare Tunnel
- ✅ Fast local access via direct connection
- ✅ Multi-domain support (charn.io + charno.net)
- ✅ Automatic HTTPS with wildcard certificates
- ✅ Hidden home IP with DDoS protection
- ✅ Works behind NAT/CGNAT
- ✅ Zero configuration on client devices

**Key URLs:**
- External: `https://*.charn.io`, `https://*.charno.net`
- Local: `https://*.local.charn.io`
- Tunnel metrics: `http://localhost:2000/metrics`

**Management Commands:**
```bash
sudo systemctl status cloudflared          # Check status
sudo systemctl restart cloudflared         # Restart tunnel
sudo journalctl -u cloudflared -f          # View logs
cloudflared tunnel list                    # List tunnels
cloudflared tunnel info pi-hybrid          # Tunnel details
```
