# Homer Dashboard Setup Documentation

## Overview

Homer is a static dashboard application that provides a central access point for all homelab services. This deployment runs on K3s on a Raspberry Pi 4.

**Current Status:** Production deployment with external and local HTTPS access

## Deployment History

### Version 1: Initial NodePort Deployment

**Configuration:**
```yaml
Service: NodePort 30800
Storage: ConfigMap only (no PVC)
Access: http://<PI_IP>:30800
```

**Features:**
- Lightweight static site (32Mi RAM, 10m CPU)
- Configuration via ConfigMap
- Organized service tiles by category
- Light/dark theme support

### Version 2: Current Ingress-Based Deployment

**What Changed:** Added HTTPS ingress for external and local access

**Configuration:**
```yaml
Ingress:
  External:
    - Host: homer.charn.io
    - TLS: Let's Encrypt via Cloudflare

  Local:
    - Host: homer.local.charn.io
    - TLS: Local wildcard certificate

Resources:
  Requests: 10m CPU, 32Mi RAM
  Limits: 100m CPU, 128Mi RAM
```

**Benefits:**
- Secure HTTPS access from anywhere
- Fast local access when at home
- Professional appearance
- Extremely lightweight

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    External Access                          │
│                                                             │
│  Internet → Cloudflare Tunnel → HTTP → Nginx Ingress       │
│             (homer.charn.io)             ↓                  │
│                                          ↓                  │
│                    Local Access          ↓                  │
│                                          ↓                  │
│  Home Network → HTTPS → Nginx Ingress → Homer Pod          │
│  (homer.local.charn.io)                  ↓                  │
│                                          ↓                  │
│                                    ┌─────────────┐          │
│                                    │   Homer     │          │
│                                    │  Container  │          │
│                                    │    :8080    │          │
│                                    └─────────────┘          │
│                                          │                  │
│                                    ┌─────▼──────┐           │
│                                    │ ConfigMap  │           │
│                                    │ (config.yml)│          │
│                                    └────────────┘           │
│                                                             │
│          NodePort Backup: http://<PI_IP>:30800             │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

Homer configuration is stored in a ConfigMap (`homer-config`):

### Config Structure

```yaml
title: "K3s Home Lab"
subtitle: "Pi 4 Cluster Dashboard"

theme: default  # Supports light/dark mode

links:
  - External reference links

services:
  - name: "Category Name"
    icon: "fas fa-icon"
    items:
      - name: "Service Name"
        subtitle: "Description"
        tag: "category"
        url: "https://service.charn.io"
```

### Editing Configuration

```bash
# Edit ConfigMap
kubectl edit configmap homer-config -n homer

# Apply changes (restart pod)
kubectl rollout restart deployment/homer -n homer

# View current config
kubectl get configmap homer-config -n homer -o yaml
```

### Adding New Services

Add to the `services` section in ConfigMap:

```yaml
- name: "New Service"
  subtitle: "Description"
  tag: "category"
  url: "https://newservice.charn.io"
  target: "_blank"
```

## Customization

### Themes

Homer supports custom themes via the `colors` section:

```yaml
colors:
  light:
    highlight-primary: "#3367d6"
    background: "#f5f5f5"
  dark:
    background: "#131313"
    card-background: "#2b2b2b"
```

### Icons

Use Font Awesome icons:
```yaml
icon: "fas fa-server"  # Category icon
logo: "assets/icons/app.png"  # App logo
```

### Custom CSS

For advanced customization, mount custom CSS:
```bash
# Add to deployment volumeMounts
- name: custom-css
  mountPath: /www/assets/custom.css
  subPath: custom.css
```

## Troubleshooting

### Pod Not Starting

**Check ConfigMap:**
```bash
kubectl get configmap homer-config -n homer
kubectl describe configmap homer-config -n homer
```

**Common Issues:**
- Invalid YAML in config.yml
- Missing indentation
- Special characters not escaped

