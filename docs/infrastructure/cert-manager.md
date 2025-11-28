# cert-manager

Automatic SSL/TLS certificate management using Let's Encrypt with Cloudflare DNS-01 challenges for wildcard certificates.

## Overview

**Why cert-manager?**
- Automatic certificate issuance and renewal
- DNS-01 challenge support for wildcard certificates
- Works with both external (Cloudflare Tunnel) and local access
- Integrates seamlessly with Kubernetes Ingress

## Architecture

This setup uses **DNS-01 challenges** via Cloudflare API:

1. cert-manager creates a DNS TXT record in Cloudflare
2. Let's Encrypt verifies the DNS record
3. Certificate is issued
4. Certificate stored as Kubernetes Secret
5. Auto-renewed 30 days before expiry

**Why DNS-01 instead of HTTP-01?**
- Allows wildcard certificates (`*.charn.io`)
- Works even when services aren't publicly accessible
- Single cert covers all subdomains
- Easier certificate management

## Wildcard Certificates

Three wildcard certificates are created:

| Certificate | Domains | Use |
|-------------|---------|-----|
| `charn-io-wildcard-tls` | `*.charn.io`, `charn.io` | External access via Cloudflare Tunnel |
| `local-charn-io-wildcard-tls` | `*.local.charn.io`, `local.charn.io` | Local network access |
| `charno-net-wildcard-tls` | `*.charno.net`, `charno.net` | Custom website domain |

## Installation

**Prerequisites:**
- K3s cluster running
- Cloudflare account with domains (charn.io, charno.net)
- Cloudflare API token with DNS:Edit permissions

### Step 1: Install cert-manager

```bash
# Option A: Use install script (recommended)
bash infrastructure/cert-manager/install.sh

# Option B: Manual installation
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for ready
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
```

### Step 2: Create Cloudflare API Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use "Edit zone DNS" template
4. Configure:
   - **Permissions:** Zone - DNS - Edit
   - **Zone Resources:**
     - Include - Specific zone - charn.io
     - Include - Specific zone - charno.net
