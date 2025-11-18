# GitHub Actions CI/CD for k3s Deployment

This directory contains GitHub Actions workflows for securely deploying applications and infrastructure to your k3s cluster.

## Workflows Overview

### 1. `validate-pr.yaml` - Pull Request Validation
**Trigger:** All pull requests to main

**Purpose:** Validates manifests before they're merged

**Features:**
- YAML syntax validation with kubeval
- Kustomize build testing
- Security scanning with kubesec
- Hardcoded secret detection
- Resource limit checks
- Image tag best practices

### 2. `deploy-infrastructure.yaml` - Infrastructure Deployment
**Trigger:**
- Push to main (paths: `infrastructure/**`)
- Manual workflow dispatch with component selection

**Components:**
- RBAC for GitHub Actions
- Ingress NGINX
- Cert Manager
- ArgoCD
- Databases (PostgreSQL, Redis)

**Features:**
- Pre-deployment validation
- Ordered deployment with health checks
- Production environment protection

### 3. `deploy-apps.yaml` - Application Deployment
**Trigger:**
- Push to main (paths: `apps/**`)
- Manual workflow dispatch with app selection

**Applications:**
- Nextcloud
- Wallabag
- Prometheus
- Grafana
- Jellyfin
- Home Assistant
- Homer

**Features:**
- Manifest validation
- Selective or full deployment
- Rollout status verification
- Deployment summary

### 4. `deploy-argocd-apps.yaml` - ArgoCD Application Deployment
**Trigger:**
- Push to main (paths: `argocd/applications/**`)
- Manual workflow dispatch

**Purpose:** Deploys ArgoCD Application manifests for GitOps automation

## Security Features

### 1. Validation & Scanning
- ✅ YAML syntax validation
- ✅ Kubernetes resource validation (kubeval)
- ✅ Security scanning (kubesec)
- ✅ Hardcoded secret detection
- ✅ Resource limit checks

### 2. Access Control
- ✅ Dedicated service account with RBAC
- ✅ Encrypted kubeconfig in GitHub Secrets
- ✅ Production environment protection
- ✅ Least privilege permissions

### 3. Best Practices
- ✅ Specific kubectl versions
- ✅ Cluster verification before deployment
- ✅ Rollout status checking
- ✅ Audit logging via GitHub Actions logs

## Setup Instructions

### Step 1: Deploy RBAC Service Account

First, apply the RBAC manifests to create a dedicated service account for GitHub Actions:

```bash
kubectl apply -k infrastructure/rbac/
```

This creates:
- `github-actions` namespace
- `github-actions-deployer` service account
- ClusterRole with necessary permissions
- ClusterRoleBinding

### Step 2: Generate Kubeconfig for Service Account

Run the setup script to generate a kubeconfig for the service account:

```bash
# Create a script to generate the kubeconfig
cat > /tmp/generate-sa-kubeconfig.sh << 'EOF'
#!/bin/bash
set -e

NAMESPACE="github-actions"
SERVICE_ACCOUNT="github-actions-deployer"
CONTEXT=$(kubectl config current-context)
CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER')].cluster.server}")

# Get the service account token
SECRET_NAME=$(kubectl get serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath='{.secrets[0].name}')

# For Kubernetes 1.24+, if no secret exists, create a token
if [ -z "$SECRET_NAME" ]; then
  TOKEN=$(kubectl create token $SERVICE_ACCOUNT -n $NAMESPACE --duration=87600h)
else
  TOKEN=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)
fi

# Get the CA certificate
kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt

# Create kubeconfig
cat > /tmp/github-actions-kubeconfig << KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- name: k3s-cluster
  cluster:
    certificate-authority-data: $(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}')
    server: $SERVER
contexts:
- name: github-actions
  context:
    cluster: k3s-cluster
    user: github-actions-deployer
current-context: github-actions
users:
- name: github-actions-deployer
  user:
    token: $TOKEN
KUBECONFIG

echo "Kubeconfig generated at /tmp/github-actions-kubeconfig"
echo ""
echo "Base64 encoded kubeconfig for GitHub Secrets:"
echo ""
base64 -w 0 /tmp/github-actions-kubeconfig
echo ""
EOF

chmod +x /tmp/generate-sa-kubeconfig.sh
/tmp/generate-sa-kubeconfig.sh
```

### Step 3: Configure GitHub Secrets

