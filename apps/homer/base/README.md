# Homer Dashboard

Central dashboard for accessing all homelab applications.

**Status:** Production deployment on K3s (Raspberry Pi 4)
**Access:** https://homer.charn.io (external) | https://homer.local.charn.io (local)

## Quick Start

```bash
# Deploy Homer
bash apps/homer/base/install.sh

# Or manually
kubectl apply -k apps/homer/base/

# Monitor startup (very fast - ~10 seconds)
kubectl logs -f -n homer -l app=homer
```

## Access URLs

- **External:** https://homer.charn.io (via Cloudflare Tunnel)
- **Local:** https://homer.local.charn.io (faster when at home)
- **NodePort:** http://192.168.0.23:30800 (testing only)

## Configuration

Homer configuration is stored in a ConfigMap. The dashboard layout, services, and theme are all configured via YAML.

### Edit Configuration

```bash
# Edit the dashboard config
kubectl edit configmap homer-config -n homer

# Apply changes (restart required)
kubectl rollout restart deployment/homer -n homer
```

### View Current Config

```bash
kubectl get configmap homer-config -n homer -o yaml
```

### Configuration Structure

```yaml
services:
  - name: "Category Name"
    icon: "fas fa-icon"
    items:
      - name: "Service Name"
        subtitle: "Description"
        url: "https://service.charn.io"
        tag: "category"
```

## Adding New Services

Edit the ConfigMap and add to the `services` section:

```bash
kubectl edit configmap homer-config -n homer
# Add your service under appropriate category
kubectl rollout restart deployment/homer -n homer
```

Example service entry:
```yaml
- name: "My New App"
  subtitle: "App description"
  tag: "category"
  url: "https://newapp.charn.io"
  target: "_blank"
```

## Common Operations

```bash
# View logs
kubectl logs -f -n homer -l app=homer

# Check status
kubectl get pods,configmap,ingress -n homer

# Restart Homer (apply config changes)
kubectl rollout restart deployment/homer -n homer

# Update image
kubectl set image deployment/homer homer=b4bz/homer:latest -n homer
```

## Themes

Homer supports light and dark modes. Theme is configured in the ConfigMap:

```yaml
theme: default  # Auto-detect based on browser preference

colors:
  light:
    highlight-primary: "#3367d6"
    background: "#f5f5f5"
  dark:
    background: "#131313"
    card-background: "#2b2b2b"
```

## Backup Configuration

```bash
# Backup ConfigMap
kubectl get configmap homer-config -n homer -o yaml > homer-config-backup.yaml

# Or just the config.yml
kubectl get configmap homer-config -n homer -o jsonpath='{.data.config\.yml}' > config-backup.yml

# Restore
kubectl apply -f homer-config-backup.yaml
kubectl rollout restart deployment/homer -n homer
```

## Troubleshooting

### Dashboard Not Loading

Check pod status:
```bash
kubectl get pods -n homer
kubectl logs -n homer -l app=homer
```

### Invalid Configuration

If Homer won't start after config change:
```bash
# Check ConfigMap YAML syntax
kubectl get configmap homer-config -n homer -o yaml

# Restore from backup if needed
kubectl apply -f homer-config-backup.yaml
kubectl rollout restart deployment/homer -n homer
```

### Services Not Appearing

Verify ConfigMap was updated:
```bash
kubectl get configmap homer-config -n homer -o jsonpath='{.data.config\.yml}'
```

Remember to restart after editing:
```bash
kubectl rollout restart deployment/homer -n homer
```

## Resources

- **CPU:** 10m request, 100m limit (extremely lightweight)
- **Memory:** 32Mi request, 128Mi limit
- **Storage:** None (ConfigMap only, no PVC)

## Documentation

- **Detailed Setup Guide:** [SETUP.md](SETUP.md)
- **Official Docs:** https://github.com/bastienwirtz/homer
- **Demo:** https://homer-demo.netlify.app/
- **Icons:** https://fontawesome.com/icons

## Related

- **Installation Script:** [install.sh](install.sh) - Automated deployment
- **ConfigMap:** [configmap.yaml](configmap.yaml) - Dashboard configuration
- **Manifests:** All Kubernetes manifests in this directory
- **Kustomize:** [kustomization.yaml](kustomization.yaml)

## Tips

- **Set as Home Page:** Bookmark https://homer.charn.io as your browser home page
- **Organize by Category:** Group related services together
- **Use Tags:** Add tags to services for visual categorization
- **Test URLs:** Verify all service URLs work before adding to dashboard
- **Backup Often:** Save ConfigMap before making major changes