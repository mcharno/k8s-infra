# GitHub Actions Workflow Templates

This directory contains workflow templates for integrating GitHub Actions with ArgoCD for GitOps deployments.

## Available Templates

### 1. `simple-argocd-deploy.yaml`

**Recommended for:** Most projects

**Description:** Simplified workflow that builds, pushes, and updates Kubernetes manifests in a single job.

**Features:**
- ✅ Single job workflow
- ✅ Builds Docker image
- ✅ Pushes to GitHub Container Registry
- ✅ Updates k8s manifest with new image tag
- ✅ Commits and pushes manifest change
- ✅ ArgoCD auto-syncs the change

**Usage:**
```bash
# In your web-app repository
cp simple-argocd-deploy.yaml .github/workflows/deploy.yaml
git add .github/workflows/deploy.yaml
git commit -m "Add ArgoCD deployment workflow"
git push
```

**Workflow triggers:**
- Push to `main` branch
- Manual workflow dispatch

### 2. `deploy-with-argocd.yaml`

**Recommended for:** Advanced projects with specific requirements

**Description:** Full-featured workflow with separate jobs for building, updating manifests, and notifications.

**Features:**
- ✅ Multi-job workflow with dependencies
- ✅ Multi-platform builds (amd64, arm64)
- ✅ Advanced Docker BuildKit caching
- ✅ Comprehensive image tagging strategy
- ✅ Detailed deployment summaries
- ✅ Optional ArgoCD API integration
- ✅ GitHub job summaries

**Usage:**
```bash
# In your web-app repository
cp deploy-with-argocd.yaml .github/workflows/deploy.yaml
# Review and customize if needed
git add .github/workflows/deploy.yaml
git commit -m "Add advanced ArgoCD deployment workflow"
git push
```

**Workflow triggers:**
- Push to `main` branch (with path filters)
- Pull requests (for validation)
- Manual workflow dispatch with environment selection

## How to Use These Templates

### Prerequisites

1. **ArgoCD installed** on your k3s cluster
2. **ArgoCD Application** created for your app
3. **GHCR secret** configured in your k3s cluster
4. **Kubernetes manifests** in your app repository (usually `k8s/base/`)

See [ARGOCD-GITHUB-ACTIONS.md](../../ARGOCD-GITHUB-ACTIONS.md) for complete setup guide.

### Step 1: Choose a Template

- **Simple workflow**: For standard deployments
- **Advanced workflow**: For complex requirements

### Step 2: Copy to Your App Repository

The workflows should be placed in your **application repository** (e.g., `mcharno/web-app`), not in this k8s-infra repo.

```bash
# In your web-app repository
mkdir -p .github/workflows
cp /path/to/k8s-infra/.github/workflow-templates/simple-argocd-deploy.yaml \
   .github/workflows/deploy.yaml
```

### Step 3: Customize (if needed)

**Required customizations:**

None! The templates use `${{ github.repository }}` which automatically uses your repo name.

**Optional customizations:**

**Change image registry:**
```yaml
env:
  REGISTRY: ghcr.io  # Or docker.io, quay.io, etc.
```

**Change manifest path:**
```yaml
# If your deployment is not at k8s/base/deployment.yaml
sed -i "s|...|...|g" path/to/your/deployment.yaml
```

**Add environment variables:**
```yaml
env:
  NODE_ENV: production
  API_URL: https://api.example.com
```

**Change trigger branches:**
```yaml
on:
  push:
    branches: [main, develop, staging]
```

### Step 4: Test the Workflow

```bash
# Make a test commit
echo "# Test" >> README.md
git add README.md
git commit -m "Test ArgoCD workflow"
git push origin main
```

**Watch the workflow:**
1. Go to your repository on GitHub
2. Click **Actions** tab
3. See the workflow running
4. Check each step completes successfully

