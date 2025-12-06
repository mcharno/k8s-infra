
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

