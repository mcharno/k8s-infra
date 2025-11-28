# Documentation Index

Complete documentation for the K3s homelab infrastructure on Raspberry Pi 4.

**Quick Links:**
- **[↩️ Back to Main README](../README.md)**
- **[🆘 Start Here: Disaster Recovery Guide](disaster-recovery.md)** - Complete cluster rebuild
- **[⚡ Quick Start Guide](quick-start-guide.md)** - Step-by-step deployment

---

## 📚 Table of Contents

### 🚀 Getting Started

| Document | Description | When to Use |
|----------|-------------|-------------|
| **[Quick Start Guide](quick-start-guide.md)** | Step-by-step deployment walkthrough with verification at each phase | First-time setup or learning the deployment process |
| **[Getting Started](../../docs/getting-started.md)** | Guide to populating this repository with your current Kubernetes configurations | Migrating existing cluster to GitOps |
| **[Disaster Recovery Guide](disaster-recovery.md)** | Complete cluster rebuild from scratch (2-4 hours) | Hardware failure, corruption, or clean slate rebuild |
| **[Migration Summary](MIGRATION-SUMMARY.md)** | Overview of infrastructure components and architecture decisions | Understanding design choices and component selection |

### 🏗️ Infrastructure Documentation

Complete documentation for each infrastructure component, moved from individual component READMEs into this central location.

#### Core Infrastructure

| Component | Documentation | Description |
|-----------|--------------|-------------|
| **Storage** | [infrastructure/storage.md](infrastructure/storage.md) | local-path-provisioner, LVM setup, WaitForFirstConsumer mode |
| **Networking** | [infrastructure/network.md](infrastructure/network.md) | Cloudflare Tunnel, hybrid access, cloudflared configuration |
| **Nginx Ingress** | [infrastructure/ingress-nginx.md](infrastructure/ingress-nginx.md) | Ingress controller, SSL redirect configuration, NodePorts |
| **cert-manager** | [infrastructure/cert-manager.md](infrastructure/cert-manager.md) | Let's Encrypt SSL, DNS-01 challenges, wildcard certificates |

#### Databases

| Component | Documentation | Description |
|-----------|--------------|-------------|
| **PostgreSQL** | [infrastructure/postgres.md](infrastructure/postgres.md) | Shared PostgreSQL 15 instance for multiple apps (~512MB RAM savings) |
| **Redis** | [infrastructure/redis.md](infrastructure/redis.md) | Redis 7 cache with LRU eviction, RDB + AOF persistence |

**Why shared PostgreSQL?**
- **Before:** 3 separate instances (768Mi RAM total)
- **After:** 1 shared instance (256Mi RAM)
- **Savings:** ~512MB RAM for a resource-constrained Pi

### 📱 Application Documentation

Documentation for deployed applications, also moved from individual application directories.

| Application | Documentation | Description |
|-------------|--------------|-------------|
| **Homer Dashboard** | [applications/homer.md](applications/homer.md) | Central dashboard, configuration, icons, customization |

**Coming soon:**
- Nextcloud (file storage)
- Jellyfin (media server)
- Home Assistant (smart home)
- Wallabag (read-it-later)
- Prometheus (metrics)
- Grafana (monitoring)

### 🌐 Network Architecture

Comprehensive documentation about the hybrid network setup.

| Document | Description | Key Topics |
|----------|-------------|------------|
| **[Network Setup Guide](network-setup.md)** | Complete Cloudflare Tunnel + local access configuration | Installation, DNS routing, troubleshooting |
| **[Network Architecture Diagrams](network-architecture-diagrams.md)** | Visual diagrams of network topology | External flow, local flow, certificate paths |
| **[Network Overview](network-overview.md)** | Detailed network documentation | Hybrid architecture benefits, domain setup |

**Network Patterns:**
- **External:** `*.charn.io`, `*.charno.net` → Cloudflare Tunnel → Apps
- **Local:** `*.local.charn.io` → Direct HTTPS → Apps

### 🚢 Deployment & Operations

| Document | Description | Key Topics |
|----------|-------------|------------|
| **[Deployment Workflow](deployment-workflow.md)** | GitHub Actions + ArgoCD GitOps workflow | PR validation, automated deployment, rollbacks |
| **[ArgoCD Setup](argocd-setup.md)** | ArgoCD installation and configuration | App-of-apps pattern, sync policies |
| **[ArgoCD GitOps](argocd-gitops.md)** | GitOps integration with GitHub Actions | Multi-environment strategies, secrets management |
| **[ArgoCD + GitHub Actions Integration](../../docs/argocd-github-actions.md)** | Complete guide for ArgoCD + GitHub Actions GitOps | Build, push, update manifests, auto-sync |
| **[GitHub Actions](github-actions.md)** | CI/CD pipeline configuration | Validation, deployment, RBAC |
| **[GitHub Actions CI/CD Setup](../../docs/github-actions-ci-cd.md)** | Automated deployment setup for k3s cluster | RBAC, kubeconfig secrets, workflows |

