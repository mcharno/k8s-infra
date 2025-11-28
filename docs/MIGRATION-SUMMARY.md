# Migration Summary: docs → infra-k8s

This document summarizes the migration of all infrastructure documentation and scripts from the `docs/` directory into the structured `infra-k8s` repository.

**Migration Date:** November 2025
**Source:** `/Users/charno/projects/homelab/docs/`
**Destination:** `/Users/charno/projects/homelab/infra-k8s/`

---

## Overview

The docs directory contained 120+ bash scripts, YAML files, and markdown documents from the actual K3s cluster build. This migration extracts the key configurations and transforms them into:

1. **Deployable Kubernetes manifests** (Kustomize-based)
2. **Comprehensive documentation** (disaster recovery, setup guides, troubleshooting)
3. **Reusable scripts** (installation, diagnostics, convenience tools)
4. **Workflow documentation** (GitOps, CI/CD)

---

## Key Infrastructure Components

### 1. K3s Cluster (Raspberry Pi 4 - 8GB)

**Source:** `docs/k3s-install.sh`
**Destination:** `scripts/k3s/install-k3s.sh`

**Configuration:**
- Traefik disabled (using Nginx Ingress)
- ServiceLB disabled
- Max pods: 110
- Memory reserved: 1GB (512Mi system + 512Mi kubelet)
- CPU reserved: 400m (200m system + 200m kubelet)
- Eviction thresholds: Aggressive (prevent OOM)
- Storage: local-path-provisioner → `/mnt/k3s-storage`

**Key Settings:**
```bash
--disable traefik
--disable servicelb
--kubelet-arg='max-pods=110'
--kubelet-arg='kube-reserved=cpu=200m,memory=512Mi'
--kubelet-arg='system-reserved=cpu=200m,memory=512Mi'
```

###2. Storage Setup (LVM - Dual SSDs)

**Source:** `docs/lvm-setup.sh`, `docs/storage_provisioner_complete.sh`
**Destination:** `scripts/storage/setup-lvm.sh`

**Configuration:**
- Drive 1: `/dev/sda` (1TB SSD)
- Drive 2: `/dev/sdb` (2TB SSD)
- Combined: ~2.7TB using LVM
- Volume Group: `k3s-storage`
- Logical Volume: `data`
- Mounted: `/mnt/k3s-storage`
- Filesystem: ext4

**Key Learning:**
- local-path-provisioner works with `volumeBindingMode: WaitForFirstConsumer`
- Storage must be pre-created at `/mnt/k3s-storage/local-path-provisioner/`

### 3. Network Architecture (Hybrid HTTPS)

**Source:** `docs/homelab-network/`, `docs/network-setup/`
**Destination:** `docs/network-setup.md`, `infrastructure/network/`

**External Access (Cloudflare Tunnel):**
- All `*.charn.io` domains
- All `*.charno.net` domains
- Traffic: User → Cloudflare Edge → Tunnel → cloudflared (Pi) → Nginx Ingress :30280 (HTTP)
- Benefits: Hidden IP, DDoS protection, no port forwarding

**Local Access (Direct):**
- All `*.local.charn.io` domains
- Traffic: User → Router:443 → Pi:30443 → Nginx Ingress (HTTPS)
- Benefits: Low latency, works without internet

**Critical Configuration:**
```yaml
# Nginx Ingress ConfigMap
ssl-redirect: "false"  # CRITICAL - prevents 308 loops with Cloudflare Tunnel
use-forwarded-headers: "true"
```

**Why ssl-redirect must be false:**
- Cloudflare terminates HTTPS → sends HTTP to tunnel
- If Nginx redirects HTTP → HTTPS, creates infinite loop
- Security maintained: Cloudflare enforces HTTPS externally

### 4. SSL Certificates (Let's Encrypt)

**Source:** `docs/homelab-network/hybrid-wildcard-certificates.yaml`
**Destination:** `infrastructure/cert-manager/`

**Certificates:**
1. `*.charn.io` - DNS-01 challenge (Cloudflare API)
2. `*.local.charn.io` - DNS-01 challenge (Cloudflare API)
3. `*.charno.net` - DNS-01 challenge (Cloudflare API)

**Note:** Originally considered HTTP-01 for local certs, but DNS-01 used for all (cleaner)

**Configuration:**
- ClusterIssuer: `letsencrypt-cloudflare-prod`
- Solver: DNS-01 via Cloudflare API
- Auto-renewal: 30 days before expiry
- Certificate sharing: Wildcard certs copied to all app namespaces