1. Go to your GitHub repository settings
2. Navigate to **Settings → Secrets and variables → Actions**
3. Click **New repository secret**
4. Create the following secret:

   **Name:** `KUBECONFIG`

   **Value:** Paste the base64-encoded kubeconfig from the previous step

### Step 4: Set Up Environment Protection (Recommended)

1. Go to **Settings → Environments**
2. Create an environment named `production`
3. Configure protection rules:
   - ✅ Required reviewers (at least 1)
   - ✅ Wait timer (optional, e.g., 5 minutes)
   - ✅ Deployment branches: only `main`

### Step 5: Test the Setup

Trigger a manual workflow:

1. Go to **Actions** tab
2. Select "Deploy Infrastructure" workflow
3. Click **Run workflow**
4. Select component: `rbac`
5. Monitor the deployment

## Usage

### Automatic Deployments

Workflows automatically trigger on push to main:

```bash
# Make changes to infrastructure
vim infrastructure/ingress-nginx/namespace.yaml

git add infrastructure/
git commit -m "Update ingress configuration"
git push origin main

# GitHub Actions will automatically deploy infrastructure
```

### Manual Deployments

Use workflow dispatch for selective deployments:

1. Go to **Actions** tab
2. Select the desired workflow
3. Click **Run workflow**
4. Select the component/app to deploy
5. Click **Run workflow**

### Pull Request Validation

All PRs are automatically validated:

```bash
git checkout -b feature/add-new-app
# Make changes
git push origin feature/add-new-app
# Create PR - validation runs automatically
```

## Security Considerations

### 1. Secrets Management

**✅ DO:**
- Store kubeconfig in GitHub Secrets (encrypted at rest)
- Use environment protection rules
- Rotate service account tokens regularly
- Use Kubernetes Secrets for application secrets

**❌ DON'T:**
- Hardcode secrets in manifests
- Commit kubeconfig to repository
- Use overly permissive RBAC roles
- Disable validation checks

### 2. RBAC Permissions

The `github-actions-deployer` service account has:

- ✅ Full control over application namespaces
- ✅ Ability to create/manage standard K8s resources
- ✅ Access to cert-manager and ArgoCD CRDs
- ❌ No access to sensitive cluster-wide resources
- ❌ Cannot modify RBAC for other service accounts

Review `infrastructure/rbac/clusterrole.yaml` to audit permissions.

### 3. Audit & Monitoring

- All deployments logged in GitHub Actions
- Review deployment history in Actions tab
- Set up Kubernetes audit logging
- Monitor service account usage

### 4. Token Security

For Kubernetes 1.24+, service account tokens are time-bound. To create long-lived tokens:

```bash
kubectl create token github-actions-deployer \
  -n github-actions \
  --duration=87600h  # 10 years
```

**Alternative:** Use a Secret-based token (auto-generated):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-actions-token
  namespace: github-actions
  annotations:
    kubernetes.io/service-account.name: github-actions-deployer
type: kubernetes.io/service-account-token
```

### 5. Network Security

Ensure your k3s cluster:
- Uses HTTPS endpoints
- Has proper firewall rules
- Restricts access to Kubernetes API
- Uses network policies for pod communication

## Troubleshooting

### Connection Issues

```bash
# Test kubeconfig locally
export KUBECONFIG=/tmp/github-actions-kubeconfig
kubectl cluster-info
kubectl auth can-i create deployments --all-namespaces
```

### Permission Denied

```bash
# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:github-actions:github-actions-deployer
```

### Workflow Failures

1. Check the Actions logs for detailed error messages
2. Verify the kubeconfig secret is correctly formatted
3. Ensure the service account exists and has proper RBAC
4. Test manifest validity locally:
   ```bash
   kubectl apply --dry-run=client -k apps/nextcloud/base/
   ```

## Maintenance

### Rotating Credentials

1. Generate new service account token
2. Update GitHub Secret with new base64-encoded kubeconfig
3. Test with manual workflow dispatch
4. Old token is automatically invalidated

### Updating Workflows

Test workflow changes on a feature branch first:

```bash
git checkout -b update-workflows
# Modify workflows
git push origin update-workflows
# Create PR and review validation results
```

### Regular Security Reviews

- Monthly: Review RBAC permissions
- Quarterly: Rotate service account tokens
- Annually: Security audit of entire CI/CD pipeline

## References

- [GitHub Actions Security Best Practices](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [k3s Documentation](https://docs.k3s.io/)
