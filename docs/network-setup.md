# Hybrid HTTPS Setup: Cloudflare Tunnel + Local Access
## Multi-Domain Configuration: charn.io (External + Local) + charno.net (External Only)

## Architecture Overview

```
External Users (Internet)
   |
   ├─ *.charn.io → Cloudflare Tunnel → cloudflared → Nginx Ingress → K3s Apps
   └─ *.charno.net → Cloudflare Tunnel → cloudflared → Nginx Ingress → Webserver Pods

Local Users (Home Network)
   |
   └─ *.local.charn.io → Router:443 → Pi:30443 → Nginx Ingress → K3s Apps
```

### Key Features:
- **External access**: All traffic through Cloudflare Tunnel (secure, hidden IP)
- **Local access**: Direct connection for fast internal access
- **charn.io**: External via tunnel + Local via local.charn.io
- **charno.net**: External only via tunnel
- **Wildcard certificates**: One cert per domain (*.charn.io, *.local.charn.io, *.charno.net)

---

## Part 1: Prerequisites

### 1.1 Cloudflare Requirements

You need:
- ✅ Both domains (charn.io and charno.net) in Cloudflare
- ✅ Cloudflare API token with DNS edit access to BOTH zones
- ✅ Cloudflare account (free tier works fine)

### 1.2 Create Cloudflare API Token

1. Log into Cloudflare Dashboard
2. Go to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use **Edit zone DNS** template
5. Configure:
   - **Permissions**: Zone - DNS - Edit
   - **Zone Resources**: 
     - Include - Specific zone - **charn.io**
     - Include - Specific zone - **charno.net**
6. Click **Continue to summary** → **Create Token**
7. **Copy the token** - you won't see it again!

### 1.3 Local DNS Configuration

You'll need to set up local DNS for `*.local.charn.io`. Two options:

**Option A: Router DNS (if supported)**
- Add wildcard DNS entry: `*.local.charn.io → Pi's local IP`

**Option B: Pi-hole or Local DNS Server**
- Add DNS record: `*.local.charn.io → Pi's local IP`

**Option C: Hosts File (manual, per device)**
- Edit `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows)
- Add entries for each service:
  ```
  192.168.1.XXX  nextcloud.local.charn.io
  192.168.1.XXX  jellyfin.local.charn.io
  192.168.1.XXX  homer.local.charn.io
  # etc.
  ```

---

## Part 2: Server Installation

### 2.1 Install Nginx Ingress Controller

```bash
# SSH to your Pi
ssh user@PI_IP

# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/baremetal/deploy.yaml

# Wait for it to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Configure specific NodePorts to avoid conflicts
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30280}]'

kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/1/nodePort", "value":30443}]'

# Verify
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Expected output shows NodePorts 30280 (HTTP) and 30443 (HTTPS).

### 2.2 Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready (2-3 minutes)
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

# Verify
kubectl get pods -n cert-manager
```

All three pods should be Running.

---

## Part 3: Certificate Configuration

### 3.1 Create Cloudflare API Token Secret

```bash
# Replace YOUR_CLOUDFLARE_API_TOKEN with your actual token
kubectl create secret generic cloudflare-api-token-secret \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN \
  -n cert-manager

# Verify
kubectl get secret cloudflare-api-token-secret -n cert-manager
```

### 3.2 Apply ClusterIssuer

Save as `cluster-issuer.yaml`:

```yaml
---
# Production Let's Encrypt Issuer with Cloudflare DNS-01
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare-prod
spec:
  acme:
    email: your-email@example.com  # Replace with your email
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-prod-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token

---
# Staging Issuer (for testing)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare-staging
spec:
  acme:
    email: your-email@example.com  # Replace with your email
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-staging-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
```

Apply it:
```bash
kubectl apply -f cluster-issuer.yaml

# Verify
kubectl get clusterissuer
```

Both should show "True" in the READY column.

### 3.3 Create Wildcard Certificates

Save as `wildcard-certificates.yaml`:

```yaml
---
# Wildcard certificate for external charn.io (*.charn.io)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: charn-io-wildcard
  namespace: default
spec:
  secretName: charn-io-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
  - '*.charn.io'
  - 'charn.io'

---
# Wildcard certificate for local charn.io (*.local.charn.io)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: local-charn-io-wildcard
  namespace: default
spec:
  secretName: local-charn-io-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
  - '*.local.charn.io'
  - 'local.charn.io'

---
# Wildcard certificate for charno.net (*.charno.net)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: charno-net-wildcard
  namespace: default
