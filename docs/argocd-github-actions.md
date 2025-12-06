# ArgoCD + GitHub Actions Integration Guide

This guide explains how to integrate GitHub Actions with ArgoCD for automated GitOps deployments of the charno-web application.

## Overview

**GitOps Flow:**
```
Code Push → GitHub Actions → Build Image → Push to GHCR → Update Manifest → ArgoCD Syncs → k3s Deploys
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│            mcharno/web-app Repository                        │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │ Source     │  │ Dockerfile   │  │ k8s/base/        │    │
│  │ Code       │  │              │  │ manifests        │    │
│  └────────────┘  └──────────────┘  └──────────────────┘    │
└──────────┬──────────────┬───────────────────┬───────────────┘
           │              │                   │
    1. Push to main       │                   │
           │              │                   │
           ▼              ▼                   │
┌─────────────────────────────────────────────┼───────────────┐
│              GitHub Actions                 │               │
│  ┌──────────────────────────────────────────┼───────────┐   │
│  │  1. Build Docker Image                   │           │   │
│  │  2. Push to GHCR (ghcr.io/mcharno/...)   │           │   │
│  │  3. Update k8s/base/deployment.yaml ─────┘           │   │
│  │  4. Commit & Push manifest change                    │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ Git detects change
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                   ArgoCD (in k3s)                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Application: charno-web                             │   │
│  │  Source: mcharno/web-app (k8s/base/)                 │   │
│  │  Auto-sync: Enabled                                  │   │
│  │  Self-heal: Enabled                                  │   │
│  └────────────────────┬─────────────────────────────────┘   │
└───────────────────────┼─────────────────────────────────────┘
                        │
                        │ Applies manifests
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  k3s Cluster                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Namespace: charno-web                               │   │
│  │  Deployment: Updated with new image                  │   │
│  │  Pods: Rolling update to new version                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. ArgoCD Setup

**Install ArgoCD** (if not already installed):
```bash
./scripts/argocd/install-argocd.sh
```

**Deploy the ArgoCD Application**:
```bash
kubectl apply -f argocd/applications/charno-web.yaml
```

This creates an ArgoCD Application that:
- Watches `mcharno/web-app` repository
- Monitors `k8s/base/` directory for manifests
- Auto-syncs changes every 3 minutes
- Self-heals if cluster state drifts

**Verify ArgoCD Application**:
```bash
kubectl get applications -n argocd
kubectl describe application charno-web -n argocd
```

### 2. GHCR Secret Setup

Create the GitHub Container Registry pull secret:
```bash
./scripts/argocd/setup-ghcr-secret.sh
```

This allows k3s to pull images from `ghcr.io/mcharno/*`.

### 3. Database Secrets (if needed)

If your app needs database credentials:
```bash
./scripts/argocd/setup-database-secret.sh
```

## Setting Up GitHub Actions in web-app Repository

### Step 1: Choose a Workflow Template

Two workflow templates are provided:

**Option A: Simple Workflow** (Recommended for most cases)
- Builds, pushes, and updates manifest in one job
- Minimal configuration
- Use: `.github/workflow-templates/simple-argocd-deploy.yaml`

**Option B: Advanced Workflow**
- Separate jobs for build, push, and manifest update
- Multi-platform builds (amd64, arm64)
- Detailed job summaries
- Use: `.github/workflow-templates/deploy-with-argocd.yaml`

### Step 2: Add Workflow to web-app Repository

**Copy the workflow to your web-app repo:**

```bash
# In the web-app repository
mkdir -p .github/workflows
cp /path/to/k8s-infra/.github/workflow-templates/simple-argocd-deploy.yaml \
   .github/workflows/deploy.yaml
```

**Or create it manually:**

```yaml
# .github/workflows/deploy.yaml
name: Deploy with ArgoCD

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and Push
        id: build
        run: |
          TAG="main-${GITHUB_SHA::7}"
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:$TAG"
          docker build -t $IMAGE .
          docker push $IMAGE
          docker tag $IMAGE ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          echo "image=$IMAGE" >> $GITHUB_OUTPUT

      - name: Update Manifest
        run: |
          sed -i "s|image: ghcr.io/${{ github.repository }}:.*|image: ${{ steps.build.outputs.image }}|g" k8s/base/deployment.yaml

      - name: Commit and Push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/base/deployment.yaml
          git diff --staged --quiet || git commit -m "Deploy ${{ steps.build.outputs.image }}"
          git push
```

### Step 3: Verify Deployment Manifest Structure

Ensure your `k8s/base/deployment.yaml` in the web-app repo has the correct image reference:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: charno-web
  namespace: charno-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: charno-web
  template:
    metadata:
      labels:
        app: charno-web
    spec:
      imagePullSecrets:
        - name: ghcr-secret  # Important!
      containers:
      - name: charno-web
        image: ghcr.io/mcharno/web-app:main-abc1234  # Will be auto-updated
        ports:
        - containerPort: 3000
        # ... rest of your container spec
```

**Important fields:**
- `imagePullSecrets`: Must reference `ghcr-secret`
- `image`: This will be automatically updated by GitHub Actions

## How It Works

### 1. Developer Workflow

```bash
# Make code changes
vim src/index.js

# Commit and push to main
git add .
git commit -m "Add new feature"
git push origin main
```

### 2. GitHub Actions Execution

When code is pushed to `main`:

1. **Checkout code** from the repository
2. **Login to GHCR** using `GITHUB_TOKEN`
3. **Build Docker image** with tag `main-<git-sha>`
4. **Push to GHCR** at `ghcr.io/mcharno/web-app:main-abc1234`
5. **Update manifest** in `k8s/base/deployment.yaml`
6. **Commit changes** back to the repository
7. **Push manifest update** to Git

### 3. ArgoCD Sync

ArgoCD continuously monitors the Git repository:

1. **Detects change** in `k8s/base/deployment.yaml` (within 3 minutes)
2. **Compares** desired state (Git) vs actual state (k3s)
3. **Syncs automatically** due to `automated.selfHeal: true`
4. **Applies** the new deployment manifest
5. **Triggers** rolling update of pods
6. **Monitors** health and reports status

### 4. Deployment Complete

New pods are created with the updated image:

```bash
# Check deployment status
kubectl get pods -n charno-web
kubectl rollout status deployment/charno-web -n charno-web

# View ArgoCD status
kubectl get application charno-web -n argocd
```

## Monitoring Deployments

### Via kubectl

```bash
# Watch pods update
kubectl get pods -n charno-web -w

# Check deployment history
kubectl rollout history deployment/charno-web -n charno-web

# View recent events
kubectl get events -n charno-web --sort-by='.lastTimestamp'

# Check image version
kubectl get deployment charno-web -n charno-web -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Via ArgoCD UI

1. **Access ArgoCD UI** (if using ingress):
   ```
   https://argocd.yourdomain.com
   ```

   Or port-forward:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Visit https://localhost:8080
   ```

2. **Login** with admin credentials

3. **View charno-web application**:
   - Sync status
   - Health status
   - Resource tree
   - Recent sync history

### Via ArgoCD CLI

```bash
# Install ArgoCD CLI
brew install argocd  # macOS
# Or download from https://github.com/argoproj/argo-cd/releases

# Login
argocd login argocd.yourdomain.com

# Get application status
argocd app get charno-web

# View sync history
argocd app history charno-web

# Force sync (if needed)
argocd app sync charno-web
```

## Troubleshooting

### Workflow Fails to Push Manifest

**Problem:** GitHub Actions can't push the updated manifest

**Solution:** Ensure the workflow has `contents: write` permission:
```yaml
permissions:
  contents: write  # Needed to push manifest changes
  packages: write  # Needed to push Docker images
```

### ArgoCD Not Syncing

**Problem:** ArgoCD doesn't detect the manifest change

**Checks:**
```bash
# 1. Check ArgoCD application status
kubectl get application charno-web -n argocd -o yaml

# 2. Verify repo URL is correct
# Should be: https://github.com/mcharno/web-app.git

# 3. Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-repo-server

# 4. Force refresh
argocd app get charno-web --refresh
```

**Solution:** ArgoCD polls every 3 minutes by default. Wait or force sync:
```bash
argocd app sync charno-web
```

### Image Pull Errors

**Problem:** Pods can't pull the image from GHCR

**Error:**
```
Failed to pull image "ghcr.io/mcharno/web-app:main-abc1234": rpc error: code = Unknown desc = failed to pull and unpack image "ghcr.io/mcharno/web-app:main-abc1234": failed to resolve reference "ghcr.io/mcharno/web-app:main-abc1234": pull access denied, repository does not exist or may require authorization
```

**Solution:** Ensure GHCR secret exists:
```bash
# Check secret
kubectl get secret ghcr-secret -n charno-web

# Recreate if missing
./scripts/argocd/setup-ghcr-secret.sh

# Verify deployment references the secret
kubectl get deployment charno-web -n charno-web -o yaml | grep imagePullSecrets
```

### Wrong Image Version Deployed

**Problem:** ArgoCD deploys an older image version

**Solution:**
1. **Check the manifest in Git**:
   ```bash
   # In web-app repo
   cat k8s/base/deployment.yaml | grep image:
   ```

2. **Check what ArgoCD thinks**:
   ```bash
   argocd app manifests charno-web | grep image:
   ```

3. **Force sync**:
   ```bash
   argocd app sync charno-web --force
   ```

### Deployment Stuck in Progressing

**Problem:** Rolling update never completes

**Checks:**
```bash
# Check pod status
kubectl get pods -n charno-web

# Check pod logs
kubectl logs -n charno-web <pod-name>

# Check events
kubectl describe pod -n charno-web <pod-name>

# Check deployment events
kubectl describe deployment charno-web -n charno-web
```

**Common causes:**
- Image doesn't exist or can't be pulled
- Container crashes on startup
- Health check failing
- Resource limits too low

## Advanced Configuration

### Manual Sync Trigger

Add this step to force ArgoCD to sync immediately (optional):

```yaml
- name: Trigger ArgoCD Sync
  run: |
    # Requires ARGOCD_TOKEN secret
    curl -X POST \
      -H "Authorization: Bearer ${{ secrets.ARGOCD_TOKEN }}" \
      https://argocd.yourdomain.com/api/v1/applications/charno-web/sync
```

**Setup ArgoCD token:**
```bash
# Generate ArgoCD auth token
argocd account generate-token --account github-actions

# Add to GitHub Secrets:
# Settings → Secrets → New secret
# Name: ARGOCD_TOKEN
# Value: <token from above>
```

### Multi-Environment Deployments

For staging + production:

**Update ArgoCD Application** to use overlays:
```yaml
# argocd/applications/charno-web-staging.yaml
source:
  path: k8s/overlays/staging

# argocd/applications/charno-web-production.yaml
source:
  path: k8s/overlays/production
```

**Update workflow** to deploy based on branch:
```yaml
- name: Update Manifest
  run: |
    if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
      ENV="production"
    else
      ENV="staging"
    fi
    sed -i "s|image: .*|image: ${{ steps.build.outputs.image }}|g" k8s/overlays/$ENV/deployment.yaml
```

### Image Tag Strategy

**Current:** `main-<git-sha>` (e.g., `main-abc1234`)

**Alternatives:**

**Semantic versioning:**
```yaml
- name: Get version
  run: echo "VERSION=$(cat package.json | jq -r .version)" >> $GITHUB_ENV

- name: Tag image
  run: docker tag $IMAGE ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:v${{ env.VERSION }}
```

**Date-based:**
```yaml
- name: Generate tag
  run: echo "TAG=$(date +%Y%m%d-%H%M%S)-${GITHUB_SHA::7}" >> $GITHUB_ENV
```

### Rollback

**Via kubectl:**
```bash
# Rollback to previous version
kubectl rollout undo deployment/charno-web -n charno-web

# Rollback to specific revision
kubectl rollout undo deployment/charno-web -n charno-web --to-revision=2
```

**Via ArgoCD:**
```bash
# View history
argocd app history charno-web

# Rollback to specific revision
argocd app rollback charno-web <revision-id>
```

**Via Git:**
```bash
# In web-app repo
git revert <commit-hash>
git push
# ArgoCD will auto-sync the reverted manifest
```

## Security Best Practices

### 1. GitHub Token Permissions

The `GITHUB_TOKEN` used has automatic permissions. Ensure they're scoped:
```yaml
permissions:
  contents: write  # Only what's needed
  packages: write  # Only what's needed
```

### 2. Image Scanning

Add vulnerability scanning:
```yaml
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.build.outputs.image }}
    format: 'sarif'
    output: 'trivy-results.sarif'
```

### 3. Signed Commits

Use GPG signing for manifest commits:
```yaml
- name: Import GPG key
  uses: crazy-max/ghaction-import-gpg@v6
  with:
    gpg_private_key: ${{ secrets.GPG_PRIVATE_KEY }}
    git_user_signingkey: true
    git_commit_gpgsign: true
```

### 4. ArgoCD RBAC

Restrict ArgoCD access:
```bash
# Edit ArgoCD RBAC
kubectl edit configmap argocd-rbac-cm -n argocd
```

## Testing the Integration

### End-to-End Test

1. **Make a code change** in web-app:
   ```bash
   echo "console.log('test');" >> src/index.js
   git add . && git commit -m "test" && git push
   ```

2. **Watch GitHub Actions**:
   - Go to web-app repo → Actions tab
   - Watch the workflow run
   - Verify it completes successfully

3. **Watch ArgoCD**:
   ```bash
   watch kubectl get application charno-web -n argocd
   # Wait for STATUS to show "Synced"
   ```

4. **Verify deployment**:
   ```bash
   kubectl get pods -n charno-web
   # New pod should be running with updated image
   ```

5. **Check image tag**:
   ```bash
   kubectl get deployment charno-web -n charno-web -o jsonpath='{.spec.template.spec.containers[0].image}'
   # Should show the new image tag
   ```

## Summary

**What you need to do:**

1. ✅ **Install ArgoCD** (if not done): `./scripts/argocd/install-argocd.sh`
2. ✅ **Deploy ArgoCD Application**: `kubectl apply -f argocd/applications/charno-web.yaml`
3. ✅ **Setup GHCR secret**: `./scripts/argocd/setup-ghcr-secret.sh`
4. ✅ **Add workflow to web-app repo**: Copy template to `.github/workflows/deploy.yaml`
5. ✅ **Push code**: ArgoCD and GitHub Actions handle the rest!

**The flow:**
```
Code Push → GH Actions (Build + Push + Update Manifest) → ArgoCD (Auto-Sync) → k3s (Deploy)
```

**Monitoring:**
- **GitHub Actions**: web-app repo → Actions tab
- **ArgoCD UI**: https://argocd.yourdomain.com
- **kubectl**: `kubectl get pods -n charno-web -w`

That's it! You now have a fully automated GitOps pipeline. 🚀
