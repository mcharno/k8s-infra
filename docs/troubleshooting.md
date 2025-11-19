# Troubleshooting Guide

Comprehensive troubleshooting guide for common issues and their solutions.

## Table of Contents

- [Kubernetes Cluster Issues](#kubernetes-cluster-issues)
- [Pod & Deployment Issues](#pod--deployment-issues)
- [Network & Connectivity Issues](#network--connectivity-issues)
- [ArgoCD Issues](#argocd-issues)
- [GitHub Actions Issues](#github-actions-issues)
- [Samba File Share Issues](#samba-file-share-issues)
- [Storage Issues](#storage-issues)
- [Performance Issues](#performance-issues)
- [Diagnostic Tools & Commands](#diagnostic-tools--commands)

## Kubernetes Cluster Issues

### Node Not Ready

**Problem:** Node shows `NotReady` status

```bash
kubectl get nodes
# NAME     STATUS     ROLES                  AGE   VERSION
# node1    NotReady   control-plane,master   5d    v1.28.0+k3s1
```

**Diagnosis:**
```bash
# Check node details
kubectl describe node <node-name>

# Check k3s status (on node)
sudo systemctl status k3s

# Check k3s logs
sudo journalctl -u k3s -f
```

**Common Causes & Solutions:**

1. **k3s service stopped:**
   ```bash
   sudo systemctl start k3s
   sudo systemctl enable k3s
   ```

2. **Disk space full:**
   ```bash
   df -h
   # Clean up space
   sudo k3s crictl rmi --prune  # Remove unused images
   ```

3. **Network issues:**
   ```bash
   # Check network interfaces
   ip addr show

   # Check firewall
   sudo ufw status
   ```

4. **Resource exhaustion:**
   ```bash
   # Check memory
   free -h

   # Check CPU
   top
   ```

### Cluster Connectivity Issues

**Problem:** Can't connect to cluster with kubectl

**Diagnosis:**
```bash
# Test connection
kubectl cluster-info

# Check kubeconfig
echo $KUBECONFIG
cat ~/.kube/config

# Test API server
curl -k https://<node-ip>:6443
```

**Solutions:**

1. **Kubeconfig not set:**
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   # Or copy to standard location
   mkdir -p ~/.kube
   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
   sudo chown $(id -u):$(id -g) ~/.kube/config
   ```

2. **API server not accessible:**
   ```bash
   # Check k3s is running
   sudo systemctl status k3s

   # Check firewall allows port 6443
   sudo ufw allow 6443/tcp
   ```

3. **Certificate issues:**
   ```bash
   # Regenerate kubeconfig
   sudo k3s kubectl config view --raw > ~/.kube/config
   ```

## Pod & Deployment Issues

### Pod Stuck in Pending

**Problem:** Pod remains in `Pending` state

```bash
kubectl get pods -n <namespace>
# NAME                    READY   STATUS    RESTARTS   AGE
# my-app-xxx              0/1     Pending   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for Events section
```

**Common Causes & Solutions:**

1. **Insufficient resources:**
   ```
   Event: 0/1 nodes are available: 1 Insufficient cpu.
   ```

   **Solution:**
   ```bash
   # Reduce resource requests
   kubectl edit deployment <deployment-name> -n <namespace>
   # Lower CPU/memory requests

   # Or scale down other deployments
   kubectl scale deployment <other-deployment> --replicas=0
   ```

2. **PVC not bound:**
   ```
   Event: pod has unbound immediate PersistentVolumeClaims
   ```

   **Solution:**
   ```bash
   # Check PVC status
   kubectl get pvc -n <namespace>

   # Check PV availability
   kubectl get pv

   # If using hostPath, ensure path exists
   ls -la /path/to/hostpath
   ```

3. **Node selector mismatch:**
   ```
   Event: 0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector
   ```

   **Solution:**
   ```bash
   # Check pod node selector
   kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 nodeSelector

   # Check node labels
   kubectl get nodes --show-labels

   # Remove or update node selector
   kubectl edit deployment <deployment-name> -n <namespace>
   ```

### Pod Stuck in ContainerCreating

**Problem:** Pod stuck in `ContainerCreating`

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep <pod-name>
```

**Common Causes & Solutions:**

1. **Image pull errors:**
   ```
   Event: Failed to pull image "ghcr.io/user/app:tag": rpc error: code = Unknown
   ```

   **Solution:**
   ```bash
   # Check image exists
   docker pull ghcr.io/user/app:tag

   # Check imagePullSecrets
   kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep imagePullSecrets

   # Recreate pull secret
   ./scripts/argocd/setup-ghcr-secret.sh
   ```

2. **Volume mount issues:**
   ```
   Event: Unable to attach or mount volumes
   ```

   **Solution:**
   ```bash
   # Check PVC status
   kubectl get pvc -n <namespace>

   # Check volume permissions (hostPath)
   ls -la /path/to/volume
   sudo chown -R <uid>:<gid> /path/to/volume
   ```

3. **ConfigMap/Secret not found:**
   ```
   Event: configmap "my-config" not found
   ```

   **Solution:**
   ```bash
   # List configmaps
   kubectl get configmaps -n <namespace>

   # Create missing resource
   kubectl apply -f <manifest.yaml>
   ```

### Pod CrashLoopBackOff

**Problem:** Pod keeps restarting

```bash
kubectl get pods -n <namespace>
# NAME                    READY   STATUS             RESTARTS   AGE
# my-app-xxx              0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>

# Check previous logs (after crash)
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod
kubectl describe pod <pod-name> -n <namespace>
```

**Common Causes & Solutions:**

1. **Application error:**
   - Check logs for error messages
   - Fix application code
   - Verify environment variables
   - Check required secrets/configmaps exist

2. **Health check failures:**
   ```bash
   # Check liveness/readiness probes
   kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 10 livenessProbe

   # Temporarily disable or adjust probes
   kubectl edit deployment <deployment-name> -n <namespace>
   ```

3. **Insufficient resources:**
   ```bash
   # Check events for OOMKilled
   kubectl describe pod <pod-name> -n <namespace> | grep -i oom

   # Increase memory limits
   kubectl edit deployment <deployment-name> -n <namespace>
   ```

### Image Pull Errors

**Problem:** Can't pull container image

```
Error: ErrImagePull
Error: ImagePullBackOff
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for "Failed to pull image" events
```

**Solutions:**

1. **Image doesn't exist:**
   ```bash
   # Verify image exists
   docker pull <image>

   # Check image tag in deployment
   kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep image:
   ```

2. **Private registry auth:**
   ```bash
   # Check imagePullSecrets exists
   kubectl get secret ghcr-secret -n <namespace>

   # Recreate if missing
   kubectl create secret docker-registry ghcr-secret \
     --docker-server=ghcr.io \
     --docker-username=<username> \
     --docker-password=<token> \
     --namespace=<namespace>

   # Update deployment to use secret
   kubectl edit deployment <deployment-name> -n <namespace>
   # Add under spec.template.spec:
   #   imagePullSecrets:
   #     - name: ghcr-secret
   ```

3. **Rate limiting:**
   ```
   Error: toomanyrequests: You have reached your pull rate limit
   ```

   **Solution:**
   - Wait for rate limit to reset
   - Use authenticated pulls (add imagePullSecret)
   - Use different registry (GHCR instead of Docker Hub)

## Network & Connectivity Issues

### Service Not Accessible

**Problem:** Can't access service via ClusterIP/NodePort/LoadBalancer

**Diagnosis:**
```bash
# Check service exists
kubectl get svc <service-name> -n <namespace>

# Check endpoints (should have IPs)
kubectl get endpoints <service-name> -n <namespace>

# Check pods are running
kubectl get pods -n <namespace> -l <selector>
```

**Solutions:**

1. **No endpoints (no pods match selector):**
   ```bash
   # Check service selector
   kubectl get svc <service-name> -n <namespace> -o yaml | grep -A 5 selector

   # Check pod labels
   kubectl get pods -n <namespace> --show-labels

   # Fix selector mismatch
   kubectl edit svc <service-name> -n <namespace>
   ```

2. **Pods not ready:**
   ```bash
   # Check pod status
   kubectl get pods -n <namespace>

   # Fix pod issues (see Pod Issues section)
   ```

3. **Firewall blocking:**
   ```bash
   # For NodePort services
   sudo ufw status
   sudo ufw allow <nodeport>/tcp
   ```

### Ingress Not Working

**Problem:** Can't access application via ingress hostname

**Diagnosis:**
```bash
# Check ingress exists
kubectl get ingress -n <namespace>

# Describe ingress
kubectl describe ingress <ingress-name> -n <namespace>

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

**Solutions:**

1. **DNS not resolving:**
   ```bash
   # Test DNS
   nslookup <hostname>

   # Add to /etc/hosts for testing
   sudo echo "<node-ip> <hostname>" >> /etc/hosts
   ```

2. **Ingress controller not running:**
   ```bash
   # Check ingress-nginx pods
   kubectl get pods -n ingress-nginx

   # Redeploy if needed
   kubectl apply -k infrastructure/ingress-nginx/
   ```

3. **Backend service not ready:**
   ```bash
   # Check ingress backend
   kubectl describe ingress <ingress-name> -n <namespace>

   # Verify service exists
   kubectl get svc <backend-service> -n <namespace>
   ```

4. **Certificate issues:**
   ```bash
   # Check cert-manager
   kubectl get certificates -n <namespace>
   kubectl describe certificate <cert-name> -n <namespace>

   # Check cert-manager logs
   kubectl logs -n cert-manager deployment/cert-manager
   ```

### DNS Resolution Issues

**Problem:** Pods can't resolve service names

**Diagnosis:**
```bash
# Test DNS from a pod
kubectl run test-dns --rm -it --image=busybox -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Solutions:**

1. **CoreDNS not running:**
   ```bash
   # Check CoreDNS pods
   kubectl get pods -n kube-system -l k8s-app=kube-dns

   # Restart CoreDNS
   kubectl rollout restart deployment/coredns -n kube-system
   ```

2. **DNS config issues:**
   ```bash
   # Check pod DNS config
   kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 dnsPolicy

   # Check cluster DNS service
   kubectl get svc -n kube-system kube-dns
   ```

## ArgoCD Issues

### Application OutOfSync

**Problem:** ArgoCD shows application as OutOfSync

**Diagnosis:**
```bash
# Check application status
argocd app get <app-name>

# View differences
argocd app diff <app-name>

# Check via kubectl
kubectl get application <app-name> -n argocd -o yaml
```

**Solutions:**

1. **Manual changes in cluster:**
   ```bash
   # If selfHeal is disabled, manual changes cause drift
   # Sync to restore Git state
   argocd app sync <app-name>

   # Or enable selfHeal
   kubectl patch application <app-name> -n argocd --type merge \
     -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
   ```

2. **Git changes not detected:**
   ```bash
   # Force refresh
   argocd app get <app-name> --refresh

   # Check ArgoCD repo-server logs
   kubectl logs -n argocd deployment/argocd-repo-server
   ```

3. **Ignored differences:**
   ```bash
   # Check ignoreDifferences in application spec
   kubectl get application <app-name> -n argocd -o yaml | grep -A 10 ignoreDifferences

   # May be intentionally ignored (e.g., replicas with HPA)
   ```

### Application Degraded

**Problem:** ArgoCD shows application as Degraded (unhealthy)

**Diagnosis:**
```bash
# Check application health
argocd app get <app-name>

# Check pod status
kubectl get pods -n <namespace>

# Check application events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**Solutions:**

1. **Pod not ready:**
   - See [Pod & Deployment Issues](#pod--deployment-issues)

2. **Service issues:**
   - Check endpoints: `kubectl get endpoints -n <namespace>`
   - Verify pods match service selector

3. **Health check misconfiguration:**
   ```bash
   # Check custom health checks
   kubectl get configmap argocd-cm -n argocd -o yaml | grep health
   ```

### Sync Failures

**Problem:** ArgoCD sync operation fails

**Diagnosis:**
```bash
# Check sync status
argocd app get <app-name>

# View application controller logs
kubectl logs -n argocd deployment/argocd-application-controller
```

**Solutions:**

1. **Invalid manifests:**
   ```bash
   # Validate locally
   kubectl apply --dry-run=client -f <manifest.yaml>

   # Check kustomization
   kubectl kustomize <path> | kubectl apply --dry-run=client -f -
   ```

2. **CRD not installed:**
   ```
   Error: no matches for kind "Certificate" in version "cert-manager.io/v1"
   ```

   **Solution:**
   ```bash
   # Install missing CRDs
   kubectl apply -f <crd-manifest.yaml>
   ```

3. **RBAC permissions:**
   ```bash
   # Check ArgoCD service account permissions
   kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller -n <namespace>
   ```

### Repository Connection Issues

**Problem:** ArgoCD can't connect to Git repository

**Diagnosis:**
```bash
# Check repository status
argocd repo list

# Check repo-server logs
kubectl logs -n argocd deployment/argocd-repo-server
```

**Solutions:**

1. **Private repository without credentials:**
   ```bash
   # Add repository with credentials
   argocd repo add <repo-url> --username <username> --password <password>

   # Or via SSH
   argocd repo add <repo-url> --ssh-private-key-path <path>
   ```

2. **Network connectivity:**
   ```bash
   # Test from ArgoCD pod
   kubectl exec -n argocd deployment/argocd-repo-server -- curl -v <repo-url>
   ```

3. **Certificate verification:**
   ```bash
   # For self-signed certificates
   argocd repo add <repo-url> --insecure-skip-server-verification
   ```

## GitHub Actions Issues

### Workflow Not Triggering

**Problem:** GitHub Actions workflow doesn't run on push

**Diagnosis:**
- Check workflow file syntax
- Verify trigger conditions
- Check GitHub Actions tab for errors

**Solutions:**

1. **Path filters don't match:**
   ```yaml
   # In workflow file
   on:
     push:
       paths:
         - 'infrastructure/**'  # Only triggers if these paths change
   ```

2. **Branch filters don't match:**
   ```yaml
   on:
     push:
       branches:
         - main  # Only triggers on main branch
   ```

3. **Workflow syntax error:**
   - Check workflow in GitHub Actions tab
   - Validate YAML syntax
   - Test locally with `act` tool

### Authentication Failures

**Problem:** Workflow fails with authentication errors

**Diagnosis:**
```
Error: The server could not find the requested resource
Error: Unauthorized
```

**Solutions:**

1. **KUBECONFIG secret not set:**
   ```bash
   # Generate kubeconfig
   ./scripts/setup-github-actions.sh

   # Add to GitHub repo secrets
   # Settings → Secrets → Actions → New repository secret
   # Name: KUBECONFIG
   # Value: <base64-encoded kubeconfig>
   ```

2. **Service account token expired:**
   ```bash
   # Regenerate token
   kubectl create token github-actions-deployer -n github-actions --duration=87600h

   # Update kubeconfig in GitHub secrets
   ```

3. **GITHUB_TOKEN permission issues:**
   ```yaml
   # In workflow file
   permissions:
     contents: write  # For pushing manifest changes
     packages: write  # For pushing to GHCR
   ```

### Deployment Failures

**Problem:** Workflow runs but deployment fails

**Diagnosis:**
- Check workflow logs in GitHub Actions tab
- Look for kubectl errors
- Verify manifest validity

**Solutions:**

1. **Invalid manifests:**
   ```bash
   # Test locally
   kubectl apply --dry-run=client -k <path>
   ```

2. **Insufficient permissions:**
   ```bash
   # Check service account permissions
   kubectl auth can-i create deployments --as=system:serviceaccount:github-actions:github-actions-deployer -n <namespace>

   # Update RBAC if needed
   kubectl edit clusterrole github-actions-deployer
   ```

3. **Resource conflicts:**
   ```bash
   # Check for existing resources
   kubectl get all -n <namespace>

   # Delete conflicting resources if safe
   kubectl delete deployment <name> -n <namespace>
   ```

## Samba File Share Issues

### Can't Connect to Share

**Problem:** Clients can't connect to `\\<node-ip>\share`

**Diagnosis:**
```bash
# Check Samba pod
kubectl get pods -n samba

# Check service
kubectl get svc -n samba

# Test port connectivity
telnet <node-ip> 30445
```

**Solutions:**

1. **Samba pod not running:**
   ```bash
   # Check pod status
   kubectl get pods -n samba
   kubectl logs -n samba deployment/samba

   # Restart if needed
   kubectl rollout restart deployment/samba -n samba
   ```

2. **Firewall blocking:**
   ```bash
   # Allow Samba ports
   sudo ufw allow 30445/tcp
   sudo ufw allow 30137:30139/tcp
   sudo ufw allow 30137:30138/udp
   ```

3. **Service not exposed:**
   ```bash
   # Check NodePort service
   kubectl get svc samba -n samba

   # Should show NodePort 30445
   ```

### Authentication Failures

**Problem:** "Access Denied" or wrong username/password

**Diagnosis:**
```bash
# Check secret
kubectl get secret samba-credentials -n samba -o yaml

# Decode username
kubectl get secret samba-credentials -n samba -o jsonpath='{.data.username}' | base64 -d

# Check pod logs
kubectl logs -n samba deployment/samba
```

**Solutions:**

1. **Wrong credentials:**
   ```bash
   # Update secret
   kubectl edit secret samba-credentials -n samba

   # Restart Samba
   kubectl rollout restart deployment/samba -n samba
   ```

2. **User not created:**
   ```bash
   # Check Samba logs for user creation
   kubectl logs -n samba deployment/samba | grep USER
   ```

### Permission Denied on Files

**Problem:** Can connect but can't read/write files

**Diagnosis:**
```bash
# Check volume mount permissions
kubectl exec -n samba deployment/samba -- ls -la /storage

# On host, check hostPath permissions
ls -la /mnt/samba-share
```

**Solutions:**

1. **Incorrect permissions:**
   ```bash
   # On k3s node
   sudo chown -R 1000:1000 /mnt/samba-share
   sudo chmod 755 /mnt/samba-share
   ```

2. **UID/GID mismatch:**
   ```bash
   # Update secret with correct UID/GID
   kubectl edit secret samba-credentials -n samba
   # Update userid and groupid

   # Restart Samba
   kubectl rollout restart deployment/samba -n samba
   ```

## Storage Issues

### PVC Not Binding

**Problem:** PersistentVolumeClaim stuck in `Pending`

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n <namespace>

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check available PVs
kubectl get pv
```

**Solutions:**

1. **No matching PV available:**
   ```bash
   # Create PV
   kubectl apply -f <pv-manifest.yaml>
   ```

2. **Storage class mismatch:**
   ```bash
   # Check PVC storage class
   kubectl get pvc <pvc-name> -n <namespace> -o yaml | grep storageClassName

   # Check available storage classes
   kubectl get storageclass

   # Update PVC storage class
   kubectl edit pvc <pvc-name> -n <namespace>
   ```

3. **hostPath doesn't exist:**
   ```bash
   # Create directory on host
   sudo mkdir -p /path/to/hostpath
   sudo chown <uid>:<gid> /path/to/hostpath
   ```

### Disk Space Full

**Problem:** Node runs out of disk space

**Diagnosis:**
```bash
# Check disk usage
df -h

# Check large directories
du -sh /var/lib/rancher/*
du -sh /mnt/*
```

**Solutions:**

1. **Clean up images:**
   ```bash
   # Remove unused images
   sudo k3s crictl rmi --prune

   # Remove specific image
   sudo k3s crictl rmi <image-id>
   ```

2. **Clean up volumes:**
   ```bash
   # List volumes
   sudo ls -la /var/lib/rancher/k3s/storage/

   # Remove unused (be careful!)
   # Only remove if you're sure they're not in use
   ```

3. **Rotate logs:**
   ```bash
   # Configure log rotation
   sudo systemctl edit k3s
   # Add: Environment="K3S_LOG_FILE=/var/log/k3s.log"

   # Manually clean old logs
   sudo journalctl --vacuum-time=7d
   ```

## Performance Issues

### High CPU Usage

**Diagnosis:**
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -A

# On node
top
htop
```

**Solutions:**

1. **Resource limits too high:**
   ```bash
   # Reduce limits
   kubectl edit deployment <deployment-name> -n <namespace>
   # Adjust resources.limits.cpu
   ```

2. **Too many replicas:**
   ```bash
   # Scale down
   kubectl scale deployment <deployment-name> -n <namespace> --replicas=1
   ```

3. **Specific pod using too much:**
   ```bash
   # Identify culprit
   kubectl top pods -A | sort -k 3 -r

   # Investigate and fix application
   ```

### High Memory Usage

**Diagnosis:**
```bash
# Check memory usage
kubectl top nodes
kubectl top pods -A

# Check for OOMKilled events
kubectl get events -A | grep OOMKilled
```

**Solutions:**

1. **Increase memory limits:**
   ```bash
   kubectl edit deployment <deployment-name> -n <namespace>
   # Increase resources.limits.memory
   ```

2. **Memory leak in application:**
   - Check application logs
   - Profile application
   - Fix memory leaks in code

3. **Too many pods:**
   ```bash
   # Scale down non-critical apps
   kubectl scale deployment <deployment-name> -n <namespace> --replicas=0
   ```

## Diagnostic Tools & Commands

### kubectl Commands

```bash
# Comprehensive pod diagnostics
kubectl get pod <pod-name> -n <namespace> -o yaml
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Resource usage
kubectl top nodes
kubectl top pods -A

# Events
kubectl get events -A --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>

# Cluster info
kubectl cluster-info
kubectl get componentstatuses
kubectl api-resources
```

### k3s Specific

```bash
# On k3s node
sudo systemctl status k3s
sudo journalctl -u k3s -f
sudo k3s kubectl get nodes

# Container runtime
sudo k3s crictl ps
sudo k3s crictl images
sudo k3s crictl logs <container-id>

# Network
sudo k3s kubectl get pods -n kube-system
```

### ArgoCD Diagnostics

```bash
# Application diagnostics
argocd app get <app-name>
argocd app diff <app-name>
argocd app logs <app-name>
argocd app resources <app-name>

# Component logs
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-repo-server

# Database check
kubectl exec -n argocd deployment/argocd-server -- argocd-util app list
```

### Network Diagnostics

```bash
# DNS testing
kubectl run test-dns --rm -it --image=busybox -- nslookup kubernetes.default

# Network connectivity
kubectl run test-net --rm -it --image=nicolaka/netshoot -- bash
# Then use: curl, wget, nc, traceroute, etc.

# Test specific service
kubectl run test-svc --rm -it --image=busybox -- wget -O- http://<service>.<namespace>.svc.cluster.local:<port>
```

## Getting Help

### Where to Look

1. **Pod logs**: `kubectl logs <pod-name> -n <namespace>`
2. **Events**: `kubectl get events -n <namespace>`
3. **Describe resource**: `kubectl describe <resource> <name> -n <namespace>`
4. **Component logs**: Check ArgoCD, ingress-nginx, cert-manager logs
5. **k3s logs**: `sudo journalctl -u k3s -f`

### Escalation Path

1. Check this troubleshooting guide
2. Review [Quick Reference](quick-reference.md) for commands
3. Check component-specific documentation
4. Review upstream documentation:
   - [Kubernetes](https://kubernetes.io/docs/tasks/debug/)
   - [k3s](https://docs.k3s.io/troubleshooting)
   - [ArgoCD](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)

### Collecting Debug Info

For reporting issues, collect:

```bash
# Cluster info
kubectl cluster-info dump > cluster-info.txt

# Node info
kubectl get nodes -o yaml > nodes.yaml
kubectl describe nodes > nodes-describe.txt

# Pod info
kubectl get pods -A -o yaml > pods.yaml
kubectl describe pods -A > pods-describe.txt

# Events
kubectl get events -A --sort-by='.lastTimestamp' > events.txt

# Logs
kubectl logs -n <namespace> deployment/<name> > app.log
```

## Summary

**Most Common Issues:**
1. Pod not starting → Check events and logs
2. Service not accessible → Check endpoints and ingress
3. ArgoCD OutOfSync → Sync application or enable selfHeal
4. GitHub Actions failing → Check KUBECONFIG secret and permissions
5. Samba connection issues → Check firewall and credentials
6. Disk space → Clean up images and logs

**Quick Diagnostic Flow:**
```
Issue reported
    ↓
Check pod status (kubectl get pods)
    ↓
Describe pod (kubectl describe pod)
    ↓
Check logs (kubectl logs)
    ↓
Check events (kubectl get events)
    ↓
Fix root cause
    ↓
Verify fix
```

For detailed information on any component, see the respective documentation in the [docs](README.md) directory.