spec:
  secretName: charno-net-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
  - '*.charno.net'
  - 'charno.net'
```

Apply and monitor:
```bash
kubectl apply -f wildcard-certificates.yaml

# Watch certificates being issued (may take 2-5 minutes)
kubectl get certificate -n default -w

# When all show "True" in READY column, press Ctrl+C
```

**Troubleshooting certificate issues:**
```bash
# Check certificate status
kubectl describe certificate charn-io-wildcard -n default

# Check challenges
kubectl get challenge -n default

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

---

## Part 4: Cloudflare Tunnel Setup

### 4.1 Install cloudflared

```bash
# Download cloudflared for ARM64
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb

# Install
sudo dpkg -i cloudflared-linux-arm64.deb

# Verify
cloudflared --version
```

### 4.2 Authenticate and Create Tunnel

```bash
# Authenticate with Cloudflare (will open browser)
cloudflared tunnel login

# Create a tunnel named "pi-hybrid"
cloudflared tunnel create pi-hybrid

# Note the Tunnel ID from the output - you'll need it!
# Example output: "Created tunnel pi-hybrid with id: 12345678-1234-1234-1234-123456789abc"

# List tunnels to confirm
cloudflared tunnel list
```

### 4.3 Configure Tunnel

Create the tunnel configuration:

```bash
# Create config directory
sudo mkdir -p /etc/cloudflared

# Create configuration file
sudo nano /etc/cloudflared/config.yml
```

Paste this configuration (replace `YOUR_TUNNEL_ID` with your actual tunnel ID):

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

# Ingress rules for routing traffic
ingress:
  # ==========================================
  # charn.io services (external via tunnel)
  # ==========================================
  
  - hostname: nextcloud.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: nextcloud.charn.io
      noTLSVerify: false
  
  - hostname: jellyfin.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: jellyfin.charn.io
      noTLSVerify: false
  
  - hostname: homer.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: homer.charn.io
      noTLSVerify: false
  
  - hostname: grafana.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: grafana.charn.io
      noTLSVerify: false
  
  - hostname: prometheus.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: prometheus.charn.io
      noTLSVerify: false

  - hostname: wallabag.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: wallabag.charn.io
      noTLSVerify: false
  
  - hostname: homeassistant.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: homeassistant.charn.io
      noTLSVerify: false
  
  - hostname: k8s.charn.io
    service: http://localhost:30280
    originRequest:
      httpHostHeader: k8s.charn.io
      noTLSVerify: false
  
  # ==========================================
  # charno.net services (external only)
  # ==========================================
  
  - hostname: charno.net
    service: http://localhost:30280
    originRequest:
      httpHostHeader: charno.net
      noTLSVerify: false
  
  - hostname: www.charno.net
    service: http://localhost:30280
    originRequest:
      httpHostHeader: www.charno.net
      noTLSVerify: false
  
  # Add more charno.net subdomains as needed
  # - hostname: blog.charno.net
  #   service: http://localhost:30280
  
  # ==========================================
  # Catch-all for any other requests
  # ==========================================
  - service: http_status:404

# Optional: Enable metrics endpoint
metrics: localhost:2000
```

Save and exit (Ctrl+X, Y, Enter).

### 4.4 Route DNS Through Tunnel

```bash
# Route charn.io subdomains
cloudflared tunnel route dns pi-hybrid nextcloud.charn.io
cloudflared tunnel route dns pi-hybrid jellyfin.charn.io
cloudflared tunnel route dns pi-hybrid homer.charn.io
cloudflared tunnel route dns pi-hybrid grafana.charn.io
cloudflared tunnel route dns pi-hybrid prometheus.charn.io
cloudflared tunnel route dns pi-hybrid wallabag.charn.io
cloudflared tunnel route dns pi-hybrid homeassistant.charn.io
cloudflared tunnel route dns pi-hybrid k8s.charn.io

# Route charno.net
cloudflared tunnel route dns pi-hybrid charno.net
cloudflared tunnel route dns pi-hybrid www.charno.net

# Add more as needed
```

This automatically creates CNAME records in Cloudflare DNS pointing to your tunnel.

### 4.5 Test Tunnel Configuration

```bash
# Test the configuration
sudo cloudflared tunnel --config /etc/cloudflared/config.yml run pi-hybrid

# Watch for:
# - "Connection established" messages
# - No errors
# - Ctrl+C to stop when ready
```

### 4.6 Install Tunnel as System Service

```bash
# Install as a service
sudo cloudflared service install

# Start the service
sudo systemctl start cloudflared

# Enable on boot
sudo systemctl enable cloudflared

