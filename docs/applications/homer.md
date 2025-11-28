# Homer Dashboard

Central dashboard for the K3s homelab - provides quick access to all applications.

## Overview

**What is Homer?**
- Static web dashboard for organizing and accessing your homelab applications
- Lightweight (32MB RAM), fast, simple
- Configurable via YAML (no database needed)
- Beautiful, responsive UI with light/dark themes
- Search functionality and keyboard shortcuts

**Why Homer?**
- Single landing page for all services
- Organizes apps by category
- Shows both external and local URLs
- Easy to customize and maintain
- Very low resource usage

## Deployment

### Prerequisites

**Infrastructure:**
- ✅ K3s cluster running
- ✅ Nginx Ingress Controller installed
- ✅ cert-manager with wildcard certificates
- ✅ Cloudflare Tunnel configured (for external access)
- ✅ Local DNS configured (for *.local.charn.io)

**Certificates needed:**
- `charn-io-wildcard-tls` in homer namespace
- `local-charn-io-wildcard-tls` in homer namespace

### Deploy Homer

**Using Kustomize:**
```bash
# Deploy everything
kubectl apply -k applications/homer/

# Wait for ready
kubectl wait --for=condition=Ready pod -l app=homer -n homer --timeout=60s

# Check status
kubectl get all -n homer
```

**Manual deployment:**
```bash
# Apply resources in order
kubectl apply -f applications/homer/namespace.yaml
kubectl apply -f applications/homer/configmap.yaml
kubectl apply -f applications/homer/deployment.yaml
kubectl apply -f applications/homer/service.yaml

# Copy wildcard certificates to namespace
bash scripts/cert-manager/copy-certs-to-namespace.sh homer

# Apply ingresses
kubectl apply -f applications/homer/ingress-external.yaml
kubectl apply -f applications/homer/ingress-local.yaml
```

### Verify Deployment

```bash
# Check pod status
kubectl get pods -n homer
# Should show: homer-xxx Running

# Check service
kubectl get svc -n homer
# Should show: homer ClusterIP 8080

# Check ingresses
kubectl get ingress -n homer
# Should show: homer-external and homer-local

# Test service internally
kubectl run -it --rm test --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://homer.homer.svc.cluster.local:8080
# Should return HTML
```

## Access URLs

### External Access (from anywhere)
```
https://homer.charn.io
```
- Routed through Cloudflare Tunnel
- Works from any location
- DDoS protection and WAF
- Slightly higher latency

### Local Access (from home network)
```
https://homer.local.charn.io
```
- Direct connection to Pi
- Low latency, fast loading
- Works even if internet is down
- Best for daily use at home

## Configuration

### Edit Dashboard Config

**Option 1: Edit ConfigMap directly**
```bash
kubectl edit configmap homer-config -n homer
```

**Option 2: Edit local file and apply**
```bash
# Edit applications/homer/configmap.yaml
vim applications/homer/configmap.yaml

# Apply changes
kubectl apply -f applications/homer/configmap.yaml

# Restart Homer to reload config
kubectl rollout restart deployment homer -n homer
```

### Configuration Structure

**config.yml sections:**

**1. Header & Theme:**
```yaml
title: "K3s Home Lab"
subtitle: "Raspberry Pi 4 Cluster Dashboard"
logo: "assets/icons/kubernetes.png"
theme: default  # or sui, cosmo, etc.
colors:
  light: { ... }
  dark: { ... }
```

**2. Links (top right corner):**
```yaml
links:
  - name: "Documentation"
    icon: "fas fa-book"
    url: "https://docs.example.com"
    target: "_blank"
```

**3. Services (main content):**
```yaml
services:
  - name: "Category Name"
    icon: "fas fa-server"
    items:
      - name: "Application Name"
        logo: "URL_TO_ICON"
        subtitle: "Description"
        tag: "tag-name"
        keywords: "search keywords"
        url: "https://app.example.com"
        target: "_blank"
```

### Add New Application

**1. Edit ConfigMap:**
```bash
kubectl edit configmap homer-config -n homer
```

**2. Add under appropriate category:**
```yaml
services:
  - name: "Your Category"
    icon: "fas fa-icon"
    items:
      # Add your app here
      - name: "New App"
        logo: "https://url-to-icon.png"
        subtitle: "Description of app"
        tag: "category"
        keywords: "searchable keywords"
        url: "https://newapp.charn.io"
        target: "_blank"

      # Local version
      - name: "New App (Local)"
        logo: "https://url-to-icon.png"
        subtitle: "Description - Local Access"
        tag: "local"
        keywords: "searchable keywords local"
        url: "https://newapp.local.charn.io"
        target: "_blank"
```

**3. Restart Homer:**
```bash
kubectl rollout restart deployment homer -n homer
```

**4. Verify:**
```bash
# Check pod restarted
kubectl get pods -n homer

# Test in browser
curl -I https://homer.charn.io
```

### Icons

