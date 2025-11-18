#!/bin/bash

# Setup script for k8s-infra monorepo

# Run this script in your k8s-infra directory: ./setup-k8s-monorepo.sh

 

set -e

 

echo "Setting up k8s-infra monorepo structure..."

echo ""

 

# Create directory structure

echo "Creating directory structure..."

mkdir -p apps/{nextcloud,wallabag,prometheus,grafana,jellyfin,homeassistant,homer}/{base,overlays}

mkdir -p infrastructure/{ingress-nginx,cert-manager,databases/{postgres,redis}}

mkdir -p scripts

 

echo "✓ Directories created"

echo ""

 

# Create .gitignore

echo "Creating .gitignore..."

cat > .gitignore << 'EOF'

# Secrets - NEVER commit these

*secret*.yaml

*credentials*.yaml

*.key

*.crt

*.pem

 

# Temporary exports (review before committing)

*-export.yaml

current-export.yaml

 

# Editor files

.vscode/

.idea/

*.swp

*.swo

*~

 

# OS files

.DS_Store

Thumbs.db

 

# Backup files

*.bak

*.backup

*.old

 

# Helm

*.tgz

charts/*/charts/

 

# Kustomize

kustomization.yaml.bak

EOF

 

echo "✓ .gitignore created"

echo ""

 

# Create main README.md

echo "Creating README.md..."

cat > README.md << 'EOF'

# Kubernetes Infrastructure

 

This repository contains all Kubernetes manifests and configurations needed to rebuild the entire cluster from scratch. It follows a GitOps-friendly monorepo structure compatible with tools like ArgoCD and Flux.

 

## Repository Structure

 

```

k8s-infra/

├── apps/                      # Application deployments

│   ├── nextcloud/

│   ├── wallabag/

│   ├── prometheus/

│   ├── grafana/

│   ├── jellyfin/

│   ├── homeassistant/

│   └── homer/

└── infrastructure/            # Core infrastructure components

    ├── ingress-nginx/        # Nginx ingress controller

    ├── cert-manager/         # Certificate management

    └── databases/            # Shared database services

        ├── postgres/         # PostgreSQL

        └── redis/            # Redis

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

 

## GitOps Integration

 

### With ArgoCD

 

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

EOF

 

echo "✓ README.md created"

echo ""

 

# Create GETTING-STARTED.md

echo "Creating GETTING-STARTED.md..."

cat > GETTING-STARTED.md << 'ENDOFFILE'

# Getting Started

 

This guide will help you populate this repository with your current Kubernetes configurations.

 

## Step 1: Export Current Configurations

 

Run the export script to save your current running configs:

 

```bash

chmod +x scripts/export-current-configs.sh

./scripts/export-current-configs.sh

```

 

This creates `*-export.yaml` files in each directory.

 

## Step 2: Clean and Split Exports

 

The exported files need cleaning before committing:

 

### Option A: Manual Cleanup

1. Remove generated fields:

   - `creationTimestamp`

   - `resourceVersion`

   - `uid`

   - `selfLink`

   - `status` section (usually)

   - `managedFields`

   - `generation`

 

2. Split combined exports into separate files:

   - `deployment.yaml`

   - `service.yaml`

   - `ingress.yaml`

   - `configmap.yaml`

   - `pvc.yaml`

 

### Option B: Use kubectl-neat Plugin

```bash

# Install kubectl-neat

kubectl krew install neat

 

# Clean a manifest

kubectl get deployment nextcloud -n nextcloud -o yaml | kubectl neat > apps/nextcloud/base/deployment.yaml

```

 

## Step 3: Update Kustomization Files

 

Update each `kustomization.yaml` to reference your actual manifest files.

 

Example for `apps/nextcloud/base/kustomization.yaml`:

```yaml

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

  - configmap.yaml  # if you have one

```

 

## Step 4: Handle Secrets

 

**NEVER commit secrets to git!**

 

Instead, create a separate secrets documentation.

 

See the example in each app's README for secret creation commands.

 

### Secret Management Options

 

1. Manual creation (not recommended for production)

2. Sealed Secrets (recommended) - encrypts secrets that can be safely committed

3. External Secrets Operator - integrates with Vault, AWS Secrets Manager, etc.

 

## Step 5: Test Your Manifests

 

Before committing, verify they apply correctly:

 

```bash

# Dry-run to check syntax

kubectl apply -k apps/nextcloud/base/ --dry-run=client

 

# Apply to a test namespace

kubectl create namespace nextcloud-test

kubectl apply -k apps/nextcloud/base/ --namespace=nextcloud-test

 

# Clean up test

kubectl delete namespace nextcloud-test

```

 

## Step 6: Commit to Git

 

```bash

git add .

git commit -m "Initial commit: Add Kubernetes manifests for all apps"

git push origin main

```

 

## Step 7: Set Up GitOps (Optional)

 

### With ArgoCD

Install ArgoCD and configure it to watch this repository.

See the main README.md for ArgoCD configuration examples.

 

## Ongoing Maintenance

 

1. **When you change a resource in the cluster:**

   ```bash

   kubectl get deployment nextcloud -n nextcloud -o yaml | kubectl neat > apps/nextcloud/base/deployment.yaml

   git add apps/nextcloud/base/deployment.yaml

   git commit -m "Update nextcloud deployment"

   git push

   ```

 

2. **When adding a new application:**

   ```bash

   mkdir -p apps/new-app/{base,overlays}

   # Export and clean manifests

   # Update apps/new-app/base/kustomization.yaml

   # Commit and push

   ```

 

3. **Regular backups:**

   - Database dumps

   - PersistentVolume data

   - Secrets (encrypted)

 

## Troubleshooting

 

**Problem: kustomization.yaml references files that don't exist**

- Comment out missing files in kustomization.yaml

- Export them from your cluster

- Uncomment once added

 

**Problem: Secrets not working**

- Check that secrets are created in the correct namespace

- Verify secret names match what deployments reference

- Use `kubectl describe pod` to see secret mount errors

 

**Problem: PersistentVolumes not binding**

- Ensure StorageClass exists

- Check PVC requests match available storage

- Verify access modes are supported by your storage provider

ENDOFFILE

 

echo "✓ GETTING-STARTED.md created"

echo ""

 

# Create export script

echo "Creating export script..."

cat > scripts/export-current-configs.sh << 'EOF'

#!/bin/bash

# Script to export current Kubernetes configurations

# This helps populate the repository with your actual running configs

 

set -e

 

echo "Exporting current Kubernetes configurations..."

 

# Infrastructure

echo "Exporting ingress-nginx..."

kubectl get all,configmap,ingressclass -n ingress-nginx -o yaml > infrastructure/ingress-nginx/current-export.yaml

 

echo "Exporting cert-manager..."

kubectl get all,configmap -n cert-manager -o yaml > infrastructure/cert-manager/current-export.yaml

kubectl get clusterissuer -o yaml > infrastructure/cert-manager/clusterissuers.yaml

 

echo "Exporting database namespace..."

kubectl get all,configmap,pvc,statefulset -n database -o yaml > infrastructure/databases/current-export.yaml

 

# Applications

apps=("nextcloud" "wallabag" "jellyfin" "homeassistant" "homer")

for app in "${apps[@]}"; do

    if kubectl get namespace "$app" &> /dev/null; then

        echo "Exporting $app..."

        kubectl get all,ingress,configmap,pvc -n "$app" -o yaml > "apps/$app/base/current-export.yaml"

    else

        echo "Namespace $app not found, skipping..."

    fi

done

 

# Monitoring namespace (prometheus & grafana)

if kubectl get namespace monitoring &> /dev/null; then

    echo "Exporting monitoring (prometheus & grafana)..."

    kubectl get all,ingress,configmap,pvc -n monitoring -o yaml > apps/prometheus/base/monitoring-export.yaml

    # You'll need to split this into prometheus and grafana directories manually

fi

 

echo ""

echo "Export complete! Files saved as *-export.yaml"

echo ""

echo "Next steps:"

echo "1. Review each *-export.yaml file"

echo "2. Remove generated fields (resourceVersion, uid, status, etc.)"

echo "3. Split combined exports into individual resource files"

echo "4. Update kustomization.yaml to reference the actual files"

echo "5. Commit to git"

echo ""

echo "Tip: Use 'kubectl neat' plugin to clean up exported manifests:"

echo "  kubectl krew install neat"

echo "  kubectl get deployment <name> -o yaml | kubectl neat > deployment.yaml"

EOF

 

chmod +x scripts/export-current-configs.sh

echo "✓ Export script created"

echo ""

 

#############################################

# APPS - Nextcloud

#############################################

echo "Creating Nextcloud templates..."

cat > apps/nextcloud/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: nextcloud

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

  # - configmap.yaml  # Uncomment if needed

 

commonLabels:

  app: nextcloud

EOF

 

cat > apps/nextcloud/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: nextcloud

EOF

 

cat > apps/nextcloud/base/README.md << 'EOF'

# Nextcloud

 

## Description

Nextcloud deployment configuration.

 

## Required Secrets

Create these secrets before deploying:

 

```bash

kubectl create secret generic nextcloud-db \

  --namespace=nextcloud \

  --from-literal=db-host=postgres.database.svc.cluster.local \

  --from-literal=db-user=nextcloud \

  --from-literal=db-password=<your-password> \

  --from-literal=db-name=nextcloud

 

kubectl create secret generic nextcloud-admin \

  --namespace=nextcloud \

  --from-literal=admin-user=admin \

  --from-literal=admin-password=<your-password>

```

 

## Persistent Storage

- Data volume: `/var/www/html/data`

- Config volume: `/var/www/html/config`

 

## Deploy

```bash

kubectl apply -k apps/nextcloud/base/

```

 

## Notes

- Add actual deployment, service, ingress, and PVC manifests based on your current setup

- Export current manifests: `kubectl get deployment,service,ingress,pvc -n nextcloud -o yaml > current-config.yaml`

EOF

 

#############################################

# APPS - Wallabag

#############################################

echo "Creating Wallabag templates..."

cat > apps/wallabag/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: wallabag

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

 

commonLabels:

  app: wallabag

EOF

 

cat > apps/wallabag/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: wallabag

EOF

 

cat > apps/wallabag/base/README.md << 'EOF'

# Wallabag

 

## Description

Wallabag read-it-later service deployment.

 

## Required Secrets

```bash

kubectl create secret generic wallabag-db \

  --namespace=wallabag \

  --from-literal=db-host=postgres.database.svc.cluster.local \

  --from-literal=db-user=wallabag \

  --from-literal=db-password=<your-password> \

  --from-literal=db-name=wallabag

```

 

## Deploy

```bash

kubectl apply -k apps/wallabag/base/

```

EOF

 

#############################################

# APPS - Prometheus

#############################################

echo "Creating Prometheus templates..."

cat > apps/prometheus/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: monitoring

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - configmap.yaml

  - pvc.yaml

 

commonLabels:

  app: prometheus

EOF

 

cat > apps/prometheus/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: monitoring

EOF

 

cat > apps/prometheus/base/README.md << 'EOF'

# Prometheus

 

## Description

Prometheus monitoring system.

 

## Configuration

- Add your `prometheus.yml` configuration to `configmap.yaml`

- Configure scrape targets for your applications

 

## Persistent Storage

- TSDB data: `/prometheus`

 

## Deploy

```bash

kubectl apply -k apps/prometheus/base/

```

 

## Access

- Internal: `http://prometheus.monitoring.svc.cluster.local:9090`

EOF

 

#############################################

# APPS - Grafana

#############################################

echo "Creating Grafana templates..."

cat > apps/grafana/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: monitoring

 

resources:

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

  - configmap.yaml

 

commonLabels:

  app: grafana

EOF

 

cat > apps/grafana/base/README.md << 'EOF'

# Grafana

 

## Description

Grafana dashboards and visualization.

 

## Required Secrets

```bash

kubectl create secret generic grafana-admin \

  --namespace=monitoring \

  --from-literal=admin-user=admin \

  --from-literal=admin-password=<your-password>

```

 

## Configuration

- Datasources configured via configmap

- Default datasource: Prometheus (http://prometheus.monitoring.svc.cluster.local:9090)

 

## Deploy

```bash

kubectl apply -k apps/grafana/base/

```

EOF

 

#############################################

# APPS - Jellyfin

#############################################

echo "Creating Jellyfin templates..."

cat > apps/jellyfin/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: media

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

 

commonLabels:

  app: jellyfin

EOF

 

cat > apps/jellyfin/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: media

EOF

 

cat > apps/jellyfin/base/README.md << 'EOF'

# Jellyfin

 

## Description

Jellyfin media server deployment.

 

## Persistent Storage

- Config: `/config`

- Media: `/media` (consider NFS or hostPath for large media libraries)

- Cache: `/cache`

 

## Notes

- May require hardware acceleration configuration for transcoding

- Consider nodeSelector for GPU nodes if using hardware transcoding

 

## Deploy

```bash

kubectl apply -k apps/jellyfin/base/

```

EOF

 

#############################################

# APPS - Home Assistant

#############################################

echo "Creating Home Assistant templates..."

cat > apps/homeassistant/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: homeassistant

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - pvc.yaml

 

commonLabels:

  app: homeassistant

EOF

 

cat > apps/homeassistant/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: homeassistant

EOF

 

cat > apps/homeassistant/base/README.md << 'EOF'

# Home Assistant

 

## Description

Home Assistant home automation platform.

 

## Persistent Storage

- Config: `/config`

 

## Network Requirements

- May need hostNetwork: true for device discovery

- Consider nodeSelector if USB devices are attached to specific nodes

 

## Deploy

```bash

kubectl apply -k apps/homeassistant/base/

```

 

## Notes

- Export configuration.yaml and other config files separately

- Some integrations may require special network or device access

EOF

 

#############################################

# APPS - Homer

#############################################

echo "Creating Homer templates..."

cat > apps/homer/base/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: homer

 

resources:

  - namespace.yaml

  - deployment.yaml

  - service.yaml

  - ingress.yaml

  - configmap.yaml

 

commonLabels:

  app: homer

EOF

 

cat > apps/homer/base/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: homer

EOF

 

cat > apps/homer/base/README.md << 'EOF'

# Homer

 

## Description

Homer dashboard for application access.

 

## Configuration

- Dashboard configuration in `configmap.yaml`

- Store `config.yml` as a ConfigMap

 

## Deploy

```bash

kubectl apply -k apps/homer/base/

```

 

## Notes

- Lightweight, doesn't require persistent storage

- Configuration is entirely in ConfigMap

EOF

 

#############################################

# INFRASTRUCTURE - Ingress NGINX

#############################################

echo "Creating Ingress NGINX templates..."

cat > infrastructure/ingress-nginx/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: ingress-nginx

 

resources:

  - namespace.yaml

  # Option 1: Use official Helm chart export or manifests

  # Download from: https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

 

  # Option 2: Reference your current deployment

  # - deployment.yaml

  # - service.yaml

  # - configmap.yaml

 

commonLabels:

  app.kubernetes.io/name: ingress-nginx

EOF

 

cat > infrastructure/ingress-nginx/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: ingress-nginx

EOF

 

cat > infrastructure/ingress-nginx/README.md << 'EOF'

# Ingress NGINX

 

## Description

NGINX Ingress Controller for managing external access to services.

 

## Installation Options

 

### Option 1: Export Current Configuration

```bash

kubectl get all,configmap,secret -n ingress-nginx -o yaml > infrastructure/ingress-nginx/current-config.yaml

# Then split into appropriate files

```

 

### Option 2: Use Official Manifests

```bash

curl -o infrastructure/ingress-nginx/deploy.yaml \

  https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

```

 

### Option 3: Helm Template

```bash

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm template ingress-nginx ingress-nginx/ingress-nginx \

  --namespace ingress-nginx \

  --set controller.service.type=LoadBalancer \

  > infrastructure/ingress-nginx/helm-generated.yaml

```

 

## Deploy

```bash

kubectl apply -k infrastructure/ingress-nginx/

```

 

## Verify

```bash

kubectl get pods -n ingress-nginx

kubectl get svc -n ingress-nginx

```

EOF

 

#############################################

# INFRASTRUCTURE - Cert Manager

#############################################

echo "Creating Cert Manager templates..."

cat > infrastructure/cert-manager/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: cert-manager

 

resources:

  - namespace.yaml

  # Add cert-manager CRDs and deployment manifests

  # Download from: https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

 

  # Custom resources:

  # - clusterissuer-letsencrypt-prod.yaml

  # - clusterissuer-letsencrypt-staging.yaml

 

commonLabels:

  app.kubernetes.io/name: cert-manager

EOF

 

cat > infrastructure/cert-manager/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: cert-manager

EOF

 

cat > infrastructure/cert-manager/README.md << 'EOF'

# Cert-Manager

 

## Description

Automatic SSL/TLS certificate management for Kubernetes.

 

## Installation

 

### Download Official Manifests

```bash

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

```

 

Or save to this directory:

```bash

curl -L -o infrastructure/cert-manager/cert-manager.yaml \

  https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

```

 

### ClusterIssuer Configuration

 

Create `clusterissuer-letsencrypt-prod.yaml`:

```yaml

apiVersion: cert-manager.io/v1

kind: ClusterIssuer

metadata:

  name: letsencrypt-prod

spec:

  acme:

    server: https://acme-v02.api.letsencrypt.org/directory

    email: your-email@example.com

    privateKeySecretRef:

      name: letsencrypt-prod

    solvers:

    - http01:

        ingress:

          class: nginx

```

 

## Deploy

```bash

kubectl apply -k infrastructure/cert-manager/

```

 

## Verify

```bash

kubectl get pods -n cert-manager

kubectl get clusterissuer

```

EOF

 

#############################################

# INFRASTRUCTURE - PostgreSQL

#############################################

echo "Creating PostgreSQL templates..."

cat > infrastructure/databases/postgres/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: database

 

resources:

  - namespace.yaml

  - statefulset.yaml

  - service.yaml

  - pvc.yaml

  - configmap.yaml

 

commonLabels:

  app: postgres

EOF

 

cat > infrastructure/databases/postgres/namespace.yaml << 'EOF'

apiVersion: v1

kind: Namespace

metadata:

  name: database

EOF

 

cat > infrastructure/databases/postgres/README.md << 'EOF'

# PostgreSQL

 

## Description

Shared PostgreSQL database for applications.

 

## Required Secrets

```bash

kubectl create secret generic postgres-credentials \

  --namespace=database \

  --from-literal=postgres-password=<your-secure-password>

```

 

## Databases

Create databases for each application:

- nextcloud

- wallabag

- (add others as needed)

 

## Persistent Storage

- Data directory: `/var/lib/postgresql/data`

- Recommend using StatefulSet with persistent volume claims

 

## Deploy

```bash

kubectl apply -k infrastructure/databases/postgres/

```

 

## Backup

Set up regular pg_dump backups:

```bash

kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup.sql

```

 

## Access

- Internal DNS: `postgres.database.svc.cluster.local:5432`

EOF

 

#############################################

# INFRASTRUCTURE - Redis

#############################################

echo "Creating Redis templates..."

cat > infrastructure/databases/redis/kustomization.yaml << 'EOF'

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

 

namespace: database

 

resources:

  - deployment.yaml

  - service.yaml

  - pvc.yaml

  - configmap.yaml

 

commonLabels:

  app: redis

EOF

 

cat > infrastructure/databases/redis/README.md << 'EOF'

# Redis

 

## Description

Shared Redis cache and message broker.

 

## Configuration

- Persistence enabled (AOF + RDB)

- MaxMemory policy: allkeys-lru

 

## Required Secrets

```bash

kubectl create secret generic redis-credentials \

  --namespace=database \

  --from-literal=redis-password=<your-secure-password>

```

 

## Persistent Storage

- Data directory: `/data`

 

## Deploy

```bash

kubectl apply -k infrastructure/databases/redis/

```

 

## Access

- Internal DNS: `redis.database.svc.cluster.local:6379`

 

## Monitoring

Connect Prometheus to Redis exporter if needed.

EOF

 

echo ""

echo "=========================================="

echo "✓ Setup complete!"

echo "=========================================="

echo ""

echo "Created structure:"

echo "  - apps/ (7 applications)"

echo "  - infrastructure/ (ingress, cert-manager, databases)"

echo "  - scripts/export-current-configs.sh"

echo "  - README.md, GETTING-STARTED.md, .gitignore"

echo ""

echo "Next steps:"

echo "  1. Review the GETTING-STARTED.md guide"

echo "  2. Run: ./scripts/export-current-configs.sh"

echo "  3. Clean and organize exported manifests"

echo "  4. Commit to git"

echo ""