5. Click "Continue to summary" → "Create Token"
6. **Copy the token** (you won't see it again!)

### Step 3: Create Secret

```bash
# Option A: Use helper script (recommended)
bash infrastructure/cert-manager/create-cloudflare-secret.sh

# Option B: Manual creation
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN \
  -n cert-manager
```

### Step 4: Apply ClusterIssuers

```bash
kubectl apply -f infrastructure/cert-manager/clusterissuers.yaml

# Verify
kubectl get clusterissuer
# Should show letsencrypt-cloudflare-prod and letsencrypt-cloudflare-staging
```

### Step 5: Apply Certificates

```bash
kubectl apply -f infrastructure/cert-manager/certificates.yaml

# Monitor issuance (takes 2-5 minutes)
kubectl get certificate -n cert-manager -w

# All should eventually show READY=True
```

## Verification

**Check certificate status:**
```bash
kubectl get certificate -n cert-manager
```

Expected output:
```
NAME                      READY   SECRET                        AGE
charn-io-wildcard         True    charn-io-wildcard-tls         5m
local-charn-io-wildcard   True    local-charn-io-wildcard-tls   5m
charno-net-wildcard       True    charno-net-wildcard-tls       5m
```

**Check certificate details:**
```bash
kubectl describe certificate charn-io-wildcard -n cert-manager
```

**View certificate secret:**
```bash
kubectl get secret charn-io-wildcard-tls -n cert-manager
```

**Check certificate expiry:**
```bash
kubectl get certificate charn-io-wildcard -n cert-manager -o jsonpath='{.status.notAfter}'
```

## Using Certificates in Ingresses

### Option 1: Copy Certificates to Application Namespace

```bash
# Copy all wildcard certs to a namespace
bash scripts/cert-manager/copy-certs-to-namespace.sh nextcloud
```

Then reference in ingress:
```yaml
spec:
  tls:
  - hosts:
    - nextcloud.charn.io
    secretName: charn-io-wildcard-tls  # Copied from cert-manager namespace
```

### Option 2: Create Certificate in Application Namespace (Recommended)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nextcloud-cert
  namespace: nextcloud
spec:
  secretName: nextcloud-tls
  issuerRef:
    name: letsencrypt-cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
  - nextcloud.charn.io
  - nextcloud.local.charn.io
```

Then reference in ingress:
```yaml
spec:
  tls:
  - hosts:
    - nextcloud.charn.io
    secretName: nextcloud-tls  # Created by Certificate resource
```

## Example Ingress with Certificate

**External access (Cloudflare Tunnel):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-external
  namespace: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
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

**Local access (direct):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-local
  namespace: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
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

### Certificate Not Issuing

**Check certificate status:**
```bash
kubectl describe certificate charn-io-wildcard -n cert-manager
```

**Check challenges:**
```bash
kubectl get challenge -n cert-manager
kubectl describe challenge -n cert-manager
```

**Common issues:**

1. **Invalid Cloudflare API token:**
```bash
# Verify secret exists
kubectl get secret cloudflare-api-token -n cert-manager

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

2. **DNS propagation delay:**
- DNS-01 challenges may take a few minutes
- Wait and check again

3. **Rate limits (production):**
```bash
# Use staging issuer for testing
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: cert-manager
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-cloudflare-staging
    kind: ClusterIssuer
  dnsNames:
  - test.charn.io
EOF
```

### Certificate Renewal Failed

```bash
# Check certificate status
kubectl describe certificate charn-io-wildcard -n cert-manager

# Force renewal
kubectl delete secret charn-io-wildcard-tls -n cert-manager
kubectl delete certificaterequest -n cert-manager --all

# cert-manager will automatically re-issue
```

### ClusterIssuer Not Ready

```bash
# Check ClusterIssuer status
kubectl describe clusterissuer letsencrypt-cloudflare-prod

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

## Monitoring

**View cert-manager logs:**
```bash
kubectl logs -f -n cert-manager -l app=cert-manager
```

**Check all certificates:**
```bash
kubectl get certificate --all-namespaces
```

**Certificate expiry monitoring:**
```bash
# Certificates auto-renew 30 days before expiry
# Monitor via Prometheus metrics (cert-manager exports metrics)

# Or check manually
for cert in $(kubectl get certificate -n cert-manager -o name); do
  echo "$cert:"
  kubectl get $cert -n cert-manager -o jsonpath='{.status.notAfter}{"\n"}'
done
```

## Maintenance

### Update cert-manager

```bash
# 1. Backup certificate resources
kubectl get certificate,clusterissuer --all-namespaces -o yaml > cert-manager-backup.yaml

# 2. Update to new version
NEW_VERSION="v1.14.0"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${NEW_VERSION}/cert-manager.yaml

# 3. Wait for rollout
kubectl rollout status deployment/cert-manager -n cert-manager

# 4. Verify
kubectl get pods -n cert-manager
```

### Rotate Cloudflare API Token

```bash
# 1. Create new token in Cloudflare dashboard
# 2. Update secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=NEW_TOKEN \
  -n cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart cert-manager
kubectl rollout restart deployment cert-manager -n cert-manager
```

### Add New Domain

To add a new domain (e.g., `example.com`):

1. **Update Cloudflare API token** to include new zone
2. **Create new Certificate:**
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-wildcard
  namespace: cert-manager
spec:
  secretName: example-com-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
  - '*.example.com'
  - 'example.com'
```

3. **Apply:**
```bash
kubectl apply -f new-certificate.yaml
```

## Security Considerations

- ✅ API token stored in Kubernetes Secret
- ✅ Token has minimal permissions (DNS:Edit only)
- ✅ Certificates auto-renewed (no manual intervention)
- ✅ Private keys never leave cluster
- ⚠️  Secret not encrypted at rest (consider: Sealed Secrets)
- ⚠️  Token has access to all DNS records

**Recommendations:**
- Rotate API token periodically
- Use Sealed Secrets for GitOps
- Monitor certificate expiry
- Regular backups of certificate resources

## Files

- `namespace.yaml` - cert-manager namespace
- `clusterissuers.yaml` - Production and staging ClusterIssuers
- `certificates.yaml` - Wildcard certificates for all domains
- `install.sh` - Automated cert-manager installation
- `create-cloudflare-secret.sh` - Helper to create Cloudflare secret
- `kustomization.yaml` - Kustomize configuration

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [Cloudflare DNS Solver](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