**Icon sources:**
- [Homer Icons Repository](https://github.com/NX211/homer-icons)
- [Font Awesome Icons](https://fontawesome.com/icons)
- Custom icons (base64 or URL)

**Example URLs:**
```yaml
# From homer-icons
logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/nextcloud.png"

# Font Awesome icon
icon: "fas fa-server"

# Custom URL
logo: "https://example.com/custom-icon.png"

# Base64 embedded
logo: "data:image/png;base64,iVBORw0KG..."
```

## Resource Usage

**CPU:**
- Requests: 10m (0.01 core)
- Limits: 100m (0.1 core)
- Typical: ~5m idle, ~20m when loading

**Memory:**
- Requests: 32Mi
- Limits: 128Mi
- Typical: ~40Mi

**Storage:**
- No persistent storage required
- Config stored in ConfigMap (~50KB)

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod -l app=homer -n homer

# Common issues:

# 1. Image pull error
# Check image exists
kubectl get deployment homer -n homer -o yaml | grep image:

# 2. ConfigMap not found
kubectl get configmap homer-config -n homer

# 3. Resource constraints
kubectl top pod -l app=homer -n homer
```

### Config Changes Not Applied

```bash
# Verify ConfigMap was updated
kubectl get configmap homer-config -n homer -o yaml

# Restart deployment to pick up changes
kubectl rollout restart deployment homer -n homer

# Watch restart
kubectl rollout status deployment homer -n homer

# Check logs
kubectl logs -l app=homer -n homer
```

### External URL Not Working

```bash
# Check ingress
kubectl describe ingress homer-external -n homer

# Verify certificate secret exists
kubectl get secret charn-io-wildcard-tls -n homer

# If missing, copy certificate
bash scripts/cert-manager/copy-certs-to-namespace.sh homer

# Check Cloudflare Tunnel includes homer.charn.io
sudo systemctl status cloudflared
sudo journalctl -u cloudflared | grep homer

# Test from external network
curl -I https://homer.charn.io
```

### Local URL Not Working

```bash
# Check local ingress
kubectl describe ingress homer-local -n homer

# Verify local certificate exists
kubectl get secret local-charn-io-wildcard-tls -n homer

# If missing, copy certificate
bash scripts/cert-manager/copy-certs-to-namespace.sh homer

# Check DNS resolution
nslookup homer.local.charn.io
# Should resolve to Pi's local IP

# Check port forwarding on router
# 443 → Pi:30443

# Test direct to NodePort
curl -k https://192.168.0.23:30443 -H "Host: homer.local.charn.io"
```

### Icons Not Loading

**Symptoms:**
- Broken image icons
- Console errors about CORS

**Causes & Fixes:**

**1. External icon URLs blocked**
```yaml
# Solution: Use icons from CDN that allows CORS
# Recommended: homer-icons repository
logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/app.png"
```

**2. Invalid icon URL**
```bash
# Test icon URL
curl -I "https://url-to-icon.png"
# Should return: 200 OK

# If 404, find alternative icon
```

**3. Network issues**
```bash
# Check from Homer pod
kubectl exec -it deployment/homer -n homer -- \
  wget -qO- https://raw.githubusercontent.com/NX211/homer-icons/master/png/nextcloud.png
```

### Dashboard Shows "Loading..."

```bash
# Check if Homer is serving files
kubectl logs -l app=homer -n homer

# Test service endpoint
kubectl run -it --rm test --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://homer.homer.svc.cluster.local:8080

# Check config.yml syntax
kubectl get configmap homer-config -n homer -o yaml | grep "config.yml"

# Common issues:
# - Invalid YAML syntax in config
# - Missing closing quotes
# - Incorrect indentation
```

## Customization Examples

### Change Theme

```yaml
# Edit ConfigMap
kubectl edit configmap homer-config -n homer

# Change theme
theme: sui  # Options: default, sui, cosmo

# Restart
kubectl rollout restart deployment homer -n homer
```

### Add Custom Message Banner

```yaml
# In config.yml
message:
  style: "is-info"  # Options: is-info, is-success, is-warning, is-danger
  title: "Welcome!"
  icon: "fa fa-info-circle"
  content: "This is your K3s homelab dashboard. Use local URLs for faster access when at home."
```

### Enable Search

```yaml
# In config.yml (root level)
search: true

# Users can now press 's' or '/' to search
# Searches across all service names, subtitles, and keywords
```

### Custom Colors

```yaml
colors:
  light:
    highlight-primary: "#ff6b6b"    # Red theme
    highlight-secondary: "#ee5a6f"
    highlight-hover: "#fa5252"
    # ... other colors
  dark:
    # ... dark theme colors
```

### Group Services by Tag

```yaml
# In services
items:
  - name: "Grafana"
    tag: "monitoring"  # Add tags
    # ...

  - name: "Prometheus"
    tag: "monitoring"  # Same tag groups together
    # ...
```

## Backup & Restore

### Backup Configuration

```bash
# Export ConfigMap
kubectl get configmap homer-config -n homer -o yaml > homer-config-backup.yaml

# Backup entire deployment
kubectl get deployment,service,ingress,configmap -n homer -o yaml > homer-full-backup.yaml

# Store securely
cp homer-*.yaml /mnt/k3s-storage/backups/
```

### Restore Configuration

```bash
# Restore from backup
kubectl apply -f homer-config-backup.yaml

# Restart to apply
kubectl rollout restart deployment homer -n homer

# Or restore entire namespace
kubectl apply -f homer-full-backup.yaml
```

## Monitoring

### Check Homer Health

```bash
# Pod status
kubectl get pods -n homer

# Service endpoints
kubectl get endpoints homer -n homer

# Resource usage
kubectl top pod -l app=homer -n homer

# Logs
kubectl logs -f -l app=homer -n homer
```

### Metrics

Homer itself doesn't expose metrics, but you can monitor via:

**1. Nginx Ingress metrics:**
```bash
# HTTP requests to homer.charn.io
# Response times
# Error rates
```

**2. Kubernetes metrics:**
```bash
# CPU/Memory usage
kubectl top pod -l app=homer -n homer

# Restart count
kubectl get pod -l app=homer -n homer -o json | \
  jq '.items[].status.containerStatuses[].restartCount'
```

## Security Considerations

**Current security:**
- ✅ Runs as non-root user (UID 1000)
- ✅ No privilege escalation
- ✅ Drops all capabilities
- ✅ Security headers (X-Frame-Options, CSP, etc.)
- ✅ HTTPS only (via Ingress)
- ⚠️  No authentication (relies on network security)

**Recommendations:**

**1. Add authentication (if needed):**
```yaml
# Option A: Nginx basic auth
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: homer-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"

# Create secret
htpasswd -c auth username
kubectl create secret generic homer-basic-auth --from-file=auth -n homer
```

**2. Use Cloudflare Access:**
- Add zero-trust authentication before reaching Homer
- Configure in Cloudflare dashboard
- Require Google/GitHub login

**3. Restrict by IP:**
```yaml
# In ingress annotations
nginx.ingress.kubernetes.io/whitelist-source-range: "192.168.0.0/24,10.0.0.0/8"
```

## Performance Tuning

### Enable Gzip Compression

```yaml
# In ingress annotations
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-gzip: "true"
    nginx.ingress.kubernetes.io/gzip-level: "6"
```

### Increase Replicas

```bash
# Scale for high availability
kubectl scale deployment homer -n homer --replicas=2

# Or edit deployment
kubectl edit deployment homer -n homer
# Change: replicas: 2
```

### Add Resource Limits

If Homer uses more resources than allocated:

```yaml
# In deployment.yaml
resources:
  requests:
    memory: "64Mi"   # Increased from 32Mi
    cpu: "20m"       # Increased from 10m
  limits:
    memory: "256Mi"  # Increased from 128Mi
    cpu: "200m"      # Increased from 100m
```

## Updating Homer

### Update to Latest Version

```bash
# Check current version
kubectl get deployment homer -n homer -o yaml | grep image:

# Update image tag in deployment.yaml
# Or use kubectl set image
kubectl set image deployment/homer homer=b4bz/homer:latest -n homer

# Watch rollout
kubectl rollout status deployment/homer -n homer

# Verify
kubectl get pods -n homer
```

### Rollback Update

```bash
# View rollout history
kubectl rollout history deployment/homer -n homer

# Rollback to previous version
kubectl rollout undo deployment/homer -n homer

# Rollback to specific revision
kubectl rollout undo deployment/homer -n homer --to-revision=2
```

## Files

- `namespace.yaml` - Homer namespace
- `configmap.yaml` - Dashboard configuration
- `deployment.yaml` - Homer deployment
- `service.yaml` - ClusterIP service
- `ingress-external.yaml` - External access ingress (*.charn.io)
- `ingress-local.yaml` - Local access ingress (*.local.charn.io)
- `kustomization.yaml` - Kustomize configuration
- `README.md` - This file

## References

- [Homer GitHub](https://github.com/bastienwirtz/homer)
- [Homer Documentation](https://github.com/bastienwirtz/homer/blob/main/docs/configuration.md)
- [Homer Icons Repository](https://github.com/NX211/homer-icons)
- [Font Awesome Icons](https://fontawesome.com/icons)

## Summary

**What You Have:**
- ✅ Central dashboard for all homelab apps
- ✅ External access via homer.charn.io
- ✅ Local access via homer.local.charn.io
- ✅ Organized by categories
- ✅ Light/dark theme support
- ✅ Search functionality
- ✅ Easy to customize (YAML config)
- ✅ Low resource usage (32MB RAM)

**Key Commands:**
```bash
# Deploy
kubectl apply -k applications/homer/

# Edit config
kubectl edit configmap homer-config -n homer

# Restart after config change
kubectl rollout restart deployment homer -n homer

# View logs
kubectl logs -f -l app=homer -n homer

# Check status
kubectl get all -n homer
```

**Access URLs:**
- External: https://homer.charn.io
- Local: https://homer.local.charn.io