### 🔧 Operations & Troubleshooting

| Document | Description | Key Topics |
|----------|-------------|------------|
| **[Quick Reference](quick-reference.md)** | Common kubectl commands and operations | Pod management, logs, storage, certificates |
| **[Troubleshooting Guide](troubleshooting.md)** | Common issues and solutions | 308 loops, PVC pending, certificate issues |
| **[Samba File Share](samba-share.md)** | LAN file sharing setup | Windows, macOS, Linux connections |

### 📊 Architecture & Design

| Document | Description | Key Topics |
|----------|-------------|------------|
| **[Architecture Overview](architecture.md)** | Complete system architecture | Components, data flow, technology stack |

---

## 🎯 Documentation by Use Case

### I want to... deploy the cluster from scratch

**Start here:**
1. **[Quick Start Guide](quick-start-guide.md)** - Follow phase by phase
2. **[Disaster Recovery Guide](disaster-recovery.md)** - If you need detailed recovery steps

**Then configure:**
- **[Network Setup](network-setup.md)** - Cloudflare Tunnel + local access
- **[Storage](infrastructure/storage.md)** - LVM and provisioner setup

**Finally deploy:**
- Infrastructure components using Kustomize
- Applications one by one
- Verify with **[Quick Reference](quick-reference.md)** commands

### I want to... understand the architecture

**Read in this order:**
1. **[Migration Summary](MIGRATION-SUMMARY.md)** - High-level decisions
2. **[Architecture Overview](architecture.md)** - Detailed system design
3. **[Network Architecture Diagrams](network-architecture-diagrams.md)** - Visual topology
4. Component-specific docs in `infrastructure/` directory

### I want to... troubleshoot an issue

**Start with:**
1. **[Troubleshooting Guide](troubleshooting.md)** - Common issues
2. **[Quick Reference](quick-reference.md)** - Diagnostic commands

**Component-specific:**
- Storage issues → **[infrastructure/storage.md](infrastructure/storage.md)**
- Network/SSL issues → **[infrastructure/network.md](infrastructure/network.md)** or **[infrastructure/ingress-nginx.md](infrastructure/ingress-nginx.md)**
- Certificate issues → **[infrastructure/cert-manager.md](infrastructure/cert-manager.md)**
- Database issues → **[infrastructure/postgres.md](infrastructure/postgres.md)** or **[infrastructure/redis.md](infrastructure/redis.md)**

### I want to... deploy or update an application

**Deployment:**
1. **[Deployment Workflow](deployment-workflow.md)** - Understand the flow
2. **[ArgoCD GitOps](argocd-gitops.md)** - GitOps patterns
3. Application-specific docs in `applications/` directory

**Example: Deploy Homer:**
```bash
kubectl apply -k applications/homer/
```
See: **[applications/homer.md](applications/homer.md)**

### I want to... configure network access

**External access (Cloudflare Tunnel):**
1. **[Network Setup Guide](network-setup.md)** - Complete walkthrough
2. **[infrastructure/network.md](infrastructure/network.md)** - Detailed configuration
3. **[infrastructure/ingress-nginx.md](infrastructure/ingress-nginx.md)** - Critical SSL redirect settings

**Local access:**
1. **[Network Setup Guide](network-setup.md)** - Router configuration
2. **[infrastructure/cert-manager.md](infrastructure/cert-manager.md)** - Local wildcard certificates
3. Configure local DNS (Pi-hole or hosts file)

### I want to... manage certificates

**Setup:**
1. **[infrastructure/cert-manager.md](infrastructure/cert-manager.md)** - Installation and configuration
2. **[Network Setup Guide](network-setup.md)** - Cloudflare API token setup

**Troubleshooting:**
```bash
kubectl get certificate -n cert-manager
kubectl describe certificate CERT_NAME -n cert-manager
```
See: **[infrastructure/cert-manager.md](infrastructure/cert-manager.md)** troubleshooting section

### I want to... manage storage

**Understanding:**
1. **[infrastructure/storage.md](infrastructure/storage.md)** - Complete storage guide
2. **[Quick Start Guide](quick-start-guide.md)** - Phase 1: Storage setup

**Key concepts:**
- `volumeBindingMode: WaitForFirstConsumer` - Why it's required
- LVM setup - How dual SSDs are combined
- Testing - Verify provisioner works

**Troubleshooting:**
- PVC stuck in Pending → **[infrastructure/storage.md](infrastructure/storage.md)** troubleshooting section

---

## 📖 Documentation Conventions

### File Organization

**Location:**
- `docs/` - All documentation (this directory)
- `docs/infrastructure/` - Infrastructure component documentation
- `docs/applications/` - Application documentation

**Naming:**
- Component docs: `COMPONENT_NAME.md` (e.g., `postgres.md`, `redis.md`)
- Application docs: `APP_NAME.md` (e.g., `homer.md`)
- Guides: Descriptive names (e.g., `quick-start-guide.md`)

