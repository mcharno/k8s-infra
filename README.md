# K3s Homelab Infrastructure

Complete Kubernetes infrastructure for a Raspberry Pi 4 homelab with production-grade practices, hybrid HTTPS access, and comprehensive documentation.

**Platform:** Raspberry Pi 4 (8GB RAM, 4 CPU cores)
**Storage:** 2.7TB LVM (Dual SSDs: 1TB + 2TB)
**Network:** Hybrid (Cloudflare Tunnel + Direct Local Access)
**Status:** Production Ready ✅

---

## 🎯 What is This?

This repository contains **everything** needed to deploy and maintain a complete K3s homelab cluster on a Raspberry Pi 4, including:

- ✅ Complete infrastructure manifests (Nginx, cert-manager, databases, storage)
- ✅ Application deployments with Kustomize
- ✅ Installation scripts for automated setup
- ✅ Comprehensive documentation for disaster recovery
- ✅ GitOps-ready with ArgoCD
- ✅ Hybrid network architecture (external + local HTTPS access)

**Goal:** Rebuild the entire cluster from scratch in 2-4 hours using only this repository.

---

## 🚀 Quick Start

### Fresh Installation

```bash
# 1. Setup storage (LVM across dual SSDs)
sudo bash scripts/storage/setup-lvm.sh

# 2. Install K3s (optimized for Raspberry Pi)
sudo bash scripts/k3s/install-k3s.sh

# 3. Deploy core infrastructure
kubectl apply -k infrastructure/ingress-nginx/
kubectl apply -k infrastructure/cert-manager/
kubectl apply -k infrastructure/databases/postgres/
kubectl apply -k infrastructure/databases/redis/

# 4. Configure network (Cloudflare Tunnel)
bash infrastructure/network/install-cloudflared.sh

# 5. Deploy applications
kubectl apply -k applications/homer/
# ... deploy more applications
```

### Quick Reference

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# View all applications
kubectl get ingress --all-namespaces

# Check storage
kubectl get pv,pvc --all-namespaces

