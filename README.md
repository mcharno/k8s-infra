
# Kubernetes Infrastructure



This repository contains all Kubernetes manifests and configurations needed to rebuild the entire cluster from scratch. It follows a GitOps-friendly monorepo structure compatible with tools like ArgoCD and Flux.

## 🚀 Quick Start

**New!** Automated deployment with GitHub Actions:

```bash
./scripts/setup-github-actions.sh
```

See [GITHUB-ACTIONS.md](GITHUB-ACTIONS.md) for complete CI/CD setup guide.



## Repository Structure

 

```

k8s-infra/

├── apps/                      # Application deployments

│   ├── charno-web/           # Personal website (manifests in web-app repo)

│   ├── nextcloud/

│   ├── wallabag/

│   ├── prometheus/

│   ├── grafana/

│   ├── jellyfin/

│   ├── homeassistant/

│   ├── homer/

│   └── samba/                # LAN file sharing (SMB/CIFS)

├── argocd/                   # ArgoCD Application manifests

│   └── applications/         # ArgoCD apps

│       └── charno-web.yaml   # Charno web GitOps config

├── infrastructure/           # Core infrastructure components

│   ├── argocd/              # ArgoCD ingress configuration

│   ├── ingress-nginx/       # Nginx ingress controller

│   ├── cert-manager/        # Certificate management

│   ├── rbac/                # GitHub Actions RBAC

│   └── databases/           # Shared database services

│       ├── postgres/        # PostgreSQL

│       └── redis/           # Redis

├── .github/                 # GitHub Actions CI/CD

│   └── workflows/           # Automated deployment workflows

└── scripts/                 # Helper scripts

    ├── setup-github-actions.sh  # CI/CD setup

    └── argocd/              # ArgoCD setup scripts

        ├── install-argocd.sh

        ├── setup-ghcr-secret.sh

        └── setup-database-secret.sh

```

 

Each application directory follows the Kustomize structure:

- `base/` - Base manifests (deployment, service, configmap, etc.)

- `overlays/` - Environment-specific overrides (if needed)

 

## Prerequisites

 

- Kubernetes cluster (v1.24+)

- kubectl configured with cluster access

- (Optional) Kustomize CLI

- (Optional) ArgoCD or Flux for GitOps automation

 

## Quick Start

 

### Apply All Infrastructure Components

 

```bash

# Install infrastructure components first

kubectl apply -k infrastructure/ingress-nginx/

kubectl apply -k infrastructure/cert-manager/

kubectl apply -k infrastructure/databases/postgres/

kubectl apply -k infrastructure/databases/redis/

```

 

### Deploy Applications

 

```bash

# Deploy individual apps

kubectl apply -k apps/nextcloud/base/

kubectl apply -k apps/wallabag/base/

kubectl apply -k apps/prometheus/base/

kubectl apply -k apps/grafana/base/

kubectl apply -k apps/jellyfin/base/

kubectl apply -k apps/homeassistant/base/

kubectl apply -k apps/homer/base/

```

 

## Disaster Recovery

 

To rebuild the entire cluster from this repository:

 

1. **Create a new Kubernetes cluster**

2. **Clone this repository**

   ```bash

   git clone https://github.com/mcharno/k8s-infra.git

   cd k8s-infra

   ```

 

3. **Apply infrastructure in order**

   ```bash

   # Ingress controller

   kubectl apply -k infrastructure/ingress-nginx/

   kubectl wait --for=condition=available --timeout=300s deployment -n ingress-nginx ingress-nginx-controller

 

   # Certificate manager

   kubectl apply -k infrastructure/cert-manager/

   kubectl wait --for=condition=available --timeout=300s deployment -n cert-manager cert-manager

 

   # Databases

   kubectl apply -k infrastructure/databases/postgres/

   kubectl apply -k infrastructure/databases/redis/

   ```

 

4. **Deploy applications**

   ```bash

   for app in apps/*/base; do

     kubectl apply -k "$app"

   done

   ```

 

5. **Restore persistent data** (from backups - not stored in git)

   - Database dumps

   - Persistent volume data

   - Secrets (from vault/sealed-secrets)

 

## Security Notes

 

- **Secrets are NOT stored in this repository**

- Use Kubernetes Secrets, Sealed Secrets, or external secret management (Vault, AWS Secrets Manager, etc.)

- Each app's README should document required secrets

 

## CI/CD with GitHub Actions

This repository includes automated deployment workflows. See [GITHUB-ACTIONS.md](GITHUB-ACTIONS.md) for setup.

**Features:**
- ✅ Automated validation and security scanning
- ✅ Push-to-deploy for infrastructure and apps
- ✅ Manual workflow dispatch for selective deployments
- ✅ Secure RBAC with dedicated service account
- ✅ Environment protection for production

**Quick setup:**
```bash
./scripts/setup-github-actions.sh
# Follow the prompts to add kubeconfig to GitHub Secrets
```

## GitOps Integration

### ArgoCD + GitHub Actions

**Automated deployments with GitOps!** See [ARGOCD-GITHUB-ACTIONS.md](ARGOCD-GITHUB-ACTIONS.md) for complete integration guide.

**Quick start:**
1. Install ArgoCD: `./scripts/argocd/install-argocd.sh`
2. Deploy ArgoCD Application: `kubectl apply -f argocd/applications/charno-web.yaml`
3. Setup GHCR secret: `./scripts/argocd/setup-ghcr-secret.sh`
4. Add workflow to your app repo from `.github/workflow-templates/`

**Flow:** Code Push → GitHub Actions (Build + Push + Update Manifest) → ArgoCD (Auto-Sync) → k3s (Deploy)

### With ArgoCD (Manual)

 

Create an Application that points to this repository:

 

```yaml

apiVersion: argoproj.io/v1alpha1

kind: Application

metadata:

  name: k8s-apps

  namespace: argocd

spec:

  project: default

  source:

    repoURL: https://github.com/mcharno/k8s-infra.git

    targetRevision: main

    path: apps

  destination:

    server: https://kubernetes.default.svc

  syncPolicy:

    automated:

      prune: true

      selfHeal: true

```

 

### With Flux

 

```bash

flux create source git k8s-infra \

  --url=https://github.com/mcharno/k8s-infra \

  --branch=main

 

flux create kustomization apps \

  --source=k8s-infra \

  --path="./apps" \

  --prune=true

```

 

## Contributing

 

When adding a new application:

 

1. Create directory structure: `apps/app-name/{base,overlays}`

2. Add base manifests in `base/`

3. Create `kustomization.yaml` in `base/`

4. Document any required secrets or persistent volumes

5. Update this README

 

## Maintenance

 

- Keep manifests up to date with current cluster state

- Test changes in a staging environment before applying to production

- Use semantic versioning for image tags (avoid `latest`)

- Document all manual steps required during deployment

