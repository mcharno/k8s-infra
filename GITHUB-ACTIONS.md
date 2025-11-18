# GitHub Actions CI/CD Setup

This repository includes GitHub Actions workflows for automated deployment to your k3s cluster.

## Quick Start

### 1. Prerequisites

- k3s cluster up and running
- kubectl configured with admin access
- GitHub repository with Actions enabled

### 2. Setup (5 minutes)

Run the automated setup script:

```bash
./scripts/setup-github-actions.sh
```

This script will:
1. Deploy RBAC resources (service account, roles, bindings)
2. Generate a secure kubeconfig for GitHub Actions
3. Provide base64-encoded kubeconfig to add as GitHub Secret

### 3. Add GitHub Secret

1. Copy the base64 kubeconfig from the script output
2. Go to your GitHub repository: **Settings → Secrets and variables → Actions**
3. Click **New repository secret**
4. Name: `KUBECONFIG`
5. Paste the base64 string
6. Click **Add secret**

### 4. Test Deployment

1. Go to **Actions** tab
2. Select "Deploy Infrastructure" workflow
3. Click **Run workflow**
4. Choose component: `rbac`
5. Watch it deploy! 🚀

## What Gets Deployed

### Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Validate PR** | All PRs | Validates manifests, checks security |
| **Deploy Infrastructure** | Push to main, Manual | Deploys infrastructure components |
| **Deploy Apps** | Push to main, Manual | Deploys applications |
| **Deploy ArgoCD Apps** | Push to main, Manual | Deploys ArgoCD Application manifests |

### Security Features

✅ **Automated Validation**
- YAML syntax checking
- Kubernetes resource validation
- Security scanning (kubesec)
- Secret detection
- Resource limit checks

✅ **Secure Access**
- Dedicated service account with RBAC
- Encrypted kubeconfig in GitHub Secrets
- Environment protection for production
- Least privilege permissions

✅ **Audit Trail**
- All deployments logged in GitHub Actions
- Rollout status verification
- Deployment summaries

## Usage Examples

### Automatic Deployment

Push changes to main branch:

```bash
# Update an app
vim apps/nextcloud/base/deployment.yaml
git add apps/nextcloud/
git commit -m "Update Nextcloud to v28"
git push origin main

# GitHub Actions automatically deploys
```

### Manual Deployment

Deploy specific components without code changes:

1. **Actions** → **Deploy Infrastructure** → **Run workflow**
2. Select component (e.g., `databases`)
3. Click **Run workflow**

### Safe Testing with PRs

All PRs are validated before merge:

```bash
git checkout -b feature/new-app
# Make changes
git push origin feature/new-app
# Create PR - automatic validation runs
# Merge after review and validation passes
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       GitHub Repository                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Apps         │  │Infrastructure│  │ ArgoCD Apps      │  │
│  │ Manifests    │  │ Manifests    │  │ Manifests        │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                  │                    │            │
└─────────┼──────────────────┼────────────────────┼────────────┘
          │                  │                    │
          │  Push to main    │                    │
          │  or Manual       │                    │
          ▼                  ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                      GitHub Actions                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  1. Validate (kubeval, kubesec, secret scan)         │   │
│  │  2. Build (kustomize)                                │   │
│  │  3. Deploy (kubectl apply)                           │   │
│  │  4. Verify (rollout status)                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Authenticated via
                          │ Service Account Token
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      k3s Cluster                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Service Account: github-actions-deployer           │    │
│  │  Namespace: github-actions                          │    │
│  │  Permissions: ClusterRole (RBAC)                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Apps         │  │Infrastructure│  │ ArgoCD           │  │
│  │ (Deployed)   │  │ (Deployed)   │  │ (GitOps)         │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Security Best Practices

### 1. Secrets Management

**Never commit secrets to the repository!**

- Use Kubernetes Secrets for application credentials
- Store kubeconfig in GitHub Secrets (encrypted)
- Use environment protection for production deployments
- Rotate service account tokens regularly

### 2. RBAC Permissions

The GitHub Actions service account has:

✅ **Allowed:**
- Create/update/delete deployments, services, ingresses
- Manage application namespaces
- Deploy cert-manager and ArgoCD resources

❌ **Denied:**
- Modify other service accounts' permissions
- Access sensitive cluster-wide configurations
- Execute commands in pods (no pod/exec)

Review and adjust: `infrastructure/rbac/clusterrole.yaml`

### 3. Validation & Testing

All changes go through:
1. ✅ YAML syntax validation
2. ✅ Kubernetes resource validation
3. ✅ Security scanning
4. ✅ Hardcoded secret detection
5. ✅ Kustomize build testing

### 4. Environment Protection

Set up in GitHub:
- **Settings → Environments → production**
- Require approvals for production deployments
- Restrict to main branch only
- Add wait timer for rollback window

### 5. Monitoring & Auditing

- Review Actions logs for all deployments
- Set up k3s audit logging
- Monitor service account usage
- Enable GitHub audit log

## Maintenance

### Rotate Service Account Token

```bash
# Generate new token
kubectl create token github-actions-deployer \
  -n github-actions \
  --duration=87600h  # 10 years

