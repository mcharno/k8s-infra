# Quick Start Guide

Complete guide to deploying the K3s homelab infrastructure from scratch in the correct order.

**Time Required:** ~2-3 hours for fresh installation
**Platform:** Raspberry Pi 4 (8GB) + K3s
**Last Updated:** November 2025

---

## Prerequisites

### Hardware
- ✅ Raspberry Pi 4 (8GB RAM)
- ✅ 2x SSDs (USB 3.0) - current: 1TB + 2TB
- ✅ SD Card (32GB+) with Ubuntu Server 22.04 LTS ARM64
- ✅ Network connection (Ethernet recommended)
- ✅ Power supply

### Accounts & Tokens
- ✅ Cloudflare account (free tier OK)
- ✅ Cloudflare API token (DNS:Edit for charn.io and charno.net)
- ✅ Email address for Let's Encrypt notifications

### Information Needed
- Static IP for Pi (e.g., 192.168.0.23)
- Router admin access (for port forwarding)
- Backup location for credentials

---

## Deployment Order

### Phase 1: Foundation (30 minutes)

#### 1. Setup Storage (LVM)

```bash
# SSH to Pi
ssh pi@pibox  # or ssh pi@192.168.0.23

# Run LVM setup
sudo bash scripts/storage/setup-lvm.sh
```

**What this does:**
- Combines both SSDs into single 2.7TB volume
- Creates volume group `k3s-storage`
- Mounts at `/mnt/k3s-storage`
- Configures auto-mount

**Verify:**
```bash
df -h /mnt/k3s-storage
# Should show ~2.7TB
```

#### 2. Install K3s

```bash
# Install K3s with optimized settings
sudo bash scripts/k3s/install-k3s.sh
```

**What this does:**
- Installs K3s (disables Traefik and ServiceLB)
- Optimizes for Pi 4 (memory/CPU reservations)
- Sets up kubectl access

**Verify:**
```bash
kubectl get nodes
# Should show: Ready

kubectl get pods -A
# Should show: coredns, local-path-provisioner running
```

**Important:** If first install, reboot for cgroup settings:
```bash
sudo reboot
# Wait 2 minutes, then SSH back in
```

---

### Phase 2: Core Infrastructure (20 minutes)

#### 3. Install Nginx Ingress

```bash
# Install Nginx Ingress Controller
bash infrastructure/ingress-nginx/install.sh
```

**What this does:**
- Installs official Nginx Ingress
- Applies critical ConfigMap (`ssl-redirect: false`)
- Sets fixed NodePorts (30280 HTTP, 30443 HTTPS)

**Verify:**
```bash
kubectl get pods -n ingress-nginx
# Should show: ingress-nginx-controller Running

kubectl get svc -n ingress-nginx
# Should show: 80:30280, 443:30443
```

#### 4. Install cert-manager

```bash
# Install cert-manager
bash infrastructure/cert-manager/install.sh
```

**Verify:**
```bash
kubectl get pods -n cert-manager
# All pods should be Running
```

---

### Phase 3: Certificates & DNS (15 minutes)

#### 5. Create Cloudflare Secret

```bash
# Interactive secret creation
bash infrastructure/cert-manager/create-cloudflare-secret.sh
# Paste your Cloudflare API token when prompted
```

#### 6. Apply ClusterIssuers

```bash
# Create Let's Encrypt issuers
kubectl apply -f infrastructure/cert-manager/clusterissuers.yaml

# Verify
kubectl get clusterissuer
# Should show: letsencrypt-cloudflare-prod (True)
```

#### 7. Request Certificates

```bash
# Create wildcard certificates
kubectl apply -f infrastructure/cert-manager/certificates.yaml

# Monitor issuance (takes 2-5 minutes)
kubectl get certificate -n cert-manager -w

# All should eventually show READY=True
# Press Ctrl+C when done
```

**Troubleshooting:** If certificates don't issue:
```bash
kubectl describe certificate charn-io-wildcard -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

---

### Phase 4: Databases (10 minutes)

#### 8. Deploy Shared PostgreSQL

```bash
# Create database passwords
bash scripts/databases/create-postgres-secret.sh