**Verify deployment:**
```bash
# Check ArgoCD detected the change
kubectl get application <your-app> -n argocd

# Watch pods update
kubectl get pods -n <your-namespace> -w

# Check image version
kubectl get deployment <your-app> -n <your-namespace> \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Workflow Comparison

| Feature | Simple | Advanced |
|---------|--------|----------|
| **Complexity** | Low | Medium-High |
| **Jobs** | 1 | 4 |
| **Multi-platform builds** | ❌ | ✅ |
| **BuildKit caching** | ❌ | ✅ |
| **Advanced tagging** | ❌ | ✅ |
| **Job summaries** | Basic | Detailed |
| **ArgoCD API integration** | ❌ | Optional |
| **Best for** | Small-medium apps | Production apps |

## GitOps Flow

```
┌──────────────────┐
│  Code Change     │
│  (git push)      │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────┐
│     GitHub Actions Workflow          │
│  ┌────────────────────────────────┐  │
│  │ 1. Build Docker image          │  │
│  │ 2. Push to GHCR                │  │
│  │ 3. Update k8s manifest (image) │  │
│  │ 4. Commit manifest to Git      │  │
│  └────────────────────────────────┘  │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│         Git Repository               │
│  k8s/base/deployment.yaml (updated)  │
└──────────────┬───────────────────────┘
               │
               │ ArgoCD polls (every 3min)
               │ or webhook trigger
               ▼
┌──────────────────────────────────────┐
│            ArgoCD                    │
│  ┌────────────────────────────────┐  │
│  │ 1. Detect manifest change      │  │
│  │ 2. Sync desired state          │  │
│  │ 3. Apply to cluster            │  │
│  │ 4. Monitor health              │  │
│  └────────────────────────────────┘  │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│         k3s Cluster                  │
│  Deployment updated                  │
│  Pods rolled out                     │
│  New version running                 │
└──────────────────────────────────────┘
```

## Required Repository Structure

Your application repository should have:

```
your-app/
├── .github/
│   └── workflows/
│       └── deploy.yaml       # Workflow (from template)
├── src/                      # Application source code
├── Dockerfile                # Docker build instructions
├── k8s/
│   └── base/
│       ├── deployment.yaml   # Kubernetes Deployment
│       ├── service.yaml      # Kubernetes Service
│       └── kustomization.yaml
└── package.json (or similar)
```

**Critical:** The `k8s/base/deployment.yaml` must include:
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-secret  # For private GHCR repos
      containers:
      - name: your-app
        image: ghcr.io/youruser/yourapp:tag  # Auto-updated by workflow
```

## Troubleshooting

### Workflow fails at "Build and Push"

**Problem:** Docker build fails

**Solutions:**
- Check Dockerfile syntax
- Ensure all dependencies are available
- Check build logs in GitHub Actions

### Workflow fails at "Update Manifest"

**Problem:** Can't find or update deployment.yaml

**Solutions:**
- Verify path: `k8s/base/deployment.yaml` exists
- Check the sed command matches your image format
- Ensure image line exists in deployment.yaml

### Workflow fails at "Commit and Push"

**Problem:** Git push rejected

**Solutions:**
- Ensure workflow has `contents: write` permission
- Check if branch is protected (disable for bot commits)
- Verify git config is set correctly

### ArgoCD doesn't sync

**Problem:** Manifest updated but pods don't update

**Solutions:**
- Check ArgoCD Application exists: `kubectl get app -n argocd`
- Verify auto-sync is enabled: `kubectl get app <name> -n argocd -o yaml`
- Force sync: `argocd app sync <app-name>`
- Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`

### Image pull errors

**Problem:** Pods can't pull the new image

**Solutions:**
- Verify GHCR secret exists: `kubectl get secret ghcr-secret -n <namespace>`
- Check image is public or secret has correct credentials
- Verify imagePullSecrets is set in deployment

## Additional Resources

- **Full setup guide:** [ARGOCD-GITHUB-ACTIONS.md](../../ARGOCD-GITHUB-ACTIONS.md)
- **ArgoCD documentation:** https://argo-cd.readthedocs.io
- **GitHub Actions documentation:** https://docs.github.com/en/actions
- **Docker best practices:** https://docs.docker.com/develop/dev-best-practices/

## Support

For issues:
1. Check the [troubleshooting section](#troubleshooting)
2. Review GitHub Actions logs
3. Check ArgoCD application status
4. Verify k8s pod events

## Examples in the Wild

See the `charno-web` application in this repository for a real-world example:
- ArgoCD Application: `argocd/applications/charno-web.yaml`
- Setup scripts: `scripts/argocd/`