### 5. Shared PostgreSQL Database

**Source:** `docs/install_shared_postgres.sh`
**Destination:** `infrastructure/databases/postgres/`

**Configuration:**
- Image: `postgres:15-alpine`
- Namespace: `database`
- Storage: 30Gi PVC
- Resources: 256Mi-1Gi RAM, 250m-1000m CPU

**Databases Created:**
- `nextcloud` → user: `nextcloud`
- `wallabag` → user: `wallabag`

**Connection String:**
```
postgres-lb.database.svc.cluster.local:5432/DATABASE_NAME
```

**Benefits:**
- Before: 3 PostgreSQL instances = 768Mi RAM
- After: 1 PostgreSQL instance = 256Mi RAM
- Saved: ~512Mi RAM, ~500m CPU

### 6. Applications Deployed

| Application | Port | Description | Database |
|-------------|------|-------------|----------|
| Homer | 30800 | Dashboard | None |
| Nextcloud | 30080 | File storage | PostgreSQL (shared) |
| Jellyfin | 30096 | Media server | None |
| Home Assistant | 30123 | Smart home | SQLite |
| Wallabag | 30086 | Read later | PostgreSQL (shared) |
| Grafana | 30300 | Monitoring | None |
| Prometheus | 30090 | Metrics | None |
| K8s Dashboard | 30000 | Cluster UI | None |

### 7. Monitoring Stack

**Source:** `docs/install_prometheus_grafana.sh`
**Destination:** `apps/prometheus/`, `apps/grafana/`

**Prometheus Configuration:**
- Scrapes: Kubernetes API, nodes, pods
- Custom scrapes: Home Assistant, node-exporter
- Storage: 20Gi PVC, 30-day retention
- Resources: 256Mi-1Gi RAM

**Grafana:**
- Datasource: Prometheus (auto-configured)
- Storage: 10Gi PVC
- Default: admin/admin (change on first login)
- Recommended dashboards: 315, 6417, 1860

---

## Migration Tracking

### ✅ Completed

- [x] Disaster recovery documentation
- [x] K3s installation script
- [x] Storage setup script (LVM)
- [x] Network architecture documentation (in docs/)

### 🚧 In Progress

- [ ] Application manifest files (base Kustomize structure)
- [ ] Complete network setup guide
- [ ] Deployment workflow documentation

### 📝 To Do

#### Infrastructure Manifests

- [ ] Nginx Ingress (complete with ConfigMap for ssl-redirect: false)
- [ ] cert-manager (ClusterIssuers + Certificates)
- [ ] Shared PostgreSQL (complete with init scripts)
- [ ] Redis cache
- [ ] Storage class configuration

#### Application Manifests

Each app needs:
- Namespace
- Deployment/StatefulSet
- Service
- PersistentVolumeClaim
- ConfigMap (if needed)
- Secret placeholders
- Ingress (external + local)

Applications:
- [ ] Homer
- [ ] Nextcloud
- [ ] Jellyfin
- [ ] Home Assistant
- [ ] Wallabag
- [ ] Prometheus
- [ ] Grafana

#### Documentation

- [ ] Network setup complete guide (Cloudflare Tunnel + local access)
- [ ] Certificate management guide
- [ ] Application configuration guide (trusted domains, proxies)
- [ ] Backup and restore procedures
- [ ] Troubleshooting guide (consolidate from fix-* scripts)
- [ ] Deployment workflow (GitHub Actions → ArgoCD)

#### Scripts

**Convenience Scripts:**
- [ ] `scripts/deploy-all.sh` - Deploy entire stack in order
- [ ] `scripts/backup/backup-postgres.sh` - Backup all databases
- [ ] `scripts/backup/backup-volumes.sh` - Backup PVCs
- [ ] `scripts/restore/restore-postgres.sh` - Restore databases
- [ ] `scripts/restore/restore-volumes.sh` - Restore PVCs

**Diagnostic Scripts:**
- [ ] `scripts/diag/check-cluster.sh` - Overall health check
- [ ] `scripts/diag/check-network.sh` - Network/ingress diagnostics
- [ ] `scripts/diag/check-storage.sh` - Storage/PVC diagnostics
- [ ] `scripts/diag/check-certs.sh` - Certificate status

**Fix Scripts:**
- [ ] `scripts/fix/fix-nginx-redirect.sh` - Fix 308 redirect loops
- [ ] `scripts/fix/fix-cert-renewal.sh` - Force cert renewal
- [ ] `scripts/fix/restart-app.sh APP_NAME` - Graceful app restart