# Deploy PostgreSQL
kubectl apply -k infrastructure/databases/postgres/

# Wait for ready
kubectl wait --for=condition=Ready pod -l app=postgres -n database --timeout=180s
```

**Verify:**
```bash
kubectl get pods -n database
kubectl get pvc -n database
# Should show: postgres-0 Running, postgres-data Bound
```

**Save credentials:** File created: `postgres-credentials-TIMESTAMP.txt`
- Move this to a secure location!
- You'll need it for application setup

#### 9. Deploy Redis

```bash
# Deploy Redis cache
kubectl apply -k infrastructure/databases/redis/

# Wait for ready
kubectl wait --for=condition=Ready pod -l app=redis -n database --timeout=120s
```

**Verify:**
```bash
kubectl get pods -n database | grep redis
kubectl get pvc -n database | grep redis
# Should show: redis Running, redis-data Bound
```

---

### Phase 5: Network Configuration (30 minutes)

#### 10. Configure Router (Local Access)

Log into your router and configure port forwarding:

```
Service: HTTPS
External Port: 443
Internal IP: 192.168.0.23  # Your Pi's IP
Internal Port: 30443
Protocol: TCP
```

**Test from local network:**
```bash
# From another device on your network
curl -I https://192.168.0.23:30443
# Should return: 404 (no ingress configured yet - this is expected)
```

#### 11. Install Cloudflare Tunnel

```bash
# Install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb

# Authenticate (opens browser)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create pi-hybrid
# Note the Tunnel ID from output!

# Configure tunnel
sudo mkdir -p /etc/cloudflared
sudo cp infrastructure/network/cloudflared-config.yml /etc/cloudflared/config.yml

# Edit config with your tunnel ID
sudo nano /etc/cloudflared/config.yml
# Replace YOUR_TUNNEL_ID with actual ID

# Route DNS for external domains
cloudflared tunnel route dns pi-hybrid homer.charn.io
cloudflared tunnel route dns pi-hybrid nextcloud.charn.io
cloudflared tunnel route dns pi-hybrid jellyfin.charn.io
cloudflared tunnel route dns pi-hybrid home.charn.io
cloudflared tunnel route dns pi-hybrid grafana.charn.io
cloudflared tunnel route dns pi-hybrid prometheus.charn.io
cloudflared tunnel route dns pi-hybrid wallabag.charn.io
cloudflared tunnel route dns pi-hybrid k8s.charn.io

# Install as service
sudo cloudflared service install

# Start service
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Verify
sudo systemctl status cloudflared
# Should show: active (running)
```

---

### Phase 6: Infrastructure Complete! (Summary)

At this point, you have:

- ✅ K3s cluster running
- ✅ 2.7TB LVM storage
- ✅ Nginx Ingress (with critical config)
- ✅ cert-manager with wildcard certificates
- ✅ Shared PostgreSQL (saves ~512MB RAM)
- ✅ Redis cache
- ✅ Cloudflare Tunnel (external access)
- ✅ Router configured (local access)

**Check overall status:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get certificate -n cert-manager
```

---

## Next Steps

### Deploy Applications

Applications can now be deployed. See individual app READMEs:

1. **Homer** - Dashboard (deploy first for easy access)
2. **Prometheus** - Metrics collection
3. **Grafana** - Monitoring dashboards
4. **Nextcloud** - File storage
5. **Jellyfin** - Media server
6. **Home Assistant** - Smart home
7. **Wallabag** - Read-it-later

### Access URLs

**External (from anywhere):**
- https://APP.charn.io

**Local (from home network):**
- https://APP.local.charn.io

### Configure Local DNS

For local access (*.local.charn.io), configure DNS:

**Option A: Pi-hole or Local DNS Server**
- Add DNS record: `*.local.charn.io` → `192.168.0.23`

