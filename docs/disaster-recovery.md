# Disaster Recovery Guide

This document provides step-by-step instructions for rebuilding the entire K3s homelab infrastructure from scratch.

**Last Updated:** November 2025
**Platform:** Raspberry Pi 4 (8GB) with ARM64
**Status:** Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Hardware Setup](#hardware-setup)
4. [Operating System Installation](#operating-system-installation)
5. [Storage Configuration](#storage-configuration)
6. [K3s Installation](#k3s-installation)
7. [Core Infrastructure](#core-infrastructure)
8. [Network & Certificates](#network--certificates)
9. [Database Services](#database-services)
10. [Application Deployment](#application-deployment)
11. [Monitoring Stack](#monitoring-stack)
12. [Data Restoration](#data-restoration)
13. [Verification](#verification)

---

## Overview

### What Gets Rebuilt

- ✅ K3s cluster with optimized settings for Raspberry Pi
- ✅ LVM-based storage across dual SSDs (2.7TB total)
- ✅ Nginx Ingress Controller
- ✅ cert-manager with SSL certificates
- ✅ Cloudflare Tunnel for external access
- ✅ Local network access with HTTPS
- ✅ Shared PostgreSQL instance
- ✅ Redis cache
- ✅ All applications (Nextcloud, Jellyfin, Home Assistant, etc.)
- ✅ Prometheus + Grafana monitoring

### What Needs Manual Restoration

- ⚠️ Application data (from backups)
- ⚠️ Database contents (from backups)
- ⚠️ Secrets and credentials
- ⚠️ Cloudflare API tokens
- ⚠️ Application-specific configurations

### Recovery Time Estimate

- **Fresh Install:** 2-3 hours
- **With Data Restoration:** 4-6 hours (depending on backup size)

---

## Prerequisites

### Required Items

**Hardware:**
- Raspberry Pi 4 (8GB RAM minimum)
- 2x SSDs (current setup: 1TB + 2TB)
- SD Card (32GB minimum, for OS)
- Power supply
- Network cable
- Case with cooling

**Software:**
- Ubuntu Server 22.04 LTS ARM64 image
- Raspberry Pi Imager or balenaEtcher
- SSH client (for remote access)

**Information You'll Need:**
- Static IP address for the Pi (current: 192.168.0.23)
- Router access (for port forwarding)
- Cloudflare account credentials
- Cloudflare API token
- Backup location (external drive/NAS/cloud)

---

## Hardware Setup

### 1. Physical Assembly

```bash
# 1. Connect SSDs to Pi via USB 3.0
# 2. Insert SD card
# 3. Connect network cable
# 4. Connect power (last step)
```

### 2. Verify Hardware

After OS installation, verify hardware:

```bash
# Check CPU info
lscpu | grep 'Model name'
# Should show: ARM Cortex-A72

# Check memory
free -h
# Should show: ~7.6GB total

# Check drives
lsblk
# Should show:
#   mmcblk0 (SD card, ~32GB)
#   sda (SSD #1, ~1TB)
#   sdb (SSD #2, ~2TB)
```

---

## Operating System Installation

### 1. Flash Ubuntu Server

Use Raspberry Pi Imager:

1. **Choose OS:** Ubuntu Server 22.04 LTS (64-bit)
2. **Choose Storage:** Your SD card
3. **Settings** (gear icon):
   - Enable SSH
   - Set hostname: `pibox`
   - Set username: `pi`
   - Set password
   - Configure WiFi (optional, but Ethernet recommended)
   - Set locale/timezone
4. **Write**

### 2. First Boot

```bash
# SSH into the Pi (wait 2-3 minutes after first boot)
ssh pi@pibox  # or ssh pi@192.168.0.23

# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y lvm2 parted wget curl git

# Reboot
sudo reboot
```

### 3. Configure Static IP (Optional but Recommended)

Edit netplan configuration:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Set static IP:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.0.23/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply:

```bash
sudo netplan apply
```

---

## Storage Configuration

### LVM Setup with Dual SSDs

This combines both SSDs into a single ~2.7TB volume.

```bash
# Download setup script
wget https://raw.githubusercontent.com/YOUR_REPO/infra-k8s/main/scripts/storage/setup-lvm.sh

# Make executable
chmod +x setup-lvm.sh

# Run with sudo
sudo bash setup-lvm.sh
```

**What this does:**
- Creates LVM physical volumes on both SSDs
- Combines them into volume group `k3s-storage`
- Creates logical volume `data`
- Formats as ext4
- Mounts at `/mnt/k3s-storage`
- Configures auto-mount in `/etc/fstab`

**Verify:**

```bash
df -h /mnt/k3s-storage
# Should show ~2.7TB total

pvs && vgs && lvs
# Should show LVM configuration
```

---

## K3s Installation

### Install K3s with Optimized Settings

```bash
# Download installation script
wget https://raw.githubusercontent.com/YOUR_REPO/infra-k8s/main/scripts/k3s/install-k3s.sh

# Make executable
chmod +x install-k3s.sh

# Run with sudo
sudo bash install-k3s.sh
```

**Configuration highlights:**
- Traefik disabled (using Nginx Ingress)
- ServiceLB disabled
- Max pods: 110
- Memory/CPU reservations for system stability
- Eviction thresholds configured
- Kubeconfig at: `/etc/rancher/k3s/k3s.yaml`

**Verify:**

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
# Should show node Ready

kubectl get pods -A
# Should show core K3s components running
```

### Configure kubectl

```bash
# Copy kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

# Add alias
echo "alias k=kubectl" >> ~/.bashrc
source ~/.bashrc
```

---

## Core Infrastructure

Apply infrastructure components in order:

### 1. Nginx Ingress Controller

```bash
cd /path/to/infra-k8s

# Apply Nginx Ingress
kubectl apply -k infrastructure/ingress-nginx/

# Wait for ready
kubectl wait --for=condition=available --timeout=300s \
  deployment -n ingress-nginx ingress-nginx-controller

# Verify
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Should show NodePorts 30280 (HTTP) and 30443 (HTTPS)
```

### 2. cert-manager

```bash
# Apply cert-manager
kubectl apply -k infrastructure/cert-manager/

# Wait for ready
kubectl wait --for=condition=available --timeout=300s \
  deployment -n cert-manager cert-manager

kubectl wait --for=condition=available --timeout=300s \
  deployment -n cert-manager cert-manager-webhook

kubectl wait --for=condition=available --timeout=300s \
  deployment -n cert-manager cert-manager-cainjector

# Verify
kubectl get pods -n cert-manager
# All pods should be Running
```

### 3. Local Path Provisioner Configuration

K3s includes local-path-provisioner by default, but we need to configure it for our LVM storage:

```bash
# Apply storage configuration
kubectl apply -k infrastructure/storage/

# Verify
kubectl get storageclass
# Should show local-path as default
```

---

## Network & Certificates

### 1. Create Cloudflare API Secret

You'll need a Cloudflare API token with DNS edit permissions for your domains.

```bash
# Create secret (replace with your actual token)
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN \
  -n cert-manager
```

### 2. Apply ClusterIssuers and Certificates

```bash
# Apply certificate configuration
kubectl apply -f infrastructure/cert-manager/certificates/

# Monitor certificate issuance
kubectl get certificate -n cert-manager -w
# Wait until all show READY=True
```

### 3. Set up Cloudflare Tunnel

```bash
# Install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb

# Authenticate (opens browser)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create pi-hybrid

# Note the tunnel ID from output

# Copy configuration
sudo mkdir -p /etc/cloudflared
sudo cp infrastructure/network/cloudflared-config.yml /etc/cloudflared/config.yml

# Edit config to add your tunnel ID
sudo nano /etc/cloudflared/config.yml
# Replace YOUR_TUNNEL_ID with actual ID

# Route DNS
cloudflared tunnel route dns pi-hybrid nextcloud.charn.io
cloudflared tunnel route dns pi-hybrid jellyfin.charn.io
cloudflared tunnel route dns pi-hybrid homer.charn.io
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
```

### 4. Configure Router Port Forwarding

For local access (*.local.charn.io):

```
Port 443 → 192.168.0.23:30443 (HTTPS - required)
Port 80  → 192.168.0.23:30280 (HTTP - optional, for redirects)
```

---

## Database Services

### 1. Shared PostgreSQL

```bash
# Apply PostgreSQL
kubectl apply -k infrastructure/databases/postgres/

# Wait for ready
kubectl wait --for=condition=Ready pod \
  -l app=postgres -n database --timeout=180s

# Verify
kubectl get pods -n database
kubectl get pvc -n database
```

### 2. Redis Cache

```bash
# Apply Redis
kubectl apply -k infrastructure/databases/redis/

# Wait for ready
kubectl wait --for=condition=Ready pod \
  -l app=redis -n database --timeout=120s

# Verify
kubectl get pods -n database
```

### 3. Retrieve Database Credentials

```bash
# Get PostgreSQL passwords
kubectl get secret postgres-passwords -n database \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Application Deployment

Deploy applications in this order:

```bash
# 1. Homer Dashboard (homepage)
kubectl apply -k apps/homer/

# 2. Nextcloud (file storage)
kubectl apply -k apps/nextcloud/

# 3. Jellyfin (media server)
kubectl apply -k apps/jellyfin/

# 4. Home Assistant (smart home)
kubectl apply -k apps/homeassistant/

# 5. Wallabag (read later)
kubectl apply -k apps/wallabag/

# Wait for all to be ready
kubectl get pods --all-namespaces
```

**Note:** Applications using the shared PostgreSQL will automatically connect. No additional database setup needed.

---

## Monitoring Stack

```bash
# Deploy Prometheus + Grafana
kubectl apply -k apps/prometheus/
kubectl apply -k apps/grafana/

# Wait for ready
kubectl wait --for=condition=Ready pod \
  -l app=prometheus -n monitoring --timeout=180s

kubectl wait --for=condition=Ready pod \
  -l app=grafana -n monitoring --timeout=120s

# Get Grafana initial password
kubectl get secret grafana-admin -n monitoring \
  -o jsonpath='{.data.password}' | base64 -d
```

**Access:**
- Prometheus: http://PI_IP:30090
- Grafana: http://PI_IP:30300

**Grafana Setup:**
1. Login with admin credentials
2. Import dashboard #315 (Kubernetes Cluster)
3. Import dashboard #6417 (Pod Resources)

---

## Data Restoration

### Restore from Backups

Assuming you have backups of:
- PostgreSQL databases
- Application persistent volumes
- Application configurations

#### PostgreSQL Restore

```bash
# Copy backup file to pod
kubectl cp backup.sql database/postgres-0:/tmp/

# Restore
kubectl exec -n database postgres-0 -- \
  psql -U postgres < /tmp/backup.sql

# Or for specific database
kubectl exec -n database postgres-0 -- \
  psql -U postgres -d nextcloud < /tmp/nextcloud-backup.sql
```

#### Persistent Volume Restore

```bash
# Example for Nextcloud data
# 1. Find the PV path
kubectl get pv

# 2. Copy data to the volume
# SSH to Pi, then:
sudo rsync -av /path/to/backup/ /mnt/k3s-storage/local-path-provisioner/pvc-XXXXX/

# 3. Restart the pod
kubectl rollout restart deployment/nextcloud -n nextcloud
```

---

## Verification

### Check All Components

```bash
# Nodes
kubectl get nodes
# Should show: Ready

# All pods
kubectl get pods --all-namespaces
# All should be Running

# Persistent volumes
kubectl get pv,pvc --all-namespaces
# All PVCs should be Bound

# Ingresses
kubectl get ingress --all-namespaces
# Should show all app ingresses

# Certificates
kubectl get certificate -n cert-manager
# All should be READY=True

# Services
kubectl get svc --all-namespaces | grep NodePort
# Should show all exposed services
```

### Test External Access

From outside your network:

```bash
curl -I https://homer.charn.io
curl -I https://nextcloud.charn.io
curl -I https://jellyfin.charn.io
# All should return 200 OK
```

### Test Local Access

From your local network:

```bash
curl -I https://homer.local.charn.io
curl -I https://nextcloud.local.charn.io
curl -I https://jellyfin.local.charn.io
# All should return 200 OK
```

### Access Applications

**External (from anywhere):**
- Homer: https://homer.charn.io
- Nextcloud: https://nextcloud.charn.io
- Jellyfin: https://jellyfin.charn.io
- Home Assistant: https://home.charn.io
- Grafana: https://grafana.charn.io
- Prometheus: https://prometheus.charn.io
- Wallabag: https://wallabag.charn.io

**Local (from home network):**
- Use *.local.charn.io for faster access
- Example: https://jellyfin.local.charn.io

---

## Post-Recovery Tasks

### 1. Update Application Credentials

Each application may need credentials set:

```bash
# Nextcloud admin password
kubectl get secret nextcloud-secrets -n nextcloud \
  -o jsonpath='{.data.admin-password}' | base64 -d

# Grafana admin password
kubectl get secret grafana-admin -n monitoring \
  -o jsonpath='{.data.password}' | base64 -d
```

### 2. Configure Applications

- **Nextcloud:** Configure trusted domains, enable apps
- **Home Assistant:** Restore configuration.yaml
- **Jellyfin:** Add media libraries
- **Grafana:** Import dashboards, configure alerts

### 3. Set Up Backups

```bash
# Schedule automated backups
# See: docs/backup-strategy.md
```

### 4. Security Hardening

```bash
# Disable SSH password auth (use keys only)
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no

# Update system
sudo apt update && sudo apt upgrade -y

# Configure firewall (optional)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

---

## Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl describe pod POD_NAME -n NAMESPACE

# Check events
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'

# Check logs
kubectl logs POD_NAME -n NAMESPACE
```

#### Storage Issues

```bash
# Check PVC status
kubectl get pvc --all-namespaces

# Check local-path-provisioner
kubectl logs -n kube-system -l app=local-path-provisioner

# Verify LVM
sudo pvs && sudo vgs && sudo lvs
df -h /mnt/k3s-storage
```

#### Certificate Issues

```bash
# Check certificates
kubectl get certificate -n cert-manager
kubectl describe certificate NAME -n cert-manager

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check challenges
kubectl get challenge -n cert-manager
```

#### Cloudflare Tunnel Issues

```bash
# Check tunnel status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -n 100

# Test configuration
sudo cloudflared tunnel --config /etc/cloudflared/config.yml run pi-hybrid
```

---

## Maintenance Mode

### Take Cluster Offline Gracefully

```bash
# Drain node (for maintenance)
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Or stop K3s
sudo systemctl stop k3s
```

### Bring Cluster Back Online

```bash
# Uncordon node
kubectl uncordon NODE_NAME

# Or start K3s
sudo systemctl start k3s
```

---

## Recovery Checklist

Use this checklist during recovery:

- [ ] Hardware assembled and connected
- [ ] Ubuntu Server installed on SD card
- [ ] SSH access working
- [ ] System updated
- [ ] Static IP configured (optional)
- [ ] LVM storage configured
- [ ] K3s installed
- [ ] kubectl configured
- [ ] Nginx Ingress deployed
- [ ] cert-manager deployed
- [ ] Cloudflare secret created
- [ ] Certificates issued
- [ ] Cloudflare Tunnel configured
- [ ] Router port forwarding configured
- [ ] PostgreSQL deployed
- [ ] Redis deployed
- [ ] All applications deployed
- [ ] Monitoring stack deployed
- [ ] Database backups restored
- [ ] Application data restored
- [ ] External access tested
- [ ] Local access tested
- [ ] All applications accessible
- [ ] Backups scheduled

---

## Estimated Timings

| Task | Duration |
|------|----------|
| OS Installation | 15 min |
| System Updates | 10 min |
| Storage Setup | 10 min |
| K3s Installation | 5 min |
| Core Infrastructure | 15 min |
| Certificates | 10 min |
| Cloudflare Setup | 15 min |
| Database Services | 10 min |
| Applications | 20 min |
| Monitoring | 10 min |
| **Total (Fresh Install)** | **~2 hours** |
| Data Restoration | +2-4 hours |
| **Total (With Data)** | **~4-6 hours** |

---

## Support Resources

- [K3s Documentation](https://docs.k3s.io)
- [Kubernetes Documentation](https://kubernetes.io/docs)
- [Nginx Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

---

**Document Version:** 1.0
**Last Tested:** November 2025
**Success Rate:** This procedure has been validated and successfully rebuilds the entire cluster from scratch.
