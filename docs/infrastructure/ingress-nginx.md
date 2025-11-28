# Nginx Ingress Controller

Nginx Ingress Controller for managing HTTP/HTTPS access to K3s services with custom configuration for hybrid network access (Cloudflare Tunnel + local).

## Overview

**Why Nginx Ingress?**
- Industry standard ingress controller
- Better performance than Traefik for this use case
- Excellent support for custom configurations
- Compatible with K3s (replaces default Traefik)

## Critical Configuration

This installation includes a **critical ConfigMap** that prevents 308 redirect loops when using Cloudflare Tunnel:

```yaml
ssl-redirect: "false"
force-ssl-redirect: "false"
```

**Why this is required:**
1. Cloudflare terminates HTTPS at their edge
2. Cloudflare sends HTTP to the tunnel (localhost:30280)
3. If Nginx redirects HTTP → HTTPS, it creates an infinite loop
4. Security is maintained: Cloudflare enforces HTTPS externally

## Installation

**Prerequisites:**
- K3s installed with Traefik disabled
- kubectl configured

**Recommended Method (Script):**
```bash
# From repository root
bash infrastructure/ingress-nginx/install.sh
```

This script:
1. Installs official Nginx Ingress (v1.9.5)
2. Applies custom ConfigMap
3. Configures fixed NodePorts (30280 HTTP, 30443 HTTPS)
4. Restarts controller to apply config

**Manual Method:**
```bash
# 1. Install official Nginx Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/baremetal/deploy.yaml

# 2. Wait for ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# 3. Apply custom ConfigMap
kubectl apply -f infrastructure/ingress-nginx/configmap.yaml

# 4. Patch NodePorts
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30280}]'

kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/1/nodePort", "value":30443}]'

# 5. Restart controller
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

## Verification

**Check installation:**
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml
```

**Verify NodePorts:**
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Should show:
# PORT(S): 80:30280/TCP,443:30443/TCP
```

**Test HTTP access:**
```bash
curl -I http://PI_IP:30280
# Should return 404 (no ingress configured yet)
```

## Network Architecture

### External Access (Cloudflare Tunnel)
```
User → HTTPS → Cloudflare Edge
→ Encrypted Tunnel → cloudflared (Pi)
→ HTTP localhost:30280 → Nginx Ingress
→ Application pods
```

**Key point:** Traffic arrives as HTTP from cloudflared

### Local Access (Direct)
```
User → HTTPS:443 → Router (port forward)
→ HTTPS:30443 → Nginx Ingress
→ Application pods
```

**Key point:** Traffic arrives as HTTPS directly

## Configuration Details

### ConfigMap Settings

**Critical settings:**
- `ssl-redirect: "false"` - No global redirect (prevents 308 loops)
- `force-ssl-redirect: "false"` - No forced redirect
- `use-forwarded-headers: "true"` - Trust X-Forwarded headers from Cloudflare
- `proxy-real-ip-cidr` - Cloudflare IP ranges for real client IP

**Performance settings:**
- `worker-processes: "2"` - Optimized for Pi 4 (4 cores)
- `max-worker-connections: "2048"` - Reasonable for homelab
- Buffer sizes tuned for typical requests

**Security settings:**
- `server-tokens: "false"` - Hide Nginx version
- Real IP detection from Cloudflare
- Custom log format for debugging

### Per-Ingress SSL Redirect

Individual ingresses can still enforce HTTPS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"  # Per-ingress override
```

**Use this for:**
- Local ingresses (*.local.charn.io) - they receive HTTPS
- Any service that should force HTTPS

## NodePort Configuration

Fixed NodePorts for consistent access:

| Service | Port | NodePort | Use |
|---------|------|----------|-----|
| HTTP | 80 | 30280 | Cloudflare Tunnel, HTTP redirects |
| HTTPS | 443 | 30443 | Local access, direct HTTPS |

**Router configuration:**
- External → 443 → Pi:30443 (for local access)
- No need to forward port 80 (Cloudflare handles external)

## Creating Ingress Resources

**Example ingress (external via Cloudflare):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-external
  namespace: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # Critical for Cloudflare
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: myapp.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

**Example ingress (local direct access):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-local
  namespace: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"  # OK for local (already HTTPS)
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: myapp.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

## Troubleshooting

**308 Redirect Loop:**
```bash
# Check ConfigMap
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep ssl-redirect
# Should show: ssl-redirect: "false"

# If not set, apply ConfigMap and restart
kubectl apply -f infrastructure/ingress-nginx/configmap.yaml
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

**Ingress not working:**
```bash
# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Check ingress status
kubectl get ingress -A
kubectl describe ingress INGRESS_NAME -n NAMESPACE

# Check endpoints
kubectl get endpoints -A
```

**404 errors:**
```bash
# Verify service exists
kubectl get svc -n NAMESPACE

# Check ingress backend
kubectl describe ingress INGRESS_NAME -n NAMESPACE | grep Backend

# Test service directly
kubectl port-forward svc/SERVICE_NAME -n NAMESPACE 8080:80
curl http://localhost:8080
```

**Certificate issues:**
```bash
# Check if secret exists
kubectl get secret SECRET_NAME -n NAMESPACE

# See cert-manager section for certificate troubleshooting
```

## Monitoring

**View logs:**
```bash
kubectl logs -f -n ingress-nginx -l app.kubernetes.io/component=controller
```

**Check metrics:**
```bash
# Prometheus scrapes Nginx metrics automatically
# View in Grafana: Import dashboard 9614 (Nginx Ingress Controller)
```

**Resource usage:**
```bash
kubectl top pod -n ingress-nginx
```

## Maintenance

**Update Nginx Ingress:**
```bash
# 1. Check current version
kubectl get deployment -n ingress-nginx ingress-nginx-controller -o yaml | grep image:

# 2. Update to new version
NEW_VERSION="v1.10.0"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NEW_VERSION}/deploy/static/provider/baremetal/deploy.yaml

# 3. Reapply custom ConfigMap
kubectl apply -f infrastructure/ingress-nginx/configmap.yaml

# 4. Verify
kubectl get pods -n ingress-nginx
```

**Restart controller:**
```bash
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

## Files

- `namespace.yaml` - Ingress namespace
- `configmap.yaml` - **Critical custom configuration**
- `deployment.yaml` - Service with fixed NodePorts
- `install.sh` - Automated installation script
- `kustomization.yaml` - Kustomize configuration

## References

- [Nginx Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Nginx Ingress GitHub](https://github.com/kubernetes/ingress-nginx)
- [ConfigMap Options](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/)
- [Annotations Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
