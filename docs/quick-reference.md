# Quick Reference Guide

Fast reference for common commands, connection settings, and useful snippets.

## Table of Contents

- [Connection Settings](#connection-settings)
- [Kubernetes Commands](#kubernetes-commands)
- [ArgoCD Commands](#argocd-commands)
- [GitHub Actions](#github-actions)
- [Samba File Share](#samba-file-share)
- [Monitoring & Logs](#monitoring--logs)
- [Troubleshooting Quick Checks](#troubleshooting-quick-checks)

## Connection Settings

### k3s Cluster Access

**Kubeconfig Location:**
```bash
# Default k3s kubeconfig
/etc/rancher/k3s/k3s.yaml

# Copy to standard location
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
```

**Kubernetes API:**
- Endpoint: `https://<node-ip>:6443`
- Access: Admin kubeconfig

### ArgoCD Access

**Web UI (Ingress):**
```
URL: https://argocd.yourdomain.com
Username: admin
Password: <your-changed-password>
```

**Web UI (Port Forward):**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# URL: https://localhost:8080
# Username: admin
# Password: <from setup or changed>
```

**CLI:**
```bash
# Login (port-forward)
argocd login localhost:8080

# Login (ingress)
argocd login argocd.yourdomain.com
```

### Samba File Share

**Connection Settings:**
- **Server:** `<k3s-node-ip>` or hostname
- **Port:** 30445 (or default SMB port)
- **Share Name:** `share`
- **Username:** From secret (default: `sambauser`)
- **Password:** From secret (changed during setup)

**Windows:**
```
\\<k3s-node-ip>\share
```

**macOS:**
```
smb://<k3s-node-ip>/share
```

**Linux:**
```
smb://<k3s-node-ip>/share
```

### GitHub Actions

**Workflows Location:**
- Infrastructure: `k8s-infra/.github/workflows/`
- Applications: `web-app/.github/workflows/`

**Access:**
- GitHub repo → Actions tab

**Required Secrets:**
- `KUBECONFIG`: Base64-encoded kubeconfig (infrastructure repo)
- `GITHUB_TOKEN`: Auto-provided by GitHub (app repos)

## Kubernetes Commands

### Cluster Status

```bash
# Node information
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node <node-name>

# All resources across namespaces
kubectl get all -A

# Cluster information
kubectl cluster-info
kubectl version
```

### Pods

```bash
# List pods in namespace
kubectl get pods -n <namespace>

# List all pods
kubectl get pods -A

# Watch pods
kubectl get pods -n <namespace> -w

# Describe pod (detailed info)
kubectl describe pod <pod-name> -n <namespace>

# Pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> -f  # follow
kubectl logs <pod-name> -n <namespace> --tail=100  # last 100 lines
kubectl logs <pod-name> -n <namespace> --previous  # previous container

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
```

### Deployments

```bash
# List deployments
kubectl get deployments -n <namespace>

# Describe deployment
kubectl describe deployment <deployment-name> -n <namespace>

# Scale deployment
kubectl scale deployment <deployment-name> -n <namespace> --replicas=3

# Restart deployment (rolling restart)
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Rollout status
kubectl rollout status deployment/<deployment-name> -n <namespace>

# Rollout history
kubectl rollout history deployment/<deployment-name> -n <namespace>

# Rollback
kubectl rollout undo deployment/<deployment-name> -n <namespace>
kubectl rollout undo deployment/<deployment-name> -n <namespace> --to-revision=2

# Edit deployment (live)
kubectl edit deployment <deployment-name> -n <namespace>
```

### Services & Ingress

```bash
# List services
kubectl get svc -n <namespace>
kubectl get svc -A

# Describe service
kubectl describe svc <service-name> -n <namespace>

# List ingresses
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>

# Port forward (temporary access)
kubectl port-forward svc/<service-name> -n <namespace> <local-port>:<service-port>
# Example: kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### ConfigMaps & Secrets

```bash
# List config maps
kubectl get configmaps -n <namespace>

# View configmap
kubectl get configmap <name> -n <namespace> -o yaml

# Edit configmap
kubectl edit configmap <name> -n <namespace>

# List secrets
kubectl get secrets -n <namespace>

# View secret (base64 encoded)
kubectl get secret <name> -n <namespace> -o yaml

# Decode secret value
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d

# Create secret from literal
kubectl create secret generic <name> -n <namespace> \
  --from-literal=key1=value1 \
  --from-literal=key2=value2

# Create docker registry secret
kubectl create secret docker-registry <name> -n <namespace> \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token> \
  --docker-email=<email>
```

### Namespaces

```bash
# List namespaces
kubectl get namespaces

# Create namespace
kubectl create namespace <namespace>

# Delete namespace (careful!)
kubectl delete namespace <namespace>

# Set default namespace for current context
kubectl config set-context --current --namespace=<namespace>
```

### Resources & Events

```bash
# Resource usage (requires metrics-server)
kubectl top nodes
kubectl top pods -A
kubectl top pods -n <namespace>

# Events (recent)
kubectl get events -A --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Describe events for a resource
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 Events
```

### Apply & Delete

```bash
# Apply manifest
kubectl apply -f <file.yaml>

# Apply directory
kubectl apply -f <directory>/

# Apply kustomization
kubectl apply -k <directory>/

# Delete from manifest
kubectl delete -f <file.yaml>

# Delete resource
kubectl delete pod <pod-name> -n <namespace>
kubectl delete deployment <deployment-name> -n <namespace>

# Force delete pod (stuck in terminating)
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

## ArgoCD Commands

### Application Management

```bash
# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Get application status
argocd app get <app-name> --show-operation

# Get application resources
argocd app resources <app-name>

# View application manifest
argocd app manifests <app-name>

# View differences (Git vs cluster)
argocd app diff <app-name>
```

### Sync Operations

```bash
# Sync application
argocd app sync <app-name>

# Force sync
argocd app sync <app-name> --force

# Prune during sync
argocd app sync <app-name> --prune

# Dry run
argocd app sync <app-name> --dry-run

# Sync specific resource
argocd app sync <app-name> --resource <group>:<kind>:<namespace>/<name>
```

### Application History

```bash
# View deployment history
argocd app history <app-name>

# Rollback to previous version
argocd app rollback <app-name>

# Rollback to specific revision
argocd app rollback <app-name> <revision-id>
```

### Application Creation

```bash
# Create application
argocd app create <app-name> \
  --repo <repo-url> \
  --path <path> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <namespace>

# Create with auto-sync
argocd app create <app-name> \
  --repo <repo-url> \
  --path <path> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <namespace> \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Delete application
argocd app delete <app-name>
```

### Cluster & Repository

```bash
# List repositories
argocd repo list

# Add repository
argocd repo add <repo-url>

# List clusters
argocd cluster list

# List projects
argocd proj list
```

### Via kubectl (ArgoCD Applications)

```bash
# List ArgoCD applications
kubectl get applications -n argocd

# Get application details
kubectl get application <app-name> -n argocd -o yaml

# Delete application
kubectl delete application <app-name> -n argocd
```

## GitHub Actions

### Triggering Workflows

**Automatic triggers:**
- Push to `main` branch (infrastructure/app changes)
- Pull request creation

**Manual trigger:**
1. Go to GitHub repo
2. Click "Actions" tab
3. Select workflow
4. Click "Run workflow"
5. Choose options
6. Click "Run workflow"

### Viewing Workflow Status

```bash
# Via GitHub CLI (if installed)
gh run list
gh run view <run-id>
gh run watch <run-id>

# Via web
# GitHub repo → Actions tab → Select run
```

### Checking Deployment Status

```bash
# After GitHub Actions deploys
kubectl get pods -n <namespace>
kubectl rollout status deployment/<deployment-name> -n <namespace>

# Check ArgoCD sync (for GitOps deployments)
kubectl get application <app-name> -n argocd
argocd app get <app-name>
```

## Samba File Share

### Connection Commands

**Windows (Command Line):**
```cmd
# Map drive
net use Z: \\<node-ip>\share /user:<username>

# Disconnect drive
net use Z: /delete
```

**macOS (Terminal):**
```bash
# Mount share
mount_smbfs //<username>@<node-ip>/share ~/mnt/samba

# Unmount
umount ~/mnt/samba
```

**Linux (Terminal):**
```bash
# Install cifs-utils (if needed)
sudo apt-get install cifs-utils  # Debian/Ubuntu

# Mount share
sudo mount -t cifs //<node-ip>/share /mnt/samba \
  -o username=<username>,password=<password>

# Unmount
sudo umount /mnt/samba
```

### Samba Management

```bash
# Check Samba pod status
kubectl get pods -n samba

# View Samba logs
kubectl logs -n samba deployment/samba -f

# Restart Samba
kubectl rollout restart deployment/samba -n samba

# Check Samba service
kubectl get svc -n samba

# Check storage usage (on k3s node)
du -sh /mnt/samba-share

# Change credentials
kubectl edit secret samba-credentials -n samba
kubectl rollout restart deployment/samba -n samba
```

## Monitoring & Logs

### Real-Time Monitoring

```bash
# Watch pods across all namespaces
watch kubectl get pods -A

# Watch specific namespace
watch kubectl get pods -n <namespace>

# Watch events
watch "kubectl get events -A --sort-by='.lastTimestamp' | tail -20"

# Resource usage monitoring
watch kubectl top nodes
watch kubectl top pods -A
```

### Log Aggregation

```bash
# Tail logs from multiple pods
kubectl logs -l app=<app-label> -n <namespace> -f --max-log-requests=10

# Get logs from all containers in pod
kubectl logs <pod-name> -n <namespace> --all-containers=true

# Previous container logs (after crash)
kubectl logs <pod-name> -n <namespace> --previous
```

### Component Logs

```bash
# k3s logs (on node)
sudo journalctl -u k3s -f

# ArgoCD logs
kubectl logs -n argocd deployment/argocd-server -f
kubectl logs -n argocd deployment/argocd-application-controller -f
kubectl logs -n argocd deployment/argocd-repo-server -f

# Ingress NGINX logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f
```

## Troubleshooting Quick Checks

### "Pod Not Starting"

```bash
# 1. Check pod status
kubectl get pod <pod-name> -n <namespace>

# 2. Describe pod (look for Events)
kubectl describe pod <pod-name> -n <namespace>

# 3. Check logs
kubectl logs <pod-name> -n <namespace>

# 4. Check image pull
kubectl describe pod <pod-name> -n <namespace> | grep -i image

# 5. Check resources
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 Resources
```

### "Service Not Accessible"

```bash
# 1. Check service exists
kubectl get svc <service-name> -n <namespace>

# 2. Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# 3. Check ingress (if using)
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# 4. Test from within cluster
kubectl run test-pod --rm -it --image=busybox -- /bin/sh
# Then: wget -O- http://<service-name>.<namespace>.svc.cluster.local:<port>

# 5. Port forward to test
kubectl port-forward svc/<service-name> -n <namespace> 8080:<service-port>
# Test: curl http://localhost:8080
```

### "ArgoCD Out of Sync"

```bash
# 1. Check application status
kubectl get application <app-name> -n argocd

# 2. View differences
argocd app diff <app-name>

# 3. Check sync status
argocd app get <app-name>

# 4. Force refresh
argocd app get <app-name> --refresh

# 5. Manual sync
argocd app sync <app-name>
```

### "Disk Space Issues"

```bash
# Check disk usage
df -h

# Check Docker images (if using Docker)
docker system df

# Clean up (on k3s node)
# Remove unused images
sudo k3s crictl rmi --prune

# Check specific directories
du -sh /var/lib/rancher
du -sh /mnt/samba-share
```

### "Network Issues"

```bash
# Test DNS from pod
kubectl run test-dns --rm -it --image=busybox -- nslookup kubernetes.default

# Test connectivity between pods
kubectl run test-net --rm -it --image=busybox -- ping <pod-ip>

# Check cluster DNS
kubectl get svc -n kube-system kube-dns

# Test external connectivity
kubectl run test-external --rm -it --image=busybox -- ping 8.8.8.8
```

## Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# kubectl aliases
alias k='kubectl'
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias ka='kubectl apply -f'
alias kdel='kubectl delete'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'

# Namespace quick switch
alias kn='kubectl config set-context --current --namespace'

# ArgoCD aliases
alias arcd='argocd'
alias arcda='argocd app'
alias arcdal='argocd app list'
alias arcdag='argocd app get'
alias arcdas='argocd app sync'

# Watch aliases
alias wkgp='watch kubectl get pods'
alias wkgpa='watch kubectl get pods -A'
```

## Environment Variables

```bash
# Set default namespace
export NAMESPACE=default

# Use in commands
kubectl get pods -n $NAMESPACE

# Set kubeconfig
export KUBECONFIG=~/.kube/config

# ArgoCD server
export ARGOCD_SERVER=argocd.yourdomain.com

# Use in argocd commands
argocd login $ARGOCD_SERVER
```

## Common File Locations

### k3s Node

```
/etc/rancher/k3s/k3s.yaml          # Kubeconfig
/var/lib/rancher/k3s/              # k3s data
/var/lib/rancher/k3s/agent/        # Agent data
/var/log/pods/                     # Pod logs
/mnt/samba-share/                  # Samba file share storage
```

### Repository Structure

```
k8s-infra/
├── .github/workflows/              # CI/CD workflows
├── apps/                           # Application manifests
├── infrastructure/                 # Infrastructure manifests
├── argocd/applications/            # ArgoCD Application definitions
├── scripts/                        # Helper scripts
└── docs/                           # Documentation
```

## Quick Deployment

```bash
# Deploy infrastructure
kubectl apply -k infrastructure/rbac/
kubectl apply -k infrastructure/ingress-nginx/
kubectl apply -k infrastructure/argocd/

# Deploy application via kustomize
kubectl apply -k apps/<app-name>/base/

# Deploy ArgoCD application
kubectl apply -f argocd/applications/<app-name>.yaml

# Deploy via GitHub Actions
# Push to main branch or manually trigger workflow
```

## Summary

**Most Common Commands:**

```bash
# Check cluster
kubectl get nodes
kubectl get pods -A

# Check specific app
kubectl get all -n <namespace>
kubectl logs -n <namespace> deployment/<name> -f

# ArgoCD
argocd app list
argocd app get <app-name>
argocd app sync <app-name>

# Troubleshoot
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

For detailed troubleshooting, see [Troubleshooting Guide](troubleshooting.md).