# View certificates
kubectl get certificate -n cert-manager
```

### Documentation Quick Links

- **[📖 Complete Documentation Index](docs/README.md)** - All documentation with descriptions
- **[🆘 Disaster Recovery Guide](docs/disaster-recovery.md)** - Rebuild from scratch (START HERE)
- **[⚡ Quick Start Guide](docs/quick-start-guide.md)** - Step-by-step deployment walkthrough

---

## 📚 Documentation

### Core Documentation

| Document | Description |
|----------|-------------|
| **[Quick Start Guide](docs/quick-start-guide.md)** | Complete deployment walkthrough with verification steps |
| **[Disaster Recovery](docs/disaster-recovery.md)** | Rebuild entire cluster from scratch in 2-4 hours |
| **[Migration Summary](docs/MIGRATION-SUMMARY.md)** | Architecture decisions and component overview |
| **[Deployment Workflow](docs/deployment-workflow.md)** | GitHub Actions + ArgoCD GitOps workflow |

### Infrastructure Documentation

| Component | Documentation |
|-----------|--------------|
| **Storage** | [docs/infrastructure/storage.md](docs/infrastructure/storage.md) |
| **Networking** | [docs/infrastructure/network.md](docs/infrastructure/network.md) |
| **Nginx Ingress** | [docs/infrastructure/ingress-nginx.md](docs/infrastructure/ingress-nginx.md) |
| **cert-manager** | [docs/infrastructure/cert-manager.md](docs/infrastructure/cert-manager.md) |
| **PostgreSQL** | [docs/infrastructure/postgres.md](docs/infrastructure/postgres.md) |
| **Redis** | [docs/infrastructure/redis.md](docs/infrastructure/redis.md) |

### Application Documentation

| Application | Documentation |
|-------------|--------------|
| **Homer Dashboard** | [docs/applications/homer.md](docs/applications/homer.md) |

### Network Documentation

| Document | Description |
|----------|-------------|
| **[Network Setup Guide](docs/network-setup.md)** | Complete Cloudflare Tunnel + local access configuration |
| **[Network Architecture](docs/network-architecture-diagrams.md)** | Visual diagrams of network topology |
| **[Network Overview](docs/network-overview.md)** | Detailed network documentation |

### Operations Documentation

| Document | Description |
|----------|-------------|
| **[Quick Reference](docs/quick-reference.md)** | Common kubectl commands and operations |
| **[Troubleshooting](docs/troubleshooting.md)** | Common issues and solutions |
| **[Samba File Share](docs/samba-share.md)** | LAN file sharing setup |

**See [docs/README.md](docs/README.md) for the complete documentation index.**

---

## 🏗️ Repository Structure

```
infra-k8s/
├── applications/              # Application deployments (Kustomize)
│   └── homer/                # Homer dashboard
│       ├── namespace.yaml
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress-external.yaml
│       ├── ingress-local.yaml
│       └── kustomization.yaml
│
├── infrastructure/            # Core infrastructure components
│   ├── cert-manager/         # SSL certificate management
│   │   ├── install.sh
│   │   ├── clusterissuers.yaml
│   │   ├── certificates.yaml
│   │   └── create-cloudflare-secret.sh
│   ├── ingress-nginx/        # Nginx Ingress Controller
│   │   ├── install.sh
│   │   ├── configmap.yaml
│   │   └── deployment-patch.yaml
│   ├── network/              # Cloudflare Tunnel configuration
│   │   ├── cloudflared-config.yml
│   │   └── install-cloudflared.sh
│   ├── storage/              # Storage provisioner config
│   │   ├── storageclass.yaml
│   │   ├── local-path-config.yaml
│   │   └── test-storage.sh
│   └── databases/
│       ├── postgres/         # Shared PostgreSQL instance
│       │   ├── namespace.yaml
│       │   ├── statefulset.yaml
│       │   ├── service.yaml
│       │   ├── pvc.yaml
│       │   ├── configmap.yaml
│       │   └── kustomization.yaml
│       └── redis/            # Redis cache
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── pvc.yaml
│           ├── configmap.yaml
│           └── kustomization.yaml
│
├── scripts/                   # Helper and installation scripts
│   ├── k3s/
│   │   └── install-k3s.sh    # K3s installation (Raspberry Pi optimized)
│   ├── storage/
│   │   └── setup-lvm.sh      # Dual SSD LVM setup (2.7TB)
│   ├── databases/
│   │   └── create-postgres-secret.sh
│   └── cert-manager/
│       └── copy-certs-to-namespace.sh
│
├── docs/                      # Documentation (moved from infrastructure/)
│   ├── README.md             # Documentation index
│   ├── quick-start-guide.md  # Step-by-step deployment
│   ├── disaster-recovery.md  # Complete rebuild guide
│   ├── MIGRATION-SUMMARY.md  # Architecture decisions
│   ├── deployment-workflow.md # GitOps workflow
│   ├── infrastructure/       # Infrastructure component docs
│   │   ├── storage.md
│   │   ├── network.md
│   │   ├── ingress-nginx.md
│   │   ├── cert-manager.md
│   │   ├── postgres.md
│   │   └── redis.md
│   ├── applications/         # Application docs
│   │   └── homer.md
│   └── [network docs...]
│
└── .github/
    └── workflows/            # GitHub Actions (future)
