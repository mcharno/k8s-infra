# ArgoCD Setup Guide

Complete guide for installing and configuring ArgoCD on your k3s cluster.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Initial Configuration](#initial-configuration)
- [Accessing ArgoCD](#accessing-argocd)
- [Deploying Applications](#deploying-applications)
- [Monitoring & Management](#monitoring--management)
- [Best Practices](#best-practices)

## Overview

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes that automatically deploys applications based on Git repository state.

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     ArgoCD Components                         │
│                                                               │
│  ┌────────────────┐          ┌────────────────┐             │
│  │  API Server    │◄────────►│  Repo Server   │             │
│  │  • REST API    │          │  • Git sync    │             │
│  │  • UI          │          │  • Manifest    │             │
│  │  • CLI         │          │    generation  │             │
│  └───────┬────────┘          └────────────────┘             │
│          │                                                    │
│  ┌───────▼──────────────────┐  ┌────────────────┐          │
│  │  Application Controller  │  │  Dex (SSO)     │          │
│  │  • Monitors apps         │  │  • Auth        │          │
│  │  • Syncs to cluster      │  │  • RBAC        │          │
│  │  • Health assessment     │  │                │          │
│  └──────────────────────────┘  └────────────────┘          │
└──────────────────────────────────────────────────────────────┘
```

### Key Features

- **Automated Sync**: Automatically deploys when Git changes are detected
- **Self-Healing**: Automatically corrects drift from desired state
- **Health Status**: Monitors application health
- **Rollback**: Easy rollback to previous versions
- **Multi-Source**: Supports Git, Helm, Kustomize
- **RBAC**: Fine-grained access control

## Installation

### Method 1: Automated Script (Recommended)

```bash
./scripts/argocd/install-argocd.sh
```

**What it does:**
1. Creates `argocd` namespace
2. Installs ArgoCD from official manifests
3. Waits for pods to be ready
4. Displays initial admin password
5. Shows access instructions

### Method 2: Manual Installation

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
```

### Verify Installation

```bash
# Check pods
kubectl get pods -n argocd

# Expected output:
# NAME                                  READY   STATUS
# argocd-application-controller-0       1/1     Running
# argocd-dex-server-xxx                 1/1     Running
# argocd-redis-xxx                      1/1     Running
# argocd-repo-server-xxx                1/1     Running
# argocd-server-xxx                     1/1     Running
# argocd-applicationset-controller-xxx  1/1     Running
# argocd-notifications-controller-xxx   1/1     Running

# Check services
kubectl get svc -n argocd
```

## Initial Configuration

### 1. Change Admin Password

**Via UI:**
1. Login to ArgoCD UI (see Accessing ArgoCD below)
2. Click user icon (top left) → User Info
3. Click "Update Password"
4. Enter current password and new password
5. Save

**Via CLI:**
```bash
# Install ArgoCD CLI
brew install argocd  # macOS
# Or download from: https://github.com/argoproj/argo-cd/releases

# Login
argocd login <argocd-server>

# Update password
argocd account update-password
```

### 2. Delete Initial Secret (Optional)

After changing the password:

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

### 3. Configure Ingress

Update the domain in `infrastructure/argocd/argocd-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # Optional: Enable cert-manager
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  # Optional: TLS configuration
  # tls:
  # - hosts:
  #   - argocd.yourdomain.com
  #   secretName: argocd-tls
  rules:
  - host: argocd.yourdomain.com  # CHANGE THIS
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

Apply the ingress:

```bash
kubectl apply -f infrastructure/argocd/argocd-ingress.yaml
```

## Accessing ArgoCD

### Method 1: Ingress (Production)

**Prerequisites:**
- Ingress NGINX deployed
- DNS record pointing to cluster IP
- Optional: cert-manager for TLS

**Access:**
```
https://argocd.yourdomain.com
```

**Login:**
- Username: `admin`
- Password: (from initial setup or changed password)

### Method 2: Port Forward (Development)

```bash
# Forward port 8080 to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access in browser
open https://localhost:8080
```

**Login:**
- Username: `admin`
- Password: (from initial setup)

### Method 3: ArgoCD CLI

```bash
# Install CLI
brew install argocd  # macOS
# Or: curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
# chmod +x /usr/local/bin/argocd

# Login (port-forward method)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080

# Or login (ingress method)
argocd login argocd.yourdomain.com

# Use CLI
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
```

## Deploying Applications

### Application Manifest Structure

ArgoCD Applications are defined as Kubernetes resources:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  # Project (default or custom)
  project: default

  # Source repository
  source:
    repoURL: https://github.com/user/repo.git
    targetRevision: main  # branch, tag, or commit SHA
    path: k8s/base       # path to manifests

  # Destination cluster and namespace
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app

  # Sync policy
  syncPolicy:
    automated:
      prune: true        # Delete resources not in Git
      selfHeal: true     # Force sync when drift detected
      allowEmpty: false  # Prevent deletion of all resources
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Deploying charno-web Example

The charno-web application is pre-configured:

```bash
# Deploy the application
kubectl apply -f argocd/applications/charno-web.yaml

# Check status
kubectl get application charno-web -n argocd

# Watch sync progress
kubectl get application charno-web -n argocd -w

# View in UI
# Navigate to ArgoCD UI and see the application card
```

### Creating New Applications

**Method 1: Via kubectl**

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nextcloud
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/mcharno/k8s-infra.git
    targetRevision: main
    path: apps/nextcloud/base
  destination:
    server: https://kubernetes.default.svc
    namespace: nextcloud
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

**Method 2: Via ArgoCD UI**

1. Click "New App"
2. Fill in details:
   - **Application Name**: nextcloud
   - **Project**: default
   - **Sync Policy**: Automatic
   - **Repository URL**: https://github.com/mcharno/k8s-infra.git
   - **Revision**: main
   - **Path**: apps/nextcloud/base
   - **Cluster**: https://kubernetes.default.svc
   - **Namespace**: nextcloud
3. Click "Create"

**Method 3: Via ArgoCD CLI**

```bash
argocd app create nextcloud \
  --repo https://github.com/mcharno/k8s-infra.git \
  --path apps/nextcloud/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nextcloud \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

## Monitoring & Management

### Viewing Application Status

**Via kubectl:**
```bash
# List all applications
kubectl get applications -n argocd

# Get detailed status
kubectl get application charno-web -n argocd -o yaml

# Watch status changes
watch kubectl get applications -n argocd
```

**Via ArgoCD UI:**
- Dashboard shows all applications
- Click application for detailed view
- Shows sync status, health, resource tree
- View deployment history

**Via ArgoCD CLI:**
```bash
# List applications
argocd app list

# Get application details
argocd app get charno-web

# View application resources
argocd app resources charno-web

# View sync history
argocd app history charno-web
```

### Manual Sync

**Via kubectl:**
```bash
# Trigger sync by annotating
kubectl patch application charno-web -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

**Via ArgoCD UI:**
- Click "Sync" button on application card
- Select sync options (prune, dry-run, etc.)
- Click "Synchronize"

**Via ArgoCD CLI:**
```bash
# Basic sync
argocd app sync charno-web

# Force sync (override)
argocd app sync charno-web --force

# Dry run
argocd app sync charno-web --dry-run

# Prune resources
argocd app sync charno-web --prune
```

### Viewing Logs

```bash
# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server -f

# Application controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# Repo server logs
kubectl logs -n argocd deployment/argocd-repo-server -f

# Application pod logs (example)
kubectl logs -n charno-web deployment/charno-web -f
```

### Health Status

ArgoCD tracks three states:

**Sync Status:**
- **Synced**: Cluster state matches Git state
- **OutOfSync**: Cluster state differs from Git state
- **Unknown**: Unable to determine state

**Health Status:**
- **Healthy**: All resources healthy and ready
- **Progressing**: Resources being created/updated
- **Degraded**: Some resources unhealthy
- **Missing**: Resources expected but not found
- **Unknown**: Unable to determine health

**Operation Status:**
- **Running**: Sync operation in progress
- **Succeeded**: Sync completed successfully
- **Failed**: Sync failed
- **Terminating**: Sync being terminated

### Rollback

**Via UI:**
1. Click application
2. Go to "History and rollback"
3. Select previous revision
4. Click "Rollback"

**Via CLI:**
```bash
# View history
argocd app history charno-web

# Rollback to specific revision
argocd app rollback charno-web <revision-id>

# Example
argocd app rollback charno-web 5
```

## Best Practices

### Application Organization

**1. One Application per Git Repository Path:**
```
apps/
  nextcloud/base/  → ArgoCD Application: nextcloud
  wallabag/base/   → ArgoCD Application: wallabag
```

**2. Use Projects for Grouping:**
```yaml
# Create project
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production applications
  sourceRepos:
    - 'https://github.com/mcharno/*'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
```

**3. Namespace-per-App:**
- Each application in its own namespace
- Easier resource isolation
- Clearer RBAC boundaries

### Sync Policies

**Automated Sync:**
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Correct drift automatically
```

**Benefits:**
- ✅ Always in sync with Git
- ✅ Self-healing if manual changes made
- ✅ True GitOps experience

**When to use manual sync:**
- Production deployments requiring approval
- Testing changes before applying
- Sensitive applications

### Repository Structure

**Recommended:**
```
repo/
  k8s/
    base/           # Base manifests
      deployment.yaml
      service.yaml
      kustomization.yaml
    overlays/       # Environment overrides
      staging/
      production/
```

**ArgoCD Application points to:**
- `path: k8s/base` for simple deployments
- `path: k8s/overlays/production` for multi-env

### Security

**1. Use RBAC:**
```bash
# View current RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Edit RBAC
kubectl edit configmap argocd-rbac-cm -n argocd
```

**2. Use SSO (Optional):**
- Configure Dex for GitHub/Google/LDAP authentication
- Disable admin account for regular users
- Use RBAC for fine-grained permissions

**3. Protect Secrets:**
- Never commit secrets to Git
- Use Sealed Secrets or External Secrets Operator
- Or manage secrets outside ArgoCD

### Monitoring

**1. Set up Notifications:**
```yaml
# ConfigMap: argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  trigger.on-deployed: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-deployed]
```

**2. Prometheus Metrics:**
- ArgoCD exposes Prometheus metrics
- Monitor sync success rate
- Track application health
- Alert on OutOfSync applications

**3. Audit Logs:**
- All operations logged
- Review in UI under "Events"
- Export to external logging system

## Troubleshooting

### Application OutOfSync

**Problem:** Application shows OutOfSync status

**Diagnosis:**
```bash
# View differences
argocd app diff charno-web

# Check sync status
kubectl get application charno-web -n argocd -o yaml
```

**Solutions:**
- If expected: Trigger manual sync
- If unexpected: Check for manual kubectl changes
- Enable selfHeal to auto-correct

### Application Unhealthy

**Problem:** Application shows Degraded health

**Diagnosis:**
```bash
# Check application resources
argocd app resources charno-web

# Check pod status
kubectl get pods -n charno-web

# Check pod logs
kubectl logs -n charno-web <pod-name>

# Check events
kubectl get events -n charno-web --sort-by='.lastTimestamp'
```

**Solutions:**
- Fix resource issues (insufficient memory/CPU)
- Check image pull errors
- Verify secrets exist
- Review application logs

### Sync Failures

**Problem:** Sync operation fails

**Diagnosis:**
```bash
# View sync errors
argocd app get charno-web

# Check operation state
kubectl get application charno-web -n argocd -o jsonpath='{.status.operationState}'
```

**Common causes:**
- Invalid YAML manifests
- Missing CRDs
- RBAC permission issues
- Resource conflicts

**Solutions:**
- Validate manifests locally: `kubectl apply --dry-run=client -f manifest.yaml`
- Check ArgoCD application controller logs
- Ensure all CRDs are installed
- Review RBAC permissions

### Repository Connection Issues

**Problem:** ArgoCD can't connect to Git repository

**Diagnosis:**
```bash
# Check repo server logs
kubectl logs -n argocd deployment/argocd-repo-server

# Test connection
argocd repo list
```

**Solutions:**
- For private repos: Add repository credentials
- Check network connectivity
- Verify repository URL is correct
- Check if repository requires authentication

### Access Issues

**Problem:** Can't access ArgoCD UI

**Diagnosis:**
```bash
# Check ArgoCD server pod
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

# Check service
kubectl get svc -n argocd argocd-server

# Check ingress
kubectl get ingress -n argocd
kubectl describe ingress argocd-server-ingress -n argocd
```

**Solutions:**
- Verify port-forward is active
- Check ingress DNS records
- Verify cert-manager issued certificate
- Check nginx ingress controller logs

## Additional Resources

### Setup Scripts

```bash
# Install ArgoCD
./scripts/argocd/install-argocd.sh

# Setup GHCR secret (for private images)
./scripts/argocd/setup-ghcr-secret.sh

# Setup database secrets
./scripts/argocd/setup-database-secret.sh
```

### Useful Commands Reference

```bash
# Application management
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
argocd app delete <app-name>

# Repository management
argocd repo list
argocd repo add <repo-url>

# Project management
argocd proj list
argocd proj create <project-name>

# Cluster management
argocd cluster list
argocd cluster add <context-name>

# Account management
argocd account update-password
argocd account list
```

### Documentation Links

- **ArgoCD Official Docs**: https://argo-cd.readthedocs.io/
- **ArgoCD GitHub**: https://github.com/argoproj/argo-cd
- **GitOps Integration**: [docs/argocd-gitops.md](argocd-gitops.md)
- **Quick Reference**: [docs/quick-reference.md](quick-reference.md)

## Summary

ArgoCD provides:

✅ **GitOps deployment** - Git as source of truth
✅ **Automated sync** - Deploy changes automatically
✅ **Self-healing** - Correct drift from desired state
✅ **Rollback** - Easy revert to previous versions
✅ **Health monitoring** - Track application health
✅ **UI/CLI/API** - Multiple access methods
✅ **Multi-source** - Git, Helm, Kustomize support

For automated GitOps deployments with GitHub Actions, see [ArgoCD GitOps Integration](argocd-gitops.md).
