# Architecture Overview

This document provides a comprehensive overview of the k8s infrastructure architecture, including all components, data flows, and integration points.

## Table of Contents

- [System Overview](#system-overview)
- [Component Architecture](#component-architecture)
- [Network Topology](#network-topology)
- [CI/CD Pipeline](#cicd-pipeline)
- [GitOps Workflow](#gitops-workflow)
- [Data Flows](#data-flows)
- [Technology Stack](#technology-stack)
- [Security Architecture](#security-architecture)

## System Overview

The infrastructure is built on k3s (lightweight Kubernetes) with a GitOps-based deployment model using ArgoCD and GitHub Actions for automation.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Internet / WAN                              │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ HTTPS (External access)
                             │
┌────────────────────────────┴────────────────────────────────────────┐
│                     Local Area Network (LAN)                         │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   Developer  │  │   Clients    │  │   Devices    │             │
│  │   Machines   │  │ (Win/Mac/Lin)│  │   (Mobile)   │             │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘             │
│         │                  │                  │                      │
│         │ kubectl/git      │ HTTPS/SMB       │ SMB/HTTPS           │
│         │                  │                  │                      │
│  ┌──────┴──────────────────┴──────────────────┴─────────────────┐  │
│  │                                                                │  │
│  │              k3s Server Node (Single Node)                    │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐ │  │
│  │  │              Ingress Layer (nginx)                       │ │  │
│  │  │  • HTTPS termination                                     │ │  │
│  │  │  • Routing to services                                   │ │  │
│  │  │  • SSL certificates (cert-manager)                       │ │  │
│  │  └────────────┬─────────────────────────────────────────────┘ │  │
│  │               │                                                │  │
│  │  ┌────────────┴─────────────────────────────────────────────┐ │  │
│  │  │          Application Layer (Namespaces)                  │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │  │
│  │  │  │  charno-web │  │  nextcloud  │  │  wallabag   │     │ │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │  │
│  │  │  │ prometheus  │  │   grafana   │  │  jellyfin   │     │ │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │  │
│  │  │  │homeassistant│  │    homer    │  │    samba    │     │ │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │  │
│  │  └───────────────────────────────────────────────────────┘ │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐ │  │
│  │  │        Infrastructure Layer (Namespaces)                 │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │  │
│  │  │  │   ArgoCD    │  │ cert-manager│  │ingress-nginx│     │ │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │  │
│  │  │  │  postgres   │  │    redis    │  │github-actions│    │ │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │  │
│  │  └───────────────────────────────────────────────────────┘ │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐ │  │
│  │  │              Storage Layer                               │ │  │
│  │  │                                                           │ │  │
│  │  │  ┌───────────────────────────────────────────────────┐  │ │  │
│  │  │  │  Host Filesystem (hostPath volumes)              │  │ │  │
│  │  │  │  • /mnt/samba-share (Samba storage)              │  │ │  │
│  │  │  │  • Application persistent volumes                │  │ │  │
│  │  │  └───────────────────────────────────────────────────┘  │ │  │
│  │  └───────────────────────────────────────────────────────┘ │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

                              External
                                 ▲
                                 │
                    ┌────────────┴────────────┐
                    │                         │
              ┌─────────────┐        ┌──────────────┐
              │   GitHub    │        │    GHCR      │
              │ (Git repos) │        │(Container    │
              │             │        │ Registry)    │
              └─────────────┘        └──────────────┘
                     ▲                      ▲
                     │                      │
              ┌──────┴──────┐               │
              │   GitHub    │───────────────┘
              │   Actions   │
              │  (CI/CD)    │
              └─────────────┘
```

## Component Architecture

### Core Components

#### 1. k3s Cluster

**Description:** Lightweight Kubernetes distribution optimized for resource-constrained environments.

**Configuration:**
- Single-node deployment
- Built-in ingress controller (Traefik) disabled in favor of nginx
- Local storage provisioner enabled
- Service load balancer (klipper-lb)

**Resources:**
```yaml
Node Specs:
  - CPU: Multi-core (adjustable based on workload)
  - Memory: 4GB+ recommended
  - Storage: 50GB+ for system and applications
```

#### 2. Ingress NGINX

**Description:** Ingress controller for HTTP/HTTPS traffic routing.

**Namespace:** `ingress-nginx`

**Purpose:**
- Route external traffic to services
- SSL/TLS termination
- Load balancing
- Path-based and host-based routing

**Configuration:**
```yaml
Service Type: LoadBalancer (klipper-lb)
HTTP Port: 80
HTTPS Port: 443
```

#### 3. cert-manager

**Description:** Automated certificate management for Kubernetes.

**Namespace:** `cert-manager`

**Purpose:**
- Automatic SSL/TLS certificate provisioning
- Let's Encrypt integration
- Certificate renewal

**Features:**
- ClusterIssuer for Let's Encrypt
- Automatic certificate injection into Ingresses
- Certificate monitoring and renewal

#### 4. ArgoCD

**Description:** GitOps continuous delivery tool for Kubernetes.

**Namespace:** `argocd`

**Purpose:**
- Automated deployment from Git repositories
- Declarative GitOps
- Application lifecycle management
- Self-healing and auto-sync

**Architecture:**
```
┌──────────────────────────────────────────────────────────┐
│                     ArgoCD                                │
│                                                           │
│  ┌────────────────────┐      ┌────────────────────┐     │
│  │  API Server        │◄────►│  Repo Server       │     │
│  │  (UI/CLI/API)      │      │  (Git sync)        │     │
│  └──────────┬─────────┘      └────────────────────┘     │
│             │                                             │
│  ┌──────────▼─────────┐      ┌────────────────────┐     │
│  │  Application       │      │  Dex Server        │     │
│  │  Controller        │      │  (Auth - optional) │     │
│  │  (Sync engine)     │      └────────────────────┘     │
│  └────────────────────┘                                  │
│             │                                             │
│             ▼                                             │
│     Kubernetes API                                       │
└──────────────────────────────────────────────────────────┘
```

**Access:**
- UI: `https://argocd.yourdomain.com` (via ingress)
- Port-forward: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
- CLI: `argocd` command-line tool

#### 5. Samba File Share

**Description:** SMB/CIFS file sharing service for LAN access.

**Namespace:** `samba`

**Purpose:**
- File sharing across Windows, macOS, Linux, mobile
- Network storage accessible from LAN
- User-authenticated access

**Architecture:**
```
┌─────────────────────────────────────────────────────┐
│              Samba Service                          │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  Samba Pod (dperson/samba)                    │ │
│  │  • SMB/CIFS server                            │ │
│  │  • User authentication                         │ │
│  │  • Share: /storage → "share"                  │ │
│  └─────────────────┬─────────────────────────────┘ │
│                    │                                │
│  ┌─────────────────▼─────────────────────────────┐ │
│  │  PersistentVolumeClaim                        │ │
│  └─────────────────┬─────────────────────────────┘ │
│                    │                                │
└────────────────────┼────────────────────────────────┘
                     │
                     ▼
          ┌────────────────────────┐
          │  hostPath Volume       │
          │  /mnt/samba-share      │
          └────────────────────────┘
```

**Network:**
- NodePort 30445 (SMB/CIFS - port 445)
- NodePort 30137-30139 (NetBIOS)
- LAN-only access (not exposed to internet)

#### 6. GitHub Actions CI/CD

**Description:** Automated deployment pipelines for infrastructure and applications.

**Namespace:** `github-actions` (service account)

**Components:**
- **Workflows:** Defined in `.github/workflows/`
- **Service Account:** `github-actions-deployer`
- **RBAC:** ClusterRole with granular permissions
- **Secrets:** `KUBECONFIG` in GitHub repository

**Workflows:**
```
Infrastructure Deployment:
  • deploy-infrastructure.yaml
  • Deploys: RBAC, ingress, cert-manager, ArgoCD, databases

Application Deployment:
  • deploy-apps.yaml
  • Deploys: Nextcloud, Wallabag, Prometheus, Grafana, etc.

Validation:
  • validate-pr.yaml
  • Validates: YAML, security, secrets, resources

ArgoCD Apps:
  • deploy-argocd-apps.yaml
  • Manages ArgoCD Application manifests
```

### Application Components

#### Web Applications

**charno-web:**
- Personal website
- Deployed via ArgoCD GitOps
- Source: `mcharno/web-app` repository
- Container registry: GitHub Container Registry (GHCR)

**Nextcloud, Wallabag, Homer:**
- Self-hosted productivity applications
- Standard Kubernetes deployments
- Persistent storage via PVCs

#### Monitoring & Observability

**Prometheus:**
- Metrics collection and storage
- Scrapes Kubernetes and application metrics

**Grafana:**
- Metrics visualization
- Dashboards for cluster and application monitoring

#### Media & Home Automation

**Jellyfin:**
- Media server
- Persistent storage for media library

**Home Assistant:**
- Home automation platform
- IoT device integration

### Data Stores

**PostgreSQL:**
- Relational database
- Shared by multiple applications
- Namespace: `postgres`

**Redis:**
- In-memory data store
- Caching and session storage
- Namespace: `redis`

## Network Topology

### Network Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     External Layer                               │
│  • Internet access for pulling images/updates                   │
│  • GitHub (code repositories)                                   │
│  • GHCR (container images)                                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Firewall
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Ingress Layer                                │
│  • NGINX Ingress Controller                                     │
│  • Ports: 80 (HTTP), 443 (HTTPS)                               │
│  • SSL/TLS termination                                          │
│  • Path/host-based routing                                     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Service Layer (ClusterIP)                       │
│  • Internal cluster networking                                  │
│  • Service discovery via DNS                                    │
│  • Load balancing across pods                                   │
│                                                                  │
│  Service Types:                                                 │
│  • ClusterIP (default) - internal only                         │
│  • NodePort (Samba) - LAN accessible                           │
│  • LoadBalancer (Ingress) - external accessible                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Pod Network                                 │
│  • CNI: Flannel (k3s default)                                   │
│  • Network policy support                                       │
│  • Pod-to-pod communication                                     │
│  • Network: 10.42.0.0/16 (default)                             │
└─────────────────────────────────────────────────────────────────┘
```

### Service Mesh

```
External Traffic:
  Internet/LAN → NodePort/LoadBalancer → Ingress → Service → Pod

Internal Traffic:
  Pod → Service (DNS) → Pod

GitOps Traffic:
  GitHub → ArgoCD Repo Server → ArgoCD Controller → Kubernetes API

File Sharing:
  LAN Client → NodePort (30445) → Samba Pod → hostPath Volume
```

### Network Ports

| Service | Type | Port(s) | Protocol | Access |
|---------|------|---------|----------|--------|
| **Ingress NGINX** | LoadBalancer | 80, 443 | TCP | External/LAN |
| **Samba** | NodePort | 30445, 30137-30139 | TCP/UDP | LAN only |
| **Kubernetes API** | - | 6443 | TCP | Admin only |
| **ArgoCD UI** | Ingress | 443 | TCP | Via ingress |
| **Application Services** | ClusterIP | Various | TCP | Internal |

### DNS Resolution

**Internal (Cluster DNS):**
```
<service-name>.<namespace>.svc.cluster.local
```

**Examples:**
```
argocd-server.argocd.svc.cluster.local
postgres.postgres.svc.cluster.local
samba.samba.svc.cluster.local
```

**External:**
- Configured via ingress host rules
- Requires DNS records pointing to cluster IP
- Examples: `argocd.yourdomain.com`, `nextcloud.yourdomain.com`

## CI/CD Pipeline

### GitHub Actions Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   Developer Workflow                             │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ git push
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Repository                              │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Triggers:                                                  │ │
│  │  • Push to main (infrastructure/**, apps/**)               │ │
│  │  • Pull request (validation)                               │ │
│  │  • Manual workflow dispatch                                │ │
│  └───────────────────────┬────────────────────────────────────┘ │
└────────────────────────────┼────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions Runner                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Stage 1: Validation                                        │ │
│  │  • YAML syntax (kubeval)                                    │ │
│  │  • Security scanning (kubesec)                              │ │
│  │  • Secret detection                                         │ │
│  │  • Kustomize build test                                     │ │
│  │  • Resource limit checks                                    │ │
│  └────────────┬───────────────────────────────────────────────┘ │
│               │                                                  │
│  ┌────────────▼───────────────────────────────────────────────┐ │
│  │  Stage 2: Deployment                                        │ │
│  │  • Configure kubectl (KUBECONFIG secret)                    │ │
│  │  • Verify cluster connection                                │ │
│  │  • Apply manifests (kubectl apply -k)                       │ │
│  │  • Wait for rollout completion                              │ │
│  └────────────┬───────────────────────────────────────────────┘ │
│               │                                                  │
│  ┌────────────▼───────────────────────────────────────────────┐ │
│  │  Stage 3: Verification                                      │ │
│  │  • Check deployment status                                  │ │
│  │  • Verify pod health                                        │ │
│  │  • Generate deployment summary                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└───────────────────────┬──────────────────────────────────────────┘
                        │
                        │ kubectl apply (via KUBECONFIG)
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   k3s Cluster                                    │
│  • Resources created/updated                                    │
│  • Pods deployed/updated                                        │
│  • Services configured                                          │
└─────────────────────────────────────────────────────────────────┘
```

### RBAC for GitHub Actions

```
┌──────────────────────────────────────────────────────────────┐
│              github-actions namespace                         │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  ServiceAccount: github-actions-deployer               │  │
│  │  • Token: Long-lived (10 years)                        │  │
│  │  • Kubeconfig: Base64 encoded in GitHub Secret        │  │
│  └────────────────────┬───────────────────────────────────┘  │
└───────────────────────┼──────────────────────────────────────┘
                        │
                        │ bound to
                        ▼
┌──────────────────────────────────────────────────────────────┐
│              ClusterRole: github-actions-deployer            │
│                                                               │
│  Permissions:                                                │
│  ✅ Create/update/delete: Deployments, Services, Ingresses  │
│  ✅ Manage: ConfigMaps, Secrets, PVCs                       │
│  ✅ Create: Namespaces                                      │
│  ✅ Manage: ArgoCD Applications                             │
│  ✅ Manage: cert-manager resources                          │
│  ❌ No pod/exec (security)                                  │
│  ❌ No cluster-admin (least privilege)                      │
└──────────────────────────────────────────────────────────────┘
```

## GitOps Workflow

### ArgoCD GitOps Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                     Application Repository                         │
│                     (e.g., mcharno/web-app)                        │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  Source Code │  │  Dockerfile  │  │  k8s/base/           │   │
│  │  (src/)      │  │              │  │  • deployment.yaml   │   │
│  │              │  │              │  │  • service.yaml      │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────┬─────────────────────────────────┬───────────────────┘
              │                                 │
       1. Code push                             │
              │                                 │
              ▼                                 │
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions (CI)                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  1. Build Docker image                                      │ │
│  │  2. Push to GHCR (ghcr.io/mcharno/web-app:main-abc1234)   │ │
│  │  3. Update k8s/base/deployment.yaml with new image tag     │ │
│  │  4. Commit manifest change back to Git                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │
                   2. Manifest updated
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                Git Repository (Updated)                          │
│  k8s/base/deployment.yaml                                       │
│  image: ghcr.io/mcharno/web-app:main-abc1234 (NEW)            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                  3. Detects change (poll every 3min)
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ArgoCD (CD)                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Application: charno-web                                    │ │
│  │  • Source: https://github.com/mcharno/web-app.git         │ │
│  │  • Path: k8s/base                                          │ │
│  │  • Auto-sync: Enabled                                      │ │
│  │  • Self-heal: Enabled                                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Sync Process:                                              │ │
│  │  1. Compare desired (Git) vs actual (cluster) state        │ │
│  │  2. Detect drift: image tag changed                        │ │
│  │  3. Execute sync: kubectl apply                            │ │
│  │  4. Monitor health: wait for rollout                       │ │
│  │  5. Report status: Synced & Healthy                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │
                 4. Apply manifests
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   k3s Cluster                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Deployment: charno-web                                     │ │
│  │  • Rolling update triggered                                 │ │
│  │  • New pods created with new image                         │ │
│  │  • Old pods terminated after new pods ready                │ │
│  │  • Zero-downtime deployment                                │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### GitOps Principles in Practice

1. **Declarative:** All desired state in Git (YAML manifests)
2. **Versioned:** Git history = deployment history
3. **Immutable:** Container images tagged with SHA
4. **Automatically Pulled:** ArgoCD polls Git for changes
5. **Continuously Reconciled:** Self-healing when cluster drifts

## Data Flows

### Deployment Flow (Infrastructure)

```
1. Developer commits infrastructure change
         ↓
2. GitHub Actions triggered
         ↓
3. Validation (kubeval, kubesec)
         ↓
4. kubectl apply -k infrastructure/component/
         ↓
5. k3s applies manifests
         ↓
6. Pods/Services created or updated
         ↓
7. Health check & verification
         ↓
8. Deployment complete
```

### Deployment Flow (Application - GitOps)

```
1. Developer commits code change (app repo)
         ↓
2. GitHub Actions: Build image
         ↓
3. Push image to GHCR (ghcr.io/user/app:tag)
         ↓
4. Update k8s manifest with new image tag
         ↓
5. Commit manifest change to Git
         ↓
6. ArgoCD detects manifest change (3min poll)
         ↓
7. ArgoCD syncs: kubectl apply
         ↓
8. k3s performs rolling update
         ↓
9. New pods deployed, old pods terminated
         ↓
10. ArgoCD reports: Synced & Healthy
```

### User Request Flow (HTTPS)

```
1. User requests https://app.example.com
         ↓
2. DNS resolves to cluster IP
         ↓
3. Request hits NGINX Ingress Controller
         ↓
4. Ingress examines Host header
         ↓
5. Routes to appropriate Service (ClusterIP)
         ↓
6. Service load-balances to Pod
         ↓
7. Pod processes request
         ↓
8. Response returns through same path
         ↓
9. User receives response
```

### File Access Flow (Samba)

```
1. Client connects to \\<node-ip>\share
         ↓
2. Request hits NodePort 30445
         ↓
3. Routed to Samba pod
         ↓
4. Authentication (username/password)
         ↓
5. Access granted to /storage mount
         ↓
6. Files served from /mnt/samba-share (hostPath)
         ↓
7. Client can read/write files
```

## Technology Stack

### Core Platform

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Orchestration** | k3s | v1.28+ | Lightweight Kubernetes |
| **Container Runtime** | containerd | Latest | Container execution |
| **CNI** | Flannel | Built-in | Pod networking |
| **Storage** | Local Path Provisioner | Built-in | Dynamic PV provisioning |

### Infrastructure

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Ingress** | NGINX Ingress Controller | Latest | HTTP/HTTPS routing |
| **Certificates** | cert-manager | Latest | SSL/TLS automation |
| **GitOps** | ArgoCD | Latest stable | Continuous delivery |
| **File Sharing** | Samba (dperson/samba) | Latest | SMB/CIFS server |

### CI/CD

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **CI Platform** | GitHub Actions | - | Build & test automation |
| **CD Platform** | ArgoCD | Latest | Deployment automation |
| **Container Registry** | GHCR | - | Docker image storage |
| **Validation** | kubeval, kubesec | Latest | Manifest validation |

### Databases

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **RDBMS** | PostgreSQL | Latest | Relational data |
| **Cache** | Redis | Latest | Caching & sessions |

### Monitoring & Observability

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Metrics** | Prometheus | Latest | Metrics collection |
| **Visualization** | Grafana | Latest | Dashboards |

## Security Architecture

### Authentication & Authorization

```
┌─────────────────────────────────────────────────────────────────┐
│                   Authentication Layers                          │
│                                                                  │
│  1. Cluster Access                                              │
│     • kubectl: kubeconfig with service account token            │
│     • ArgoCD: admin password (changeable)                       │
│     • Samba: username/password                                  │
│                                                                  │
│  2. Service Accounts                                            │
│     • github-actions-deployer (CI/CD)                           │
│     • Default service accounts per namespace                    │
│                                                                  │
│  3. RBAC (Role-Based Access Control)                            │
│     • ClusterRole: github-actions-deployer                      │
│     • Namespace-scoped roles for applications                   │
│     • Least privilege principle                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Network Security

```
┌─────────────────────────────────────────────────────────────────┐
│                   Network Security Layers                        │
│                                                                  │
│  1. Firewall (Host)                                             │
│     • Allow: 80, 443 (Ingress)                                 │
│     • Allow: 30445, 30137-30139 (Samba - LAN only)            │
│     • Allow: 6443 (Kubernetes API - admin only)                │
│     • Deny: All other ports                                    │
│                                                                  │
│  2. Network Policies (Optional)                                 │
│     • Pod-to-pod communication rules                            │
│     • Namespace isolation                                       │
│                                                                  │
│  3. Service Types                                               │
│     • ClusterIP: Internal only (default)                        │
│     • NodePort: LAN accessible (Samba)                         │
│     • LoadBalancer: External accessible (Ingress)              │
└─────────────────────────────────────────────────────────────────┘
```

### Secret Management

```
┌─────────────────────────────────────────────────────────────────┐
│                   Secret Storage                                 │
│                                                                  │
│  1. Kubernetes Secrets                                          │
│     • Base64 encoded (NOT encrypted by default)                 │
│     • Namespace-scoped                                          │
│     • Examples: GHCR credentials, database passwords            │
│                                                                  │
│  2. GitHub Secrets                                              │
│     • Encrypted at rest                                         │
│     • KUBECONFIG for cluster access                             │
│     • GitHub tokens for GHCR                                    │
│                                                                  │
│  3. Best Practices                                              │
│     • Never commit secrets to Git                               │
│     • Use Secret templates in Git                               │
│     • Rotate secrets regularly                                  │
│     • Consider: Sealed Secrets or External Secrets Operator     │
└─────────────────────────────────────────────────────────────────┘
```

### Container Security

```
┌─────────────────────────────────────────────────────────────────┐
│                   Container Security                             │
│                                                                  │
│  1. Image Sources                                               │
│     • GHCR: GitHub Container Registry (authenticated)           │
│     • Docker Hub: Public images (trusted sources)               │
│     • Image pull secrets for private registries                 │
│                                                                  │
│  2. Image Tags                                                  │
│     • Immutable: SHA-based tags (main-abc1234)                 │
│     • Avoid: latest tag in production                           │
│     • Audit trail via Git commits                               │
│                                                                  │
│  3. Security Scanning                                           │
│     • kubesec: Kubernetes manifest scanning                     │
│     • Optional: Trivy/Clair for image vulnerability scanning    │
│                                                                  │
│  4. Runtime Security                                            │
│     • Non-root containers where possible                        │
│     • Read-only root filesystems                                │
│     • Drop capabilities (CAP_DROP)                              │
│     • Security contexts defined                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Backup & Disaster Recovery

### Backup Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                   What to Backup                                 │
│                                                                  │
│  1. Git Repositories (Already backed up)                        │
│     ✅ k8s-infra: All manifests                                 │
│     ✅ web-app: Application code + manifests                    │
│     ✅ GitHub: Automatic backups                                │
│                                                                  │
│  2. Persistent Data (Manual/Automated)                          │
│     • /mnt/samba-share (Samba files)                           │
│     • Database volumes (PostgreSQL data)                        │
│     • Application persistent volumes                            │
│     • Method: rsync, Velero, or custom scripts                  │
│                                                                  │
│  3. Secrets (Secure backup)                                     │
│     • Export and encrypt secrets                                │
│     • Store in secure location (not Git)                        │
│     • Consider: Sealed Secrets for Git storage                  │
│                                                                  │
│  4. Cluster Configuration                                       │
│     ✅ Declarative: All in Git (k8s-infra repo)                │
│     • Cluster-specific: kubeconfig, tokens                      │
└─────────────────────────────────────────────────────────────────┘
```

### Disaster Recovery

**Recovery Time Objective (RTO):** ~2 hours

**Recovery Point Objective (RPO):** Last Git commit + last data backup

**Recovery Procedure:**

```
1. Provision new k3s cluster
2. Clone k8s-infra repository
3. Run setup scripts:
   - ./scripts/setup-github-actions.sh
   - ./scripts/argocd/install-argocd.sh
   - ./scripts/setup-samba.sh
4. Deploy infrastructure:
   - kubectl apply -k infrastructure/rbac/
   - kubectl apply -k infrastructure/ingress-nginx/
   - kubectl apply -k infrastructure/cert-manager/
   - kubectl apply -k infrastructure/databases/
5. Restore secrets:
   - GHCR credentials
   - Database passwords
   - Samba credentials
6. Deploy applications:
   - kubectl apply -f argocd/applications/
   - Wait for ArgoCD to sync
7. Restore persistent data:
   - rsync backups to /mnt/samba-share
   - Restore database dumps
8. Verify all services operational
```

## Scalability Considerations

### Current State: Single Node

The current architecture is designed for a single-node k3s cluster, suitable for:
- Home lab / development environments
- Small-scale production workloads
- Resource-constrained environments

### Scaling Paths

**Horizontal Scaling (Multi-Node):**
```
1. Add worker nodes to k3s cluster
2. Update hostPath volumes → NFS/Ceph/Longhorn
3. Add node selectors for stateful workloads
4. Configure pod anti-affinity for HA
5. Increase replica counts for services
```

**Vertical Scaling (Resource Limits):**
```
1. Increase resource requests/limits in deployments
2. Add more CPU/RAM to server node
3. Expand storage capacity
```

## Maintenance & Operations

### Regular Maintenance Tasks

| Task | Frequency | Command/Action |
|------|-----------|----------------|
| Update k3s | Monthly | `curl -sfL https://get.k3s.io \| sh -` |
| Review logs | Weekly | `kubectl logs -n <namespace> <pod>` |
| Check disk space | Weekly | `df -h`, `du -sh /mnt/samba-share` |
| Update applications | As needed | Git commit → GitOps auto-deploy |
| Rotate secrets | Quarterly | Recreate secrets, restart pods |
| Review RBAC | Quarterly | `kubectl auth can-i --list` |
| Backup data | Daily/Weekly | `rsync` or backup tool |
| Test disaster recovery | Quarterly | Full recovery drill |

### Monitoring Checklist

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl top pods -A

# Resource usage
df -h
free -h

# Service status
kubectl get svc -A
kubectl get ingress -A

# ArgoCD applications
kubectl get applications -n argocd

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

## Summary

This architecture provides:

✅ **GitOps-based deployments** - ArgoCD + GitHub Actions
✅ **Automated CI/CD** - Build, test, deploy on Git push
✅ **Self-healing** - ArgoCD auto-sync and self-heal
✅ **Security** - RBAC, secrets management, network policies
✅ **Observability** - Prometheus + Grafana monitoring
✅ **Flexibility** - Easily add new applications
✅ **Disaster recovery** - All infrastructure as code
✅ **LAN file sharing** - Samba for cross-platform access

The system follows cloud-native best practices while remaining lightweight and suitable for resource-constrained environments.