```

---

## 🌐 Architecture

### Infrastructure Components

```
Raspberry Pi 4 (8GB RAM, 4 cores)
│
├── K3s Cluster
│   ├── Nginx Ingress Controller (ports 30280 HTTP, 30443 HTTPS)
│   ├── cert-manager (Let's Encrypt wildcard certificates)
│   ├── PostgreSQL 15 (shared instance, saves ~512MB RAM)
│   ├── Redis 7 (200MB cache with LRU eviction)
│   └── local-path-provisioner (WaitForFirstConsumer mode)
│
├── LVM Storage (2.7TB total)
│   ├── /dev/sda (1TB SSD)
│   └── /dev/sdb (2TB SSD)
│   └── Mounted at: /mnt/k3s-storage
│
└── Network Access
    ├── External: Cloudflare Tunnel → *.charn.io, *.charno.net
    └── Local: Direct HTTPS → *.local.charn.io
```

### Network Architecture

**External Access (via Cloudflare Tunnel):**
```
Internet → Cloudflare Edge → Tunnel → cloudflared → Nginx Ingress → Apps
```
- DDoS protection and WAF
- Hidden home IP address
- No port forwarding needed
- Works behind CGNAT/NAT

**Local Access (direct connection):**
```
Home Network → Router:443 → Pi:30443 → Nginx Ingress → Apps
```
- Low latency (<5ms)
- Works offline
- Fast media streaming
- Direct connection

**Domains:**
- `*.charn.io` - Applications (external + local)
- `*.local.charn.io` - Applications (local only)
- `*.charno.net` - Websites (external only)

### Key Features

- ✅ **Hybrid HTTPS:** Best of both worlds (external security + local speed)
- ✅ **Wildcard SSL:** Automatic Let's Encrypt certificates via DNS-01
- ✅ **Shared PostgreSQL:** Single instance for multiple apps (saves ~512MB RAM)
- ✅ **Resource Optimized:** Tuned for Raspberry Pi constraints
- ✅ **GitOps Ready:** Infrastructure as code with Kustomize

---

## 📦 Deployed Applications

| Application | External URL | Local URL | Description |
|-------------|--------------|-----------|-------------|
| Homer | homer.charn.io | homer.local.charn.io | Dashboard |
| Nextcloud | nextcloud.charn.io | nextcloud.local.charn.io | File storage |
| Jellyfin | jellyfin.charn.io | jellyfin.local.charn.io | Media server |
| Home Assistant | home.charn.io | home.local.charn.io | Smart home |
| Wallabag | wallabag.charn.io | wallabag.local.charn.io | Read later |
| Grafana | grafana.charn.io | grafana.local.charn.io | Monitoring |
| Prometheus | prometheus.charn.io | prometheus.local.charn.io | Metrics |

---

## 🔧 Using This Repository

### Prerequisites

**Hardware:**
- Raspberry Pi 4 (8GB RAM recommended)
- 2x USB SSDs (1TB + 2TB used in this setup)
- SD card with Ubuntu Server 22.04 LTS ARM64
- Network connection

**Accounts:**
- Cloudflare account (free tier works)
- Cloudflare API token with DNS:Edit permissions

### Deployment Workflow

**1. Clone repository:**
```bash
git clone https://github.com/mcharno/homelab-infra-k8s.git
cd homelab-infra-k8s
```

**2. Setup infrastructure:**
```bash
# Follow docs/quick-start-guide.md for step-by-step instructions
# Or see docs/disaster-recovery.md for complete rebuild
```

**3. Deploy applications:**
```bash
# Deploy using Kustomize
kubectl apply -k applications/homer/

# Or use ArgoCD (GitOps)
kubectl apply -f argocd/applications/
```

### Working with Kustomize

All infrastructure and applications use Kustomize for configuration management:

```bash
# View what will be deployed
kubectl kustomize infrastructure/ingress-nginx/

# Deploy with Kustomize
kubectl apply -k infrastructure/ingress-nginx/

# Delete resources
kubectl delete -k infrastructure/ingress-nginx/
```

### Common Commands

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check ingresses (URLs)
kubectl get ingress --all-namespaces

# Check certificates
kubectl get certificate -n cert-manager

# View application logs
kubectl logs -f -n NAMESPACE -l app=APP_NAME

# Restart application
kubectl rollout restart deployment/APP_NAME -n NAMESPACE

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

---

## 🔐 Security & Secrets

### Secrets Management

**⚠️ NEVER commit secrets to Git!**

Secrets are:
- Generated during installation by scripts
- Stored as Kubernetes Secrets
- Backed up separately (not in Git)

**Retrieve secrets:**
```bash
kubectl get secret SECRET_NAME -n NAMESPACE -o jsonpath='{.data.KEY}' | base64 -d
```

**Example: PostgreSQL password:**
```bash
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.admin-password}' | base64 -d
```

### Network Security

- ✅ All traffic encrypted (HTTPS/TLS everywhere)
- ✅ Cloudflare DDoS protection and WAF
- ✅ Hidden home IP (external access via tunnel)
- ✅ Let's Encrypt certificates (auto-renewal)
- ✅ Security headers in Nginx
- ⚠️ Consider: Cloudflare Access for zero-trust authentication

---

## 🛠️ Troubleshooting

### Quick Diagnostics

```bash
# Check cluster health
kubectl get nodes
kubectl get componentstatuses