# Update GitHub Secret
# Settings → Secrets → KUBECONFIG → Update
```

### Update RBAC Permissions

```bash
# Edit ClusterRole
vim infrastructure/rbac/clusterrole.yaml

# Apply changes
kubectl apply -k infrastructure/rbac/

# Test permissions
kubectl auth can-i --list \
  --as=system:serviceaccount:github-actions:github-actions-deployer
```

### Troubleshooting

#### Connection Issues

```bash
# Test kubeconfig locally
export KUBECONFIG=/tmp/github-actions-kubeconfig
kubectl cluster-info
```

#### Permission Denied

```bash
# Check what the service account can do
kubectl auth can-i create deployments --all-namespaces \
  --as=system:serviceaccount:github-actions:github-actions-deployer
```

#### Workflow Failures

1. Check Actions logs for error messages
2. Verify kubeconfig secret is correctly formatted (base64)
3. Ensure RBAC resources are deployed
4. Test manifest validity:
   ```bash
   kubectl apply --dry-run=client -k apps/myapp/base/
   ```

## Advanced Usage

### Custom Workflows

Create custom workflows in `.github/workflows/`:

```yaml
name: Deploy Custom Component
on:
  workflow_dispatch:
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure kubectl
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config
      - name: Deploy
        run: kubectl apply -k path/to/manifests/
```

### Integration with ArgoCD

Use GitHub Actions to manage ArgoCD Application manifests:

```bash
# ArgoCD handles the actual deployment
# GitHub Actions just manages the Application specs
git push origin main  # → Deploys ArgoCD App → ArgoCD syncs actual resources
```

### Multi-Environment Setup

Add environment-specific secrets:

- `KUBECONFIG_DEV` for development cluster
- `KUBECONFIG_PROD` for production cluster

Use in workflows:

```yaml
- name: Configure kubectl (dev)
  if: github.ref != 'refs/heads/main'
  run: |
    echo "${{ secrets.KUBECONFIG_DEV }}" | base64 -d > $HOME/.kube/config
```

## Documentation

- **Detailed Setup Guide:** [.github/workflows/README.md](.github/workflows/README.md)
- **RBAC Configuration:** [infrastructure/rbac/](infrastructure/rbac/)
- **Workflow Files:** [.github/workflows/](.github/workflows/)

## Support

For issues or questions:
1. Check the [troubleshooting section](#troubleshooting)
2. Review GitHub Actions logs
3. Verify RBAC permissions
4. Test manifests locally

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [k3s Documentation](https://docs.k3s.io/)
- [Kustomize](https://kustomize.io/)