### Structure

Each component/application documentation includes:
1. **Overview** - What is it and why?
2. **Deployment** - How to install
3. **Configuration** - How to customize
4. **Operations** - Common tasks
5. **Troubleshooting** - Common issues
6. **References** - External links

### Code Blocks

```bash
# Example command with explanation
kubectl get pods -n namespace

# What it does:
# Lists all pods in the specified namespace
```

### Links

- Internal: `[Link Text](path/to/file.md)`
- Sections: `[Link Text](file.md#section-name)`
- External: Full URLs to upstream docs

---

## 🗂️ Complete File List

### Core Guides

```
docs/
├── README.md                          (this file)
├── quick-start-guide.md              Complete deployment walkthrough
├── disaster-recovery.md              Rebuild cluster from scratch
├── MIGRATION-SUMMARY.md              Architecture decisions and migration tracking
└── deployment-workflow.md            GitOps workflow
```

### Infrastructure Documentation

```
docs/infrastructure/
├── storage.md                        Storage provisioner, LVM, WaitForFirstConsumer
├── network.md                        Cloudflare Tunnel, hybrid access
├── ingress-nginx.md                  Nginx Ingress, SSL redirect, NodePorts
├── cert-manager.md                   SSL certificates, DNS-01, wildcards
├── postgres.md                       Shared PostgreSQL instance
└── redis.md                          Redis cache configuration
```

### Application Documentation

```
docs/applications/
└── homer.md                          Homer dashboard
```

### Network Documentation

```
docs/
├── network-setup.md                  Complete network configuration guide
├── network-architecture-diagrams.md  Visual network topology
└── network-overview.md               Detailed network documentation
```

### Operations Documentation

```
docs/
├── quick-reference.md                Common kubectl commands
├── troubleshooting.md                Common issues and solutions
├── samba-share.md                    LAN file sharing
├── argocd-setup.md                   ArgoCD installation
├── argocd-gitops.md                  GitOps integration
├── github-actions.md                 CI/CD pipelines
└── architecture.md                   System architecture
```

### Additional Guides (in central docs/)

```
../../docs/
├── getting-started.md                Guide to populating repo with existing configs
├── argocd-github-actions.md          Complete ArgoCD + GitHub Actions integration
└── github-actions-ci-cd.md           GitHub Actions CI/CD setup for k3s
```

---

## 🔄 Documentation Updates

**When to update documentation:**
- Adding new infrastructure component → Create `docs/infrastructure/COMPONENT.md`
- Adding new application → Create `docs/applications/APP.md`
- Changing architecture → Update `MIGRATION-SUMMARY.md` and component docs
- New troubleshooting pattern → Update `troubleshooting.md`

**Documentation workflow:**
1. Update component-specific documentation
2. Update this index (docs/README.md)
3. Update main README.md if needed
4. Test all links

---

## 🆘 Getting Help

### Documentation Priority

**For quick answers:**
1. **[Quick Reference](quick-reference.md)** - Commands
2. **[Troubleshooting](troubleshooting.md)** - Known issues

**For understanding:**
1. **[Migration Summary](MIGRATION-SUMMARY.md)** - High-level overview
2. **[Architecture](architecture.md)** - Detailed design
3. Component-specific docs

**For deployment:**
1. **[Quick Start Guide](quick-start-guide.md)** - Step-by-step
2. **[Disaster Recovery](disaster-recovery.md)** - Complete rebuild
3. **[Deployment Workflow](deployment-workflow.md)** - GitOps

### Upstream Documentation

- **[K3s Documentation](https://docs.k3s.io)**
- **[Kubernetes Documentation](https://kubernetes.io/docs)**
- **[Nginx Ingress](https://kubernetes.github.io/ingress-nginx/)**
- **[cert-manager](https://cert-manager.io/)**
- **[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)**
- **[Kustomize](https://kustomize.io/)**
- **[ArgoCD](https://argo-cd.readthedocs.io/)**

---

## 📝 Summary

**Total Documentation Files:** 20+ comprehensive guides

**Infrastructure Coverage:**
- ✅ Storage (LVM + local-path-provisioner)
- ✅ Networking (Cloudflare Tunnel + local)
- ✅ Ingress (Nginx with critical configs)
- ✅ Certificates (cert-manager + Let's Encrypt)
- ✅ Databases (PostgreSQL + Redis)

**Application Coverage:**
- ✅ Homer (dashboard)
- 🚧 More applications coming soon

**Operations Coverage:**
- ✅ Deployment workflows
- ✅ Troubleshooting guides
- ✅ Quick reference commands
- ✅ Disaster recovery procedures

**All documentation is:**
- 📖 Comprehensive with examples
- 🔧 Practical with real commands
- 🆘 Troubleshooting-focused
- 🔗 Cross-referenced
- ✅ Battle-tested on real hardware

---

**Last Updated:** November 2025
**Status:** Production Ready ✅

For questions or improvements, see the main [README.md](../README.md).