# Check for failed pods
kubectl get pods --all-namespaces | grep -v Running

# Check recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Check storage
kubectl get pv,pvc --all-namespaces
df -h /mnt/k3s-storage
```

### Common Issues

**PVC Stuck in Pending:**
- StorageClass must have `volumeBindingMode: WaitForFirstConsumer`
- PVC waits for pod to be scheduled (this is normal!)
- See: [docs/infrastructure/storage.md](docs/infrastructure/storage.md)

**308 Redirect Loop:**
- Nginx ConfigMap must have `ssl-redirect: "false"`
- Cloudflare Tunnel sends HTTP to Nginx
- See: [docs/infrastructure/ingress-nginx.md](docs/infrastructure/ingress-nginx.md)

**Certificates Not Issuing:**
- Verify Cloudflare API token permissions
- Check cert-manager logs
- See: [docs/infrastructure/cert-manager.md](docs/infrastructure/cert-manager.md)

**Cloudflare Tunnel Not Connecting:**
- Verify tunnel ID in config
- Check credentials file exists
- See: [docs/infrastructure/network.md](docs/infrastructure/network.md)

**Complete troubleshooting:** [docs/troubleshooting.md](docs/troubleshooting.md)

---

## 📊 Resource Usage

### Raspberry Pi 4 (8GB RAM, 4 CPU cores)

```
Total Resources:
├── RAM: 8GB
│   ├── System + Kubelet: ~1GB (reserved)
│   ├── Infrastructure: ~1.5GB (Nginx, cert-manager, databases)
│   ├── Applications: ~5GB
│   └── Available: ~0.5GB buffer
│
└── CPU: 4 cores (ARM Cortex-A72)
    ├── System + Kubelet: ~0.4 cores (reserved)
    ├── Infrastructure: ~0.3 cores
    ├── Applications: ~2.5 cores
    └── Available: ~0.8 cores buffer
```

### Shared PostgreSQL Savings

**Before:** 2 separate PostgreSQL instances
- Nextcloud: 256Mi
- Wallabag: 256Mi
- **Total: 512Mi**

**After:** 1 shared instance
- PostgreSQL 15: 256Mi
- **Saved: ~256Mi RAM** ✅

---

## 🔄 Backup & Restore

### What to Backup

1. **This Repository** (already in Git)
2. **Kubernetes Secrets:**
   ```bash
   kubectl get secrets --all-namespaces -o yaml > secrets-backup.yaml
   ```
3. **PostgreSQL Databases:**
   ```bash
   kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup.sql
   ```
4. **Persistent Volumes:**
   ```bash
   sudo tar -czf pv-backup.tar.gz /mnt/k3s-storage/local-path-provisioner/
   ```

### Disaster Recovery

Complete rebuild procedure: **[docs/disaster-recovery.md](docs/disaster-recovery.md)**

Estimated time: 2-4 hours

---

## 📖 References

**K3s & Kubernetes:**
- [K3s Documentation](https://docs.k3s.io)
- [Kubernetes Documentation](https://kubernetes.io/docs)
- [Kustomize Documentation](https://kustomize.io/)

**Infrastructure Components:**
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Redis Documentation](https://redis.io/docs/)

**Applications:**
- [Homer Dashboard](https://github.com/bastienwirtz/homer)
- [Nextcloud](https://docs.nextcloud.com/)
- [Jellyfin](https://jellyfin.org/docs/)
- [Home Assistant](https://www.home-assistant.io/docs/)
- [Wallabag](https://doc.wallabag.org/)

---

## 🤝 Contributing

This is a personal homelab repository, but you're welcome to:

- ⭐ Star the repo if you find it helpful
- 🐛 Report issues or bugs
- 📖 Suggest documentation improvements
- 🔧 Share your own homelab setup

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Matt Charno**

- Website: https://charno.net
- GitHub: [@mcharno](https://github.com/mcharno)

---

**Status:** Production Ready ✅
**Last Updated:** November 2025
**Cluster:** Running on Raspberry Pi 4 with K3s

---

If you found this helpful, please ⭐ star the repository!

Want to build your own homelab? This repo has everything you need to get started.
