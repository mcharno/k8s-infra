# Hybrid HTTPS Network Setup - Complete Documentation

## Overview

This document describes the complete hybrid network setup for the K3s cluster running on a Raspberry Pi 4, providing both external (internet) and local (home network) HTTPS access to services.

**Last Updated:** November 2025  
**Status:** Production  
**Author:** System Setup Documentation

---

## Table of Contents

1. [Architecture Summary](#architecture-summary)
2. [External Access (Cloudflare Tunnel)](#external-access-cloudflare-tunnel)
3. [Local Access (Direct)](#local-access-direct)
4. [SSL/TLS Certificates](#ssltls-certificates)
5. [Nginx Ingress Controller](#nginx-ingress-controller)
6. [DNS Configuration](#dns-configuration)
7. [Application Configuration](#application-configuration)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)

---

## Architecture Summary

### The Hybrid Approach

This setup provides **two separate pathways** to access services:

1. **External Access:** Via Cloudflare Tunnel (internet)
2. **Local Access:** Direct connection (home network)

Both use HTTPS with valid SSL certificates but different certificate issuance methods.

### Key Components

- **K3s Cluster:** Single-node Kubernetes on Raspberry Pi 4
- **Nginx Ingress Controller:** Routes incoming traffic to services
- **cert-manager:** Automates SSL certificate management
- **Cloudflare Tunnel (cloudflared):** Secure tunnel for external access
- **Let's Encrypt:** Certificate Authority for SSL certificates

### Domains

- **External:** `*.charn.io`, `*.charno.net`
- **Local:** `*.local.charn.io`

---

## External Access (Cloudflare Tunnel)

### How It Works

External users access services through Cloudflare's global network, which provides:
- DDoS protection
- SSL termination
- Automatic HTTPS enforcement
- Geographic load balancing

### Traffic Flow

```
User (Internet)
    ↓
Cloudflare Edge Servers (DDoS protection, SSL)
    ↓
Cloudflare Tunnel (encrypted connection)
    ↓
cloudflared daemon (on Pi)
    ↓
Nginx Ingress Controller :30280 (HTTP)
    ↓
Application Services
```

### Configuration

#### Cloudflare Tunnel Setup

**Location:** `/etc/cloudflared/config.yml`

```yaml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: homer.charn.io
    service: http://localhost:30280
  - hostname: nextcloud.charn.io
    service: http://localhost:30280
  - hostname: jellyfin.charn.io
    service: http://localhost:30280
  - hostname: home.charn.io
    service: http://localhost:30280
  - hostname: grafana.charn.io
    service: http://localhost:30280
  - hostname: prometheus.charn.io
    service: http://localhost:30280
  - hostname: k8s.charn.io
    service: http://localhost:30280
  - hostname: wallabag.charn.io
    service: http://localhost:30280
  - hostname: charno.net
    service: http://localhost:30280
  - service: http_status:404
```

**Service Management:**
```bash
# Status
sudo systemctl status cloudflared

# Restart
sudo systemctl restart cloudflared

# View logs
sudo journalctl -u cloudflared -f
```

#### DNS Records

Each hostname has a CNAME record pointing to the tunnel:

```
homer.charn.io      → CNAME → <tunnel-id>.cfargotunnel.com
nextcloud.charn.io  → CNAME → <tunnel-id>.cfargotunnel.com
# ... etc
```

**To add new service:**
```bash
# 1. Add to cloudflared config
sudo nano /etc/cloudflared/config.yml

# 2. Restart cloudflared
sudo systemctl restart cloudflared

# 3. Add DNS record
cloudflared tunnel route dns pi-hybrid newservice.charn.io
```

### Certificates (External)

External access uses **DNS-01 challenge** with Cloudflare API for wildcard certificates.

**Certificate Resources:**
- `charn-io-wildcard-tls` - Covers `*.charn.io`
- `charno-net-wildcard-tls` - Covers `*.charno.net`

**ClusterIssuer:** `letsencrypt-cloudflare-prod`

**Validity:** 90 days, auto-renewed by cert-manager

---

## Local Access (Direct)

### How It Works

Users on the home network connect directly to the Pi via the router, bypassing Cloudflare entirely.

### Traffic Flow

```
User (Home Network)
    ↓
Home Router:443 (port forward)
    ↓
Pi:30443 (Nginx Ingress HTTPS port)
    ↓
Nginx Ingress Controller (HTTPS, terminates SSL)
    ↓
Application Services
```

### Configuration

#### Router Port Forwarding

**Required forwards:**
```
External Port → Internal IP:Port
443           → 192.168.0.23:30443  (HTTPS - always needed)
80            → 192.168.0.23:30280  (HTTP - only for cert issuance)
```

**Important:** Port 80 is only needed temporarily when HTTP-01 certificates are being issued. Can be removed after initial setup if desired, but certificates won't auto-renew without it.

#### Local DNS

Configure local DNS resolution (options):

**Option A: Router DNS (Recommended)**
- Add custom DNS entries in router
- Points `*.local.charn.io` to `192.168.0.23`

**Option B: Pi-hole**
- Local DNS entry for `local.charn.io`
- Wildcard: `*.local.charn.io` → `192.168.0.23`

**Option C: Hosts File**
```
# /etc/hosts or C:\Windows\System32\drivers\etc\hosts
192.168.0.23  homer.local.charn.io
192.168.0.23  nextcloud.local.charn.io
# ... etc
```

### Certificates (Local)

Local access uses **HTTP-01 challenge** for individual certificates.

**Certificate Resources:**
- `homer-local-tls` - For `homer.local.charn.io`
- `nextcloud-local-tls` - For `nextcloud.local.charn.io`
- One per service

**ClusterIssuer:** `letsencrypt-http-prod`

**Validity:** 90 days, auto-renewed by cert-manager

**Requirements:**
- Port 80 must be forwarded to Pi during renewal
- Let's Encrypt validates ownership by accessing `http://service.local.charn.io/.well-known/acme-challenge/`

---

## SSL/TLS Certificates

### Certificate Management Architecture

```
cert-manager (Kubernetes)
    ↓
ClusterIssuers (defines how to get certs)
    ├─ letsencrypt-cloudflare-prod (DNS-01)
    └─ letsencrypt-http-prod (HTTP-01)
    ↓
Certificates (requests for specific domains)
    ↓
Secrets (stores private keys and certificates)
    ↓
Ingress Resources (use the certificates)
```

### ClusterIssuers

#### DNS-01 (Cloudflare) - For Wildcard Certs

**Use case:** External access, wildcard domains

**File:** `hybrid-wildcard-certificates.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-cloudflare-prod
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

**Requirements:**
- Cloudflare API token with DNS edit permissions
- Token stored in secret: `cloudflare-api-token`

**Advantages:**
- Can create wildcard certificates
- No need to expose port 80
- Works for internal domains

**Disadvantages:**
- Requires Cloudflare API access
- Only works for domains on Cloudflare

#### HTTP-01 - For Individual Certs

**Use case:** Local access, individual domains

**File:** `local-ingresses-http01.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-http-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Requirements:**
- Port 80 accessible from internet
- DNS must resolve to your public IP
- Ingress must route challenge requests

**Advantages:**
- No API tokens needed
- Works with any domain
- Simple setup

**Disadvantages:**
- Can't create wildcard certificates
- Port 80 must be open
- One cert per domain

### Certificate Lifecycle

**Creation:**
1. Create Ingress with `cert-manager.io/cluster-issuer` annotation
2. cert-manager sees the annotation
3. Creates Certificate resource
4. Initiates challenge with Let's Encrypt
5. Validates domain ownership
6. Receives certificate
7. Stores in Secret
8. Ingress uses the Secret

**Renewal:**
- Automatic at 30 days before expiry
- cert-manager handles entire process
- Zero downtime

**Monitoring:**
```bash
# View all certificates
kubectl get certificate --all-namespaces

# Check certificate status
kubectl describe certificate <name> -n <namespace>

# View certificate details
kubectl get secret <secret-name> -n <namespace> -o yaml
```

### Certificate Sharing

Wildcard certificates are created once and shared across namespaces:

```bash
# Original in cert-manager namespace
kubectl get secret charn-io-wildcard-tls -n cert-manager

# Copied to application namespaces
kubectl get secret charn-io-wildcard-tls -n homer
kubectl get secret charn-io-wildcard-tls -n nextcloud
# ... etc
```

**Copy script:** `copy-certificates.sh`

```bash
#!/bin/bash
# Copies wildcard cert to all namespaces

NAMESPACES="homer nextcloud jellyfin homeassistant grafana monitoring wallabag"

for ns in $NAMESPACES; do
    kubectl get secret charn-io-wildcard-tls -n cert-manager -o yaml | \
      sed "s/namespace: cert-manager/namespace: $ns/" | \
      kubectl apply -f -
done
```

---

## Nginx Ingress Controller

### Role

Nginx Ingress acts as a reverse proxy and load balancer for the cluster:
- Routes traffic based on hostname
- Terminates SSL/TLS connections
- Handles HTTP/HTTPS
- Serves as entry point for all services

### Deployment

**Namespace:** `ingress-nginx`

**Ports:**
- `30280` - HTTP (NodePort)
- `30443` - HTTPS (NodePort)

**Key Configuration:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # CRITICAL: Disable global SSL redirect
  ssl-redirect: "false"
  force-ssl-redirect: "false"
  
  # Trust Cloudflare IPs for X-Forwarded-* headers
  use-forwarded-headers: "true"
  compute-full-forwarded-for: "true"
  
  # Cloudflare IP ranges (for real IP detection)
  proxy-real-ip-cidr: "173.245.48.0/20,103.21.244.0/22,..."
```

### Why ssl-redirect: "false"?

**Critical Setting Explained:**

With Cloudflare Tunnel, external traffic arrives as **HTTP** (not HTTPS) at Nginx because:
1. Cloudflare terminates the HTTPS connection
2. Tunnel sends HTTP to localhost:30280
3. Nginx receives HTTP

If `ssl-redirect: "true"`:
```
Cloudflare → HTTP → Nginx → 308 Redirect to HTTPS → 
Cloudflare → HTTP → Nginx → 308 Redirect → LOOP!
```

With `ssl-redirect: "false"`:
```
Cloudflare → HTTP → Nginx → Service → Success!
```

**Security:** Not compromised because:
- External: Cloudflare enforces HTTPS before tunnel
- Local: Direct HTTPS to port 30443
- Tunnel: Encrypted connection

### Ingress Resources

#### External Ingress Pattern

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homer-external
  namespace: homer
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"  # Important!
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homer.charn.io
    secretName: charn-io-wildcard-tls  # Shared wildcard cert
  rules:
  - host: homer.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: homer
            port:
              number: 8080
```

**Key Points:**
- Uses wildcard certificate
- `force-ssl-redirect: "false"` to prevent redirect loops
- Routes based on hostname

#### Local Ingress Pattern

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homer-local
  namespace: homer
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-http-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homer.local.charn.io
    secretName: homer-local-tls  # Individual cert
  rules:
  - host: homer.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: homer
            port:
              number: 8080
```

**Key Points:**
- Individual certificate per service
- Same backend as external ingress
- Port 80 must be open for initial cert issuance

---

## DNS Configuration

### External DNS (Cloudflare)

**Domain:** charn.io, charno.net

**Record Type:** CNAME

**Example records:**
```
homer.charn.io      → <tunnel-id>.cfargotunnel.com
nextcloud.charn.io  → <tunnel-id>.cfargotunnel.com
charno.net          → <tunnel-id>.cfargotunnel.com
```

**Created via:**
```bash
cloudflared tunnel route dns pi-hybrid homer.charn.io
```

**TTL:** Auto (300 seconds typical)

**Proxied:** Yes (Cloudflare proxy enabled - orange cloud)

### Local DNS

**Domain:** local.charn.io

**Options:**

#### Option A: Router DNS Override
Most routers support custom DNS entries:
```
*.local.charn.io → 192.168.0.23
```

#### Option B: Pi-hole or AdGuard Home
```
# Local DNS record
(^|\.)local\.charn\.io$ → 192.168.0.23
```

#### Option C: Hosts File
Each device needs entries:
```
192.168.0.23  homer.local.charn.io
192.168.0.23  nextcloud.local.charn.io
192.168.0.23  jellyfin.local.charn.io
```

**Recommendation:** Option A (router DNS) - Set once, works for all devices

---

## Application Configuration

### Dual-Domain Support

Applications must be configured to work with **both** external and local domains.

### Configuration Pattern

Most web applications need to know:
1. Which domains to trust
2. What protocol to use (HTTPS)
3. Which proxies to trust

### Application-Specific Settings

#### Nextcloud

```yaml
env:
- name: NEXTCLOUD_TRUSTED_DOMAINS
  value: "nextcloud.charn.io nextcloud.local.charn.io localhost"
- name: OVERWRITEPROTOCOL
  value: "https"
- name: TRUSTED_PROXIES
  value: "10.42.0.0/16"  # Kubernetes pod network
```

**Notes:**
- No `OVERWRITEHOST` - allows auto-detection
- Trusts both domains
- Always uses HTTPS protocol

#### Home Assistant

**configuration.yaml:**
```yaml
homeassistant:
  external_url: https://home.charn.io
  internal_url: https://home.local.charn.io

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.42.0.0/16
```

**Notes:**
- Explicitly sets both URLs
- Trusts proxy headers from Kubernetes

#### Wallabag

```yaml
env:
- name: SYMFONY__ENV__DOMAIN_NAME
  value: "https://wallabag.charn.io"
```

**Notes:**
- Uses primary domain
- Works with both but generates URLs for external

#### Grafana

```yaml
env:
- name: GF_SERVER_ROOT_URL
  value: "%(protocol)s://%(domain)s/"
- name: GF_SERVER_DOMAIN
  value: "grafana.charn.io"
```

**Notes:**
- Auto-detects domain from request
- `%(domain)s` is Grafana syntax for variable substitution

### How Auto-Detection Works

When configured properly:

```
Request: https://nextcloud.charn.io
  ↓
Nginx adds headers:
  X-Forwarded-Host: nextcloud.charn.io
  X-Forwarded-Proto: https
  ↓
Nextcloud reads headers
  ↓
Generates URLs: https://nextcloud.charn.io/...
```

```
Request: https://nextcloud.local.charn.io
  ↓
Nginx adds headers:
  X-Forwarded-Host: nextcloud.local.charn.io
  X-Forwarded-Proto: https
  ↓
Nextcloud reads headers
  ↓
Generates URLs: https://nextcloud.local.charn.io/...
```

**Result:** Same app, correct URLs for each domain!

---

## Troubleshooting

### External Access Issues

#### Symptom: ERR_NAME_NOT_RESOLVED

**Cause:** DNS not configured

**Fix:**
```bash
# Add DNS record
cloudflared tunnel route dns pi-hybrid service.charn.io

# Verify
nslookup service.charn.io
```

#### Symptom: 308 Redirect Loop

**Cause:** `ssl-redirect: "true"` in Nginx config

**Fix:**
```bash
# Check config
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml

# Should show ssl-redirect: "false"
# If not, update and restart
kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
  --type merge -p '{"data":{"ssl-redirect":"false"}}'

kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

#### Symptom: App returns internal IPs in redirects

**Cause:** App not configured with external domain

**Fix:**
```bash
# Example for Nextcloud
kubectl set env deployment/nextcloud -n nextcloud \
  OVERWRITEPROTOCOL="https" \
  NEXTCLOUD_TRUSTED_DOMAINS="nextcloud.charn.io,nextcloud.local.charn.io"
```

### Local Access Issues

#### Symptom: Certificate not issuing

**Cause:** Port 80 not accessible

**Fix:**
```bash
# 1. Verify port forwarding in router
# 2. Test from external network
curl -I http://your-public-ip:80

# 3. Check challenge
kubectl get challenge --all-namespaces
kubectl describe challenge <name> -n <namespace>
```

#### Symptom: Browser shows "Not Secure"

**Cause:** Certificate not valid yet

**Fix:**
```bash
# Check certificate status
kubectl get certificate -n <namespace>

# If pending, wait 2-5 minutes
# If failed, check challenge
kubectl describe certificate <name> -n <namespace>
```

### General Debugging

#### Check Nginx Ingress Logs

```bash
kubectl logs -n ingress-nginx \
  -l app.kubernetes.io/component=controller \
  -f
```

Look for:
- 404s: Ingress not found for hostname
- 502s: Backend not responding
- 308s: Redirect loop

#### Check cert-manager Logs

```bash
kubectl logs -n cert-manager \
  -l app=cert-manager \
  -f
```

Look for:
- Challenge failures
- DNS validation issues
- Rate limit errors

#### Check Cloudflare Tunnel

```bash
# Status
sudo systemctl status cloudflared

# Logs
sudo journalctl -u cloudflared -f
```

Look for:
- Connection established
- Routes registered
- Errors connecting to services

#### Test Connectivity

```bash
# Local test (bypass tunnel)
curl -I http://localhost:30280 -H 'Host: service.charn.io'

# Should return 200 or redirect, not 400/500
```

---

## Security Considerations

### Cloudflare Protection

External access benefits from:
- DDoS mitigation
- Bot protection
- Web Application Firewall (WAF)
- Rate limiting
- IP reputation filtering

### Network Segmentation

- **Cloudflare Tunnel:** Only outbound connection from Pi to Cloudflare
- **No inbound ports:** Except for local access (443)
- **Tunnel is encrypted:** TLS 1.3 between cloudflared and Cloudflare

### Certificate Security

- **Private keys:** Stored as Kubernetes Secrets
- **Automatic rotation:** Every 60 days (Let's Encrypt renews at 30 days before expiry)
- **No self-signed certs:** All from trusted CA (Let's Encrypt)

### Application Security

**Best Practices Implemented:**
1. Apps trust specific proxy CIDR (10.42.0.0/16)
2. CSRF protection configured
3. Trusted domains explicitly listed
4. HTTPS enforced by Cloudflare (external)
5. HTTPS available for local access

### Recommendations

**Enable:**
- Fail2ban on Pi (optional)
- Regular updates (`apt update && apt upgrade`)
- Monitoring (Prometheus + Grafana already deployed)

**Disable:**
- SSH password auth (use keys only)
- Unnecessary services on Pi

**Monitor:**
- Cloudflare analytics
- Nginx access logs
- Application logs for suspicious activity

---

## Maintenance

### Regular Tasks

**Weekly:**
- Check certificate status: `kubectl get certificate --all-namespaces`
- Review Cloudflare analytics
- Check resource usage: `kubectl top nodes`

**Monthly:**
- Update Pi OS: `sudo apt update && sudo apt upgrade`
- Review application logs for errors
- Test disaster recovery backups

**As Needed:**
- Add new services to tunnel config
- Update DNS records
- Rotate secrets/passwords

### Adding New Service

**Complete Checklist:**

1. **Deploy application** to K3s
   ```bash
   kubectl create namespace newapp
   kubectl apply -f newapp-deployment.yaml
   ```

2. **Create service**
   ```bash
   kubectl apply -f newapp-service.yaml
   ```

3. **Create external ingress**
   ```yaml
   # Use charn-io-wildcard-tls
   # Set force-ssl-redirect: "false"
   # Host: newapp.charn.io
   ```

4. **Create local ingress** (optional)
   ```yaml
   # Use HTTP-01 challenge
   # Host: newapp.local.charn.io
   ```

5. **Add to Cloudflare Tunnel**
   ```bash
   # Edit config
   sudo nano /etc/cloudflared/config.yml
   
   # Add:
   # - hostname: newapp.charn.io
   #   service: http://localhost:30280
   
   # Restart
   sudo systemctl restart cloudflared
   ```

6. **Add DNS record**
   ```bash
   cloudflared tunnel route dns pi-hybrid newapp.charn.io
   ```

7. **Configure application**
   ```bash
   # Set ALLOWED_HOSTS, trusted domains, etc.
   ```

8. **Test**
   ```bash
   # External
   curl -I https://newapp.charn.io
   
   # Local (if configured)
   curl -I https://newapp.local.charn.io
   ```

9. **Add to Homer dashboard**
   ```bash
   kubectl edit configmap homer-config -n homer
   ```

---

## Configuration Files Reference

### Key Files Locations

**On Raspberry Pi:**
```
/etc/cloudflared/config.yml          # Cloudflare Tunnel config
/root/.cloudflared/<id>.json         # Tunnel credentials
/etc/systemd/system/cloudflared.service  # Service file
```

**In Kubernetes:**
```
Namespace: ingress-nginx
  - ConfigMap: ingress-nginx-controller
  - Deployment: ingress-nginx-controller

Namespace: cert-manager
  - ClusterIssuer: letsencrypt-cloudflare-prod
  - ClusterIssuer: letsencrypt-http-prod
  - Secret: cloudflare-api-token
  - Secret: charn-io-wildcard-tls
  - Secret: charno-net-wildcard-tls

Namespace: <app>
  - Ingress: <app>-external
  - Ingress: <app>-local (optional)
  - Secret: charn-io-wildcard-tls (copied)
  - Secret: <app>-local-tls (if using HTTP-01)
```

### Configuration Scripts

**Created during setup:**
- `copy-certificates.sh` - Copy wildcard certs to namespaces
- `fix-nginx-redirect.sh` - Fix 308 redirect loops
- `configure-apps-dual-domain.sh` - Configure apps for both domains

**Created for troubleshooting:**
- `diagnose-*.sh` - Various diagnostic scripts
- `fix-*.sh` - Various fix scripts

---

## Performance Considerations

### Cloudflare Tunnel

**Latency:**
- Adds ~20-50ms (routing through Cloudflare edge)
- Minimal impact for web applications
- Consider local access for latency-sensitive apps

**Bandwidth:**
- No limits from Cloudflare for normal use
- Sufficient for home use cases

### Local Access

**Latency:**
- <5ms (local network)
- Direct connection

**Bandwidth:**
- Limited by local network (usually 1Gbps)
- Much faster than internet connection

### Recommendation

- **Media streaming:** Use local access (jellyfin.local.charn.io)
- **File sync:** Use local access when home
- **Remote access:** Use external (nextcloud.charn.io)
- **Public services:** Use external only

---

## Summary

### What We Built

A production-grade hybrid access system providing:
- ✅ Secure external access via Cloudflare Tunnel
- ✅ High-performance local access via direct connection
- ✅ Valid SSL certificates for all services
- ✅ No exposed ports (except 443 for local HTTPS)
- ✅ Automatic certificate renewal
- ✅ DDoS protection and WAF
- ✅ Same applications accessible both ways

### Key Innovations

1. **No global SSL redirect:** Allows tunnel HTTP traffic
2. **Dual-domain support:** Apps work with both URLs
3. **Shared wildcard certs:** Efficient certificate management
4. **Separate challenges:** DNS-01 for external, HTTP-01 for local

### System Reliability

**Single Points of Failure:**
- Raspberry Pi hardware
- Home internet connection (for tunnel)
- Cloudflare service (for external access)

**Mitigation:**
- Local access works even if internet is down
- Cloudflare has 99.99%+ uptime
- Can restore from backups if Pi fails

### Future Enhancements

**Possible Improvements:**
- Add multiple nodes to K3s (high availability)
- Implement automatic backups to cloud storage
- Add more monitoring and alerting
- Implement GitOps for configuration management
- Add staging environment

---

## Appendix: Quick Reference

### Common Commands

```bash
# Cloudflare Tunnel
sudo systemctl restart cloudflared
cloudflared tunnel route dns pi-hybrid <hostname>
sudo journalctl -u cloudflared -f

# Certificates
kubectl get certificate --all-namespaces
kubectl describe certificate <name> -n <namespace>

# Ingress
kubectl get ingress --all-namespaces
kubectl describe ingress <name> -n <namespace>

# Nginx Ingress
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

# Testing
curl -I http://localhost:30280 -H 'Host: service.charn.io'
curl -I https://service.charn.io
```

### URLs Quick Reference

**External (from anywhere):**
- https://homer.charn.io
- https://nextcloud.charn.io
- https://jellyfin.charn.io
- https://home.charn.io
- https://grafana.charn.io
- https://prometheus.charn.io
- https://wallabag.charn.io
- https://charno.net

**Local (home network only):**
- https://homer.local.charn.io
- https://nextcloud.local.charn.io
- https://jellyfin.local.charn.io
- (Configure as needed)

---

**Document Version:** 1.0  
**Created:** November 2025  
**Platform:** Raspberry Pi 4 + K3s  
**Status:** Production Ready