---

## Key Learnings from docs/

### What Worked Well

1. **Cloudflare Tunnel** - Excellent for external access without exposing IP
2. **Shared PostgreSQL** - Significant resource savings
3. **LVM Storage** - Flexible, easy to manage
4. **Hybrid network** - Best of both worlds (fast local, secure external)
5. **Wildcard certificates** - Easy management, single cert per domain

### Common Issues & Solutions

#### 1. 308 Redirect Loop

**Problem:** Cloudflare Tunnel sends HTTP → Nginx redirects to HTTPS → loop

**Solution:**
```yaml
# Nginx Ingress ConfigMap
ssl-redirect: "false"
force-ssl-redirect: "false"
```

**Files showing this:**
- `docs/network-setup/nginx-fix.sh`
- `docs/fix-mounts.sh`
- Multiple `diag-308.sh` scripts

#### 2. Storage Binding with local-path-provisioner

**Problem:** PVCs stuck in Pending

**Solution:**
```yaml
volumeBindingMode: WaitForFirstConsumer
```

**Files showing this:**
- `docs/storage_provisioner_complete.sh`
- `docs/storage_binding_fix.sh`

**Reason:** local-path-provisioner needs pod scheduled first to know which node

#### 3. Nextcloud Trusted Domains

**Problem:** "Access through untrusted domain" errors

**Solution:**
```yaml
env:
  - name: NEXTCLOUD_TRUSTED_DOMAINS
    value: "nextcloud.charn.io nextcloud.local.charn.io"
  - name: OVERWRITEPROTOCOL
    value: "https"
  - name: TRUSTED_PROXIES
    value: "10.42.0.0/16"
```

**Files showing this:**
- `docs/fix_nextcloud_500.sh`
- `docs/investigate_nextcloud_500.sh`

#### 4. Wallabag Database

**Problem:** Database configuration challenges

**Solution:** Shared PostgreSQL with specific env vars

**Files:**
- `docs/apps-wallabag.sh`
- `docs/app-wallabag-diag.sh`

---

## File Categorization from docs/

### Core Infrastructure
- `k3s-install.sh` ✅ → `scripts/k3s/install-k3s.sh`
- `lvm-setup.sh` ✅ → `scripts/storage/setup-lvm.sh`
- `storage_provisioner_complete.sh` → documented in disaster recovery
- `drives-setup.sh` → similar to lvm-setup.sh

### Network Setup
- `homelab-network/hybrid-setup-guide.md` → need to migrate
- `homelab-network/hybrid-deploy.sh` → extract configs
- `network-setup/hybrid-*.{yaml,sh}` → extract configs
- `argocd/setup-local.sh` → need to create

### Database
- `install_shared_postgres.sh` → create manifests
- `migrate_to_shared_postgres.sh` → document in migration guide

### Applications (Latest Versions)
- `install_homer.sh` → create manifest
- `install_nextcloud.sh` → create manifest (note: uses shared DB now)
- `install_jellyfin.sh` → create manifest
- `install_homeassistant_{minimal,simple}.sh` → use simple version
- `install_wallabag.sh` → create manifest
- `install_prometheus_grafana.sh` → create manifests

### Monitoring
- `install_prometheus_grafana.sh` → create manifests
- `k3s-monitor.sh` → extract useful commands for docs

### Diagnostics (Extract Commands)
- `diag-network.sh` → add to diag scripts
- `diag_nextcloud.sh` → add to troubleshooting
- `diag_provisioner.sh` → add to troubleshooting
- `diag_pvc.sh` → add to troubleshooting
- `k3s-diag.sh` → add to diag scripts
- `pihole/troubleshooting_guide.sh` → extract useful patterns

### Fix Scripts (Document Solutions)
- `fix-mounts.sh` → document solution
- `fix_nextcloud_500.sh` → document solution
- `network-setup/nginx-fix.sh` → critical (ssl-redirect fix)

### Pi-hole/DNS (Optional - Not Currently Used)
- `pihole/*` → Document as alternative to Cloudflare DNS
- Could be useful for fully local setup

### Cleanup Scripts (Archive Reference)
- `cleanup*.sh` → reference for troubleshooting
- `deep-clean.sh` → reference for reset procedures
- `lvm-cleanup.sh` → reference

---

## Manifest Structure to Create

Using Kustomize pattern:

```
apps/
├── APP_NAME/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml (or statefulset.yaml)
│   │   ├── service.yaml
│   │   ├── pvc.yaml
│   │   ├── configmap.yaml (if needed)
│   │   ├── ingress-external.yaml
│   │   └── ingress-local.yaml
│   └── README.md
```

### Example: Nextcloud Structure

```yaml
# apps/nextcloud/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: nextcloud

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - pvc.yaml
  - configmap.yaml
  - ingress-external.yaml
  - ingress-local.yaml

configMapGenerator:
  - name: nextcloud-config
    literals:
      - POSTGRES_HOST=postgres-lb.database.svc.cluster.local
      - POSTGRES_DB=nextcloud
      - OVERWRITEPROTOCOL=https
      - TRUSTED_PROXIES=10.42.0.0/16

secretGenerator:
  - name: nextcloud-secrets
    literals:
      - admin-password=CHANGEME  # Generated during install
```

---

## Priority Order for Completion

### Phase 1: Core Infrastructure (Week 1)
1. ✅ Disaster recovery doc
2. Network setup complete guide
3. Nginx Ingress manifests + ConfigMap
4. cert-manager manifests
5. Storage configuration

### Phase 2: Database & Essential Apps (Week 1-2)
1. Shared PostgreSQL manifests
2. Redis manifests
3. Homer (dashboard)
4. Nextcloud (most complex app)
5. Monitoring (Prometheus + Grafana)

### Phase 3: Remaining Apps (Week 2)
1. Jellyfin
2. Home Assistant
3. Wallabag

### Phase 4: Automation & Scripts (Week 3)
1. Deployment workflow docs (GitHub Actions + ArgoCD)
2. Convenience scripts
3. Diagnostic scripts
4. Backup/restore scripts

### Phase 5: Documentation Polish (Week 3-4)
1. Troubleshooting guide
2. Application configuration guide
3. Update main README
4. Create quick-start guide

---

## Testing Strategy

### Validation Steps

After each app manifest creation:

1. **Syntax Check**
```bash
kubectl apply -k apps/APP_NAME/base/ --dry-run=client
```

2. **Deployment Test** (on test cluster)
```bash
kubectl apply -k apps/APP_NAME/base/
kubectl wait --for=condition=Ready pod -l app=APP_NAME -n NAMESPACE --timeout=300s
```

3. **Access Test**
```bash
# External
curl -I https://APP.charn.io

# Local
curl -I https://APP.local.charn.io
```

4. **Functionality Test**
- Login with credentials
- Verify database connection (if applicable)
- Test core features

### Full Stack Test

After all manifests created, test complete deployment:

```bash
# Fresh K3s cluster
./scripts/k3s/install-k3s.sh

# Deploy infrastructure
kubectl apply -k infrastructure/ingress-nginx/
kubectl apply -k infrastructure/cert-manager/
kubectl apply -k infrastructure/databases/postgres/
kubectl apply -k infrastructure/databases/redis/

# Deploy apps
for app in apps/*/base; do
  kubectl apply -k "$app"
done

# Wait and verify
./scripts/diag/check-cluster.sh
```

---

## Success Criteria

Migration is complete when:

- [ ] All scripts from docs/ are either migrated or documented
- [ ] All applications have Kustomize manifests
- [ ] Disaster recovery guide tested successfully
- [ ] Network setup (Cloudflare + local) fully documented
- [ ] Deployment workflow (GitOps) documented
- [ ] Diagnostic and convenience scripts created
- [ ] Main README updated with clear structure
- [ ] No references to old docs/ paths in infra-k8s
- [ ] Fresh deployment works end-to-end from infra-k8s alone

---

## Notes for Future

### What to Keep from docs/

The `docs/` directory is valuable history showing:
- Evolution of solutions
- Troubleshooting approaches
- Alternative configurations tried
- Diagnostic techniques

**Recommendation:** Keep `docs/` as archive, but infra-k8s is source of truth.

### What Makes This Different from Generic K8s

1. **Raspberry Pi Specific:** Memory/CPU tuning, ARM images
2. **Hybrid Network:** Unique Cloudflare Tunnel + local access pattern
3. **Resource Constrained:** Shared PostgreSQL, careful resource limits
4. **Home Lab Focus:** NodePort services, local storage, single node
5. **LVM Setup:** Dual SSD combination for maximum storage

---

**Migration Started:** November 25, 2025
**Current Status:** Disaster recovery complete, manifests in progress
**Next Priority:** Network setup guide + Nginx Ingress manifests