# Check status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f
```

You should see "Registered tunnel connection" messages.

---

## Part 5: Router Configuration (Local Access)

### 5.1 Configure Port Forwarding

This is ONLY for local network access via `*.local.charn.io`.

**In your router:**
1. Find Port Forwarding settings
2. Add rules:

```
External Port: 443
Internal IP: Your Pi's local IP (e.g., 192.168.1.50)
Internal Port: 30443
Protocol: TCP
```

**Note:** We only need port 443 (HTTPS) for local access. Port 80 can optionally be forwarded for automatic redirects.

Optional (for HTTP → HTTPS redirects):
```
External Port: 80
Internal IP: Your Pi's local IP
Internal Port: 30280
Protocol: TCP
```

### 5.2 Verify Local Access Setup

From a device on your local network:

```bash
# Test local DNS resolution
nslookup nextcloud.local.charn.io
# Should resolve to your Pi's local IP

# Test connectivity
curl -k https://nextcloud.local.charn.io
# Should connect (may show certificate error if certs not ready yet)
```

---

## Part 6: Create Ingress Resources

### 6.1 K3s Apps on charn.io (External + Local)

Each service needs TWO ingresses: one for external (charn.io) and one for local (local.charn.io).

Save as `charn-io-ingresses.yaml`:

```yaml
---
# ==========================================
# NEXTCLOUD - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud-external
  namespace: nextcloud
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10G"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - nextcloud.charn.io
    secretName: charn-io-wildcard-tls  # Using wildcard cert
  rules:
  - host: nextcloud.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nextcloud
            port:
              number: 80

---
# NEXTCLOUD - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud-local
  namespace: nextcloud
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10G"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - nextcloud.local.charn.io
    secretName: local-charn-io-wildcard-tls  # Using local wildcard cert
  rules:
  - host: nextcloud.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nextcloud
            port:
              number: 80

---
# ==========================================
# JELLYFIN - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jellyfin-external
  namespace: jellyfin
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - jellyfin.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: jellyfin.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jellyfin
            port:
              number: 8096

---
# JELLYFIN - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jellyfin-local
  namespace: jellyfin
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - jellyfin.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: jellyfin.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jellyfin
            port:
              number: 8096

---
# ==========================================
# HOMER - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homer-external
  namespace: homer
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homer.charn.io
    secretName: charn-io-wildcard-tls
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

---
# HOMER - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homer-local
  namespace: homer
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homer.local.charn.io
    secretName: local-charn-io-wildcard-tls
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

---
# ==========================================
# GRAFANA - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-external
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: grafana.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000

---
# GRAFANA - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-local
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: grafana.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000

---
# ==========================================
# PROMETHEUS - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-external
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: prometheus.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090

---
# PROMETHEUS - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-local
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: prometheus.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090

---
# ==========================================
# WALLABAG - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wallabag-external
  namespace: wallabag
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - wallabag.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: wallabag.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: wallabag
            port:
              number: 80

---
# WALLABAG - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wallabag-local
  namespace: wallabag
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - wallabag.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: wallabag.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: wallabag
            port:
              number: 80

---
# ==========================================
# HOME ASSISTANT - External Access
# ==========================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homeassistant-external
  namespace: homeassistant
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/websocket-services: "homeassistant"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homeassistant.charn.io
    secretName: charn-io-wildcard-tls
  rules:
  - host: homeassistant.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: homeassistant
            port:
              number: 8123

---
# HOME ASSISTANT - Local Access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homeassistant-local
  namespace: homeassistant
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/websocket-services: "homeassistant"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - homeassistant.local.charn.io
    secretName: local-charn-io-wildcard-tls
  rules:
  - host: homeassistant.local.charn.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: homeassistant
            port:
              number: 8123
```

Apply it:
```bash
kubectl apply -f charn-io-ingresses.yaml
```

### 6.2 Custom Webserver on charno.net (External Only)

First, create the webserver deployment and service:

Save as `charno-net-webserver.yaml`:

```yaml
---
# Namespace for charno.net
apiVersion: v1
kind: Namespace
metadata:
  name: charno-net

---
# Simple webserver deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webserver
  namespace: charno-net
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webserver
  template:
    metadata:
      labels:
        app: webserver
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: webserver-html