**Fix:**
```bash
# Edit and fix YAML
kubectl edit configmap homer-config -n homer
kubectl rollout restart deployment/homer -n homer
```

### Dashboard Not Loading

**Test pod access:**
```bash
kubectl port-forward -n homer deployment/homer 8080:8080
# Visit http://localhost:8080
```

**Check logs:**
```bash
kubectl logs -n homer -l app=homer
```

### Links Not Working

Verify URLs in ConfigMap are correct:
```bash
kubectl get configmap homer-config -n homer -o yaml | grep url
```

## Resource Usage

Homer is extremely lightweight:

```yaml
resources:
  requests:
    cpu: 10m      # 0.01 cores
    memory: 32Mi  # 32 megabytes
  limits:
    cpu: 100m     # 0.1 cores max
    memory: 128Mi # 128 megabytes max
```

**Typical Usage:**
- CPU: 1-5m (idle)
- Memory: 20-40Mi
- No storage needed (static files in container)

## Common Operations

### Update Configuration

```bash
# Method 1: Edit directly
kubectl edit configmap homer-config -n homer
kubectl rollout restart deployment/homer -n homer

# Method 2: Replace from file
kubectl create configmap homer-config -n homer \
  --from-file=config.yml=./new-config.yml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/homer -n homer
```

### Restart Homer

```bash
kubectl rollout restart -n homer deployment/homer
```

### View Logs

```bash
kubectl logs -f -n homer -l app=homer
```

### Update Image

```bash
kubectl set image deployment/homer homer=b4bz/homer:latest -n homer
```

## Best Practices

1. **Keep Config Organized:** Group services by logical categories
2. **Use HTTPS URLs:** Always link to HTTPS versions of services
3. **Test After Changes:** Verify dashboard loads after config changes
4. **Backup ConfigMap:** Save config.yml before major changes
5. **Use Tags:** Add tags to categorize services (monitoring, media, etc.)

## Backup and Recovery

### Backup ConfigMap

```bash
# Export ConfigMap
kubectl get configmap homer-config -n homer -o yaml > homer-config-backup.yaml

# Or just the config.yml
kubectl get configmap homer-config -n homer -o jsonpath='{.data.config\.yml}' > config-backup.yml
```

### Restore ConfigMap

```bash
# From full backup
kubectl apply -f homer-config-backup.yaml

# From config.yml only
kubectl create configmap homer-config -n homer \
  --from-file=config.yml=config-backup.yml \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Lessons Learned

### 1. ConfigMap is All You Need
- No PVC required (static site)
- Configuration changes via ConfigMap only
- Pod restart required to apply changes

### 2. Extremely Lightweight
- Uses minimal resources (10m CPU, 32Mi RAM)
- Perfect for Raspberry Pi
- Can run alongside resource-intensive apps

### 3. Restart Required for Changes
- Homer doesn't hot-reload config
- Must restart pod after ConfigMap edits
- Takes only 5-10 seconds to restart

### 4. Perfect Home Page
- Set as browser home page for quick access
- Single dashboard for all services
- Light/dark mode auto-detection

## References

- **Homer GitHub:** https://github.com/bastienwirtz/homer
- **Docker Hub:** https://hub.docker.com/r/b4bz/homer
- **Demo:** https://homer-demo.netlify.app/
- **Icons:** https://fontawesome.com/icons
- **Themes:** https://github.com/bastienwirtz/homer/blob/main/docs/customservices.md

## Support

For issues specific to this deployment:
- Check logs: `kubectl logs -n homer -l app=homer`
- Review ConfigMap: `kubectl get configmap homer-config -n homer -o yaml`
- Verify pod status: `kubectl get pods -n homer`

For Homer application issues:
- GitHub Issues: https://github.com/bastienwirtz/homer/issues
- Documentation: https://github.com/bastienwirtz/homer/tree/main/docs