**Option B: Hosts File (per device)**
Edit `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
```
192.168.0.23  homer.local.charn.io
192.168.0.23  nextcloud.local.charn.io
192.168.0.23  jellyfin.local.charn.io
# etc.
```

---

## Verification Checklist

Use this checklist to verify your installation:

### Infrastructure
- [ ] K3s node is Ready
- [ ] All infrastructure pods Running
- [ ] Storage provisioner working
- [ ] Nginx Ingress running (ports 30280/30443)
- [ ] cert-manager pods Running
- [ ] All certificates READY=True
- [ ] PostgreSQL pod Running, PVC Bound
- [ ] Redis pod Running, PVC Bound
- [ ] Cloudflare Tunnel connected

### Network
- [ ] Router port forwarding configured (443 → 30443)
- [ ] Cloudflare DNS records created (CNAME to tunnel)
- [ ] Local DNS configured (*.local.charn.io)

### Testing
- [ ] curl http://PI_IP:30280 returns 404
- [ ] curl https://PI_IP:30443 returns 404 or certificate error (expected - no apps yet)
- [ ] Cloudflare Tunnel shows "connected" in systemctl status

---

## Common Issues & Solutions

### K3s Node Not Ready

```bash
kubectl describe node
sudo journalctl -u k3s -n 100
```

**Solution:** Reboot if first install (for cgroup settings)

### Certificates Not Issuing

```bash
kubectl describe certificate charn-io-wildcard -n cert-manager
kubectl get challenge -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

**Solution:** Verify Cloudflare API token has DNS:Edit for both zones

### Cloudflare Tunnel Not Connecting

```bash
sudo journalctl -u cloudflared -n 100
```

**Common fixes:**
- Wrong tunnel ID in config
- Credentials file path incorrect
- Firewall blocking outbound 443

### 308 Redirect Loop (After Deploying Apps)

**Solution:** Nginx ConfigMap must have `ssl-redirect: false`
```bash
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep ssl-redirect
# Should show: ssl-redirect: "false"
```

### Storage Issues

```bash
kubectl get pv,pvc -A
kubectl logs -n kube-system -l app=local-path-provisioner
```

**Solution:** Verify `/mnt/k3s-storage` is mounted:
```bash
df -h /mnt/k3s-storage
```

---

## Backup & Maintenance

### Regular Backups

**PostgreSQL databases:**
```bash
kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup-$(date +%Y%m%d).sql
```

**Certificates (auto-renewed, but good to backup):**
```bash
kubectl get certificate,clusterissuer --all-namespaces -o yaml > certs-backup.yaml
```

**Kubernetes resources:**
```bash
kubectl get all,pvc,ingress --all-namespaces -o yaml > k8s-backup.yaml
```

### Updates

**K3s:**
```bash
curl -sfL https://get.k3s.io | sh -
```

**Applications:**
- Update image versions in manifests
- Apply with kubectl

### Monitoring

- Grafana: https://grafana.charn.io
- Prometheus: https://prometheus.charn.io
- kubectl top nodes/pods

---

## Getting Help

**Documentation:**
- [Disaster Recovery Guide](disaster-recovery.md) - Complete rebuild
- [Migration Summary](MIGRATION-SUMMARY.md) - Architecture decisions
- [Deployment Workflow](deployment-workflow.md) - GitOps setup
- Component READMEs in each directory

**Logs:**
```bash
# Specific pod
kubectl logs -f POD_NAME -n NAMESPACE

# All pods in namespace
kubectl logs -n NAMESPACE --all-containers=true

# Previous pod instance
kubectl logs POD_NAME -n NAMESPACE --previous
```

**Events:**
```bash
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

**Describe:**
```bash
kubectl describe pod POD_NAME -n NAMESPACE
kubectl describe pvc PVC_NAME -n NAMESPACE
kubectl describe certificate CERT_NAME -n NAMESPACE
```

---

## Success Criteria

Your installation is successful when:

- ✅ All infrastructure pods Running
- ✅ All PVCs Bound
- ✅ All certificates READY=True
- ✅ Cloudflare Tunnel connected
- ✅ Can curl Pi on port 30280 (HTTP) and 30443 (HTTPS)
- ✅ DNS records created in Cloudflare
- ✅ Ready to deploy applications

---

**Congratulations!** Your K3s homelab infrastructure is ready for applications!

Next: Deploy your first app (Homer dashboard recommended) and verify end-to-end connectivity.