---
# ConfigMap with simple HTML content
apiVersion: v1
kind: ConfigMap
metadata:
  name: webserver-html
  namespace: charno-net
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>charno.net</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
                background: #f5f5f5;
            }
            .container {
                background: white;
                padding: 40px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 { color: #333; }
            p { color: #666; line-height: 1.6; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Welcome to charno.net</h1>
            <p>This is a custom webserver running on Kubernetes!</p>
            <p>Served via Cloudflare Tunnel with automatic HTTPS.</p>
        </div>
    </body>
    </html>

---
# Service for the webserver
apiVersion: v1
kind: Service
metadata:
  name: webserver
  namespace: charno-net
spec:
  selector:
    app: webserver
  ports:
  - port: 80
    targetPort: 80

---
# Ingress for charno.net (www and apex)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: charno-net
  namespace: charno-net
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - charno.net
    - www.charno.net
    secretName: charno-net-wildcard-tls  # Using wildcard cert
  rules:
  - host: charno.net
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webserver
            port:
              number: 80
  - host: www.charno.net
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webserver
            port:
              number: 80
```

Apply it:
```bash
kubectl apply -f charno-net-webserver.yaml
```

---

## Part 7: Verification and Testing

### 7.1 Check All Components

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check cert-manager
kubectl get pods -n cert-manager

# Check certificates
kubectl get certificate -n default

# Check cloudflared
sudo systemctl status cloudflared

# Check all ingresses
kubectl get ingress --all-namespaces
```

### 7.2 Test External Access (via Cloudflare Tunnel)

From a device NOT on your local network (use phone on cellular, or a VPS):

```bash
# Test charn.io services
curl -v https://homer.charn.io
curl -v https://nextcloud.charn.io

# Test charno.net
curl -v https://charno.net
curl -v https://www.charno.net

# All should return 200 OK with valid SSL certificates
```

### 7.3 Test Local Access

From a device on your local network:

```bash
# Test local.charn.io services
curl -v https://homer.local.charn.io
curl -v https://nextcloud.local.charn.io

# All should return 200 OK with valid SSL certificates
```

### 7.4 Test in Browser

**External (from anywhere):**
- https://homer.charn.io
- https://nextcloud.charn.io
- https://jellyfin.charn.io
- https://charno.net

**Local (from home network):**
- https://homer.local.charn.io
- https://nextcloud.local.charn.io
- https://jellyfin.local.charn.io

All should show valid SSL certificates (green padlock) and load correctly.

---

## Part 8: Cloudflare Configuration

### 8.1 Verify DNS Records

Log into Cloudflare Dashboard and check DNS records:

**For charn.io:**
- You should see CNAME records for each subdomain pointing to your tunnel
- Example: `nextcloud.charn.io` → `YOUR_TUNNEL_ID.cfargotunnel.com`

**For charno.net:**
- You should see CNAME records pointing to your tunnel
- Example: `charno.net` → `YOUR_TUNNEL_ID.cfargotunnel.com`
- Example: `www.charno.net` → `YOUR_TUNNEL_ID.cfargotunnel.com`

### 8.2 SSL/TLS Settings

For both domains (charn.io and charno.net):

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to: **Full (strict)**
3. Go to **SSL/TLS** → **Edge Certificates**
4. Enable:
   - ✅ Always Use HTTPS
   - ✅ Automatic HTTPS Rewrites
   - ✅ Minimum TLS Version: 1.2

### 8.3 Security Settings (Optional but Recommended)

For both domains:

1. **Firewall Rules**:
   - Create rules to block traffic from unwanted countries
   - Rate limit login pages

2. **Bot Fight Mode**:
   - Go to **Security** → **Bots**
   - Enable Bot Fight Mode

3. **WAF (Web Application Firewall)**:
   - Go to **Security** → **WAF**
   - Enable Managed Rules

---

## Part 9: Troubleshooting

### Issue: Certificates Not Issuing

```bash
# Check certificate status
kubectl describe certificate charn-io-wildcard -n default

# Check challenges
kubectl get challenge -n default
kubectl describe challenge -n default

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Common issue: API token permissions
# Verify token has DNS edit access to BOTH zones
```

### Issue: Tunnel Not Connecting

```bash
# Check tunnel status
sudo systemctl status cloudflared

# Check logs
sudo journalctl -u cloudflared -n 100

# Test configuration
sudo cloudflared tunnel --config /etc/cloudflared/config.yml run pi-hybrid

# Common issues:
# - Wrong tunnel ID in config
# - Credentials file path incorrect
# - Network connectivity issues
```

### Issue: Local Access Not Working

```bash
# Check DNS resolution
nslookup nextcloud.local.charn.io
# Should resolve to Pi's local IP

# Check if port forwarding is working
# From local network:
nc -zv YOUR_PI_IP 30443

# Check nginx ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

### Issue: 502 Bad Gateway

```bash
# Check if service exists
kubectl get svc -n nextcloud

# Check if pods are running
kubectl get pods -n nextcloud

# Check service endpoints
kubectl get endpoints nextcloud -n nextcloud

# If no endpoints, pods aren't matching service selector
```

---

## Part 10: Monitoring and Maintenance

### Monitor Cloudflare Tunnel

```bash
# Check tunnel status
sudo systemctl status cloudflared

# View real-time logs
sudo journalctl -u cloudflared -f

# Check metrics (if enabled)
curl http://localhost:2000/metrics
```

### Monitor Certificates

```bash
# Check all certificates
kubectl get certificate --all-namespaces

# Check expiration
kubectl get certificate charn-io-wildcard -n default -o jsonpath='{.status.notAfter}'

# Certificates auto-renew 30 days before expiration
```

### View Ingress Status

```bash
# List all ingresses
kubectl get ingress --all-namespaces

# Check specific ingress
kubectl describe ingress nextcloud-external -n nextcloud
```

---

## Part 11: Homer Dashboard Configuration

Update your Homer dashboard to include both external and local links.

Edit Homer config:
```bash
kubectl edit configmap homer-config -n homer
```

Add section for local vs external access:

```yaml
data:
  config.yml: |
    title: "Home Dashboard"
    subtitle: "K3s Cluster"
    
    header: true
    footer: false
    
    services:
      - name: "Applications (External)"
        icon: "fas fa-cloud"
        items:
          - name: "Nextcloud"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/nextcloud.png"
            subtitle: "File Storage"
            url: "https://nextcloud.charn.io"
          
          - name: "Jellyfin"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/jellyfin.png"
            subtitle: "Media Server"
            url: "https://jellyfin.charn.io"
          
          - name: "Grafana"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/grafana.png"
            subtitle: "Monitoring"
            url: "https://grafana.charn.io"
      
      - name: "Applications (Local - Fast)"
        icon: "fas fa-home"
        items:
          - name: "Nextcloud (Local)"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/nextcloud.png"
            subtitle: "File Storage - Direct"
            url: "https://nextcloud.local.charn.io"
          
          - name: "Jellyfin (Local)"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/jellyfin.png"
            subtitle: "Media Server - Direct"
            url: "https://jellyfin.local.charn.io"
          
          - name: "Grafana (Local)"
            logo: "https://raw.githubusercontent.com/NX211/homer-icons/master/png/grafana.png"
            subtitle: "Monitoring - Direct"
            url: "https://grafana.local.charn.io"
```

Restart Homer:
```bash
kubectl rollout restart deployment homer -n homer
```

---

## Summary: What You Have Now

### External Access (via Cloudflare Tunnel):
- ✅ **charn.io services**: nextcloud.charn.io, jellyfin.charn.io, etc.
- ✅ **charno.net**: charno.net, www.charno.net
- ✅ Hidden home IP
- ✅ Cloudflare DDoS protection
- ✅ No port forwarding needed
- ✅ Valid SSL certificates

### Local Access (direct connection):
- ✅ **local.charn.io services**: nextcloud.local.charn.io, etc.
- ✅ Fast, direct connection
- ✅ Works without internet
- ✅ Lower latency for streaming
- ✅ Valid SSL certificates

### Architecture Benefits:
- ✅ Best of both worlds
- ✅ Secure external access
- ✅ Fast local access
- ✅ Wildcard certificates (easy management)
- ✅ Multi-domain support
- ✅ Flexible routing

---

## Quick Reference Commands

```bash
# Check tunnel status
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f

# Check certificates
kubectl get certificate -n default

# Check all ingresses
kubectl get ingress --all-namespaces

# Restart tunnel
sudo systemctl restart cloudflared

# Restart ingress controller
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

# View nginx logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f

# View cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

---

## Next Steps

1. **Customize charno.net content**
   - Edit the ConfigMap: `kubectl edit configmap webserver-html -n charno-net`
   - Or mount persistent storage for dynamic content

2. **Add more services**
   - Follow the same pattern: create external and local ingresses
   - Use wildcard certificates

3. **Configure applications**
   - Update Home Assistant trusted proxies
   - Update Nextcloud trusted domains

4. **Set up Cloudflare Access** (optional)
   - Add SSO authentication to sensitive services
   - Go to Cloudflare Zero Trust dashboard

5. **Monitor and optimize**
   - Check Cloudflare Analytics
   - Monitor tunnel metrics
   - Review certificate renewals

Congratulations! You now have a secure, hybrid HTTPS setup with the best of both worlds! 🎉
