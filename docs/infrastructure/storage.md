# Storage Configuration

Local storage provisioning for K3s using the built-in local-path-provisioner.

## Overview

**What is local-path-provisioner?**
- Built-in dynamic storage provisioner that comes with K3s
- Creates directories on the host node for PersistentVolumes
- No external dependencies (no NFS, no Ceph, no cloud providers)
- Perfect for single-node clusters like Raspberry Pi

**Storage Backend:**
- Host path: `/mnt/k3s-storage/local-path-provisioner`
- Backed by dual SSD LVM setup (2.7TB total)
- Each PVC gets a unique subdirectory: `pvc-{uuid}`

## Architecture

```
Application Pod
    ↓
PersistentVolumeClaim (PVC)
    ↓
PersistentVolume (PV) - Auto-created by provisioner
    ↓
Host Directory: /mnt/k3s-storage/local-path-provisioner/pvc-{uuid}
    ↓
LVM Volume: /dev/k3s-storage/data
    ↓
Physical SSDs: /dev/sda (1TB) + /dev/sdb (2TB)
```

## Critical Configuration

### volumeBindingMode: WaitForFirstConsumer

**IMPORTANT:** The StorageClass MUST use `WaitForFirstConsumer` binding mode.

**Why?**
- Single-node cluster: Provisioner needs to know which node will run the pod
- `Immediate` mode fails: PVC stays Pending because no node is selected yet
- `WaitForFirstConsumer`: PV is created only after pod is scheduled to a node

**How it works:**
1. Create PVC → Status: Pending (waiting for consumer)
2. Create Pod that uses PVC → Pod triggers scheduling
3. Scheduler assigns pod to node → Provisioner creates PV on that node
4. PVC binds to PV → Pod starts

**Symptom if misconfigured:**
```bash
kubectl get pvc
# NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# my-pvc     Pending                                      local-path

kubectl describe pvc my-pvc
# Events:
#   Type     Reason              Message
#   ----     ------              -------
#   Normal   WaitForFirstConsumer  waiting for first consumer to be created
```

**Fix:** Ensure StorageClass has `volumeBindingMode: WaitForFirstConsumer`

## Deployment

### Prerequisites

**1. LVM Storage Setup:**
```bash
# Run on the Pi (see scripts/storage/setup-lvm.sh)
sudo bash scripts/storage/setup-lvm.sh
```

This creates:
- Volume group: `k3s-storage`
- Logical volume: `data` (2.7TB)
- Mount point: `/mnt/k3s-storage`
- Auto-mount via `/etc/fstab`

**2. K3s Installed:**
```bash
# K3s comes with local-path-provisioner pre-installed
kubectl get pods -n kube-system -l app=local-path-provisioner
```

### Configuration

The local-path-provisioner is pre-installed with K3s, but you can customize it:

**Option 1: Use K3s Defaults (Recommended)**
```bash
# K3s automatically creates the StorageClass
# Just verify it exists and has correct settings
kubectl get storageclass local-path -o yaml
```

**Option 2: Customize Configuration**
```bash
# Apply custom ConfigMap (changes storage path)
kubectl apply -f infrastructure/storage/local-path-config.yaml

# Restart provisioner to pick up changes
kubectl rollout restart deployment local-path-provisioner -n kube-system
```

**Option 3: Recreate StorageClass**
```bash
# If needed, recreate with correct volumeBindingMode
kubectl delete storageclass local-path
kubectl apply -f infrastructure/storage/storageclass.yaml
```

### Verification

**Check provisioner is running:**
```bash
kubectl get pods -n kube-system -l app=local-path-provisioner
# Should show: Running
```

**Check StorageClass:**
```bash
kubectl get storageclass
# NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
# local-path   rancher.io/local-path   Delete          WaitForFirstConsumer   true
```

**Test with a pod:**
```bash
# Create test PVC + pod
bash infrastructure/storage/test-storage.sh

# Should show: PVC bound, pod running
```

## Testing

**Quick test script:**
```bash
#!/bin/bash
# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Mi
EOF

# Create pod that uses it
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox:1.36
    command: ['sh', '-c', 'echo "Storage works!" > /data/test.txt && cat /data/test.txt && sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: storage-test
EOF

# Wait and check
echo "Waiting 30 seconds for provisioning..."
sleep 30

kubectl get pvc storage-test
kubectl get pod storage-test-pod

# Verify data written
kubectl exec storage-test-pod -- cat /data/test.txt

# Cleanup
kubectl delete pod storage-test-pod
kubectl delete pvc storage-test
```

## Storage Path Structure

**On the host (Pi):**
```
/mnt/k3s-storage/
├── local-path-provisioner/          # Provisioner working directory
│   ├── pvc-abc123.../               # PV for one PVC
│   │   └── (application data)
│   ├── pvc-def456.../               # PV for another PVC
│   │   └── (application data)
│   └── ...
└── data/                            # Optional: Manual data directory
```

**Example:**
```bash
# Check actual storage usage
ssh pi@pibox "ls -lh /mnt/k3s-storage/local-path-provisioner/"

# Output:
# drwxrwxrwx 3 root root 4.0K Nov 25 10:30 pvc-a1b2c3d4-homeassistant
# drwxrwxrwx 3 root root 4.0K Nov 25 11:15 pvc-e5f6g7h8-nextcloud-data
# drwxrwxrwx 3 root root 4.0K Nov 25 11:20 pvc-i9j0k1l2-jellyfin-config
```

## Common Operations

### View all PVCs and PVs

```bash
# All PVCs across namespaces
kubectl get pvc -A

# All PVs
kubectl get pv

# Detailed view
kubectl get pv,pvc -A -o wide
```

### Find which pod uses a PVC

```bash
# List all pods with their volumes
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim) |
  "\(.metadata.namespace)/\(.metadata.name) uses \(.spec.volumes[].persistentVolumeClaim.claimName)"'
```

### Check storage usage

```bash
# On the Pi
ssh pi@pibox "df -h /mnt/k3s-storage"

# Breakdown by PVC
ssh pi@pibox "du -sh /mnt/k3s-storage/local-path-provisioner/*"
```

### Expand a PVC

```bash
# Edit PVC to request more storage
kubectl patch pvc my-pvc -n my-namespace -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'

# Note: Requires allowVolumeExpansion: true in StorageClass (enabled by default)
# May require pod restart to take effect
```

### Delete PVC (and underlying data)

```bash
# Delete PVC
kubectl delete pvc my-pvc -n my-namespace

# This automatically deletes the PV and host directory
# (due to reclaimPolicy: Delete)

# Verify cleanup
ssh pi@pibox "ls /mnt/k3s-storage/local-path-provisioner/"
```

## Troubleshooting

### PVC Stays Pending

**Symptom:**
```bash
kubectl get pvc
# NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# my-pvc   Pending                                      local-path
```

**Cause 1: Waiting for First Consumer**
```bash
kubectl describe pvc my-pvc
# Events:
#   Normal   WaitForFirstConsumer  waiting for first consumer to be created
```

**Solution:** This is NORMAL. Create a pod that uses the PVC:
```yaml
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

**Cause 2: Wrong volumeBindingMode**
```bash
# Check StorageClass
kubectl get storageclass local-path -o yaml | grep volumeBindingMode
# Should show: volumeBindingMode: WaitForFirstConsumer
```

**Solution:** Recreate StorageClass with correct mode:
```bash
kubectl delete storageclass local-path
kubectl apply -f infrastructure/storage/storageclass.yaml
```

**Cause 3: Provisioner not running**
```bash
kubectl get pods -n kube-system -l app=local-path-provisioner
```

**Solution:** Check provisioner logs:
```bash
kubectl logs -n kube-system -l app=local-path-provisioner --tail=50
```

### PV Created But Pod Can't Start

**Symptom:**
```bash
kubectl describe pod my-pod
# Events:
#   Warning  FailedMount  MountVolume.SetUp failed: mkdir /mnt/k3s-storage/...: permission denied
```

**Cause:** Storage path doesn't exist or wrong permissions

**Solution:**
```bash
# On the Pi
ssh pi@pibox

# Check mount
df -h /mnt/k3s-storage
# Should show: ~2.7TB mounted

# Check permissions
ls -la /mnt/k3s-storage/
# Should show: drwxr-xr-x for local-path-provisioner/

# Fix permissions if needed
sudo chmod 755 /mnt/k3s-storage/local-path-provisioner
```

### Storage Path Not Found

**Symptom:**
```bash
kubectl logs -n kube-system -l app=local-path-provisioner
# Error: path /mnt/k3s-storage/local-path-provisioner does not exist
```

**Cause:** LVM volume not mounted

**Solution:**
```bash
# On the Pi
ssh pi@pibox

# Check if mounted
df -h | grep k3s-storage

# If not mounted
sudo mount /mnt/k3s-storage

# Verify fstab entry
grep k3s-storage /etc/fstab
# Should show: /dev/k3s-storage/data /mnt/k3s-storage ext4 defaults,nofail 0 2

# If missing, re-run setup
sudo bash scripts/storage/setup-lvm.sh
```

### Provisioner Logs Show Errors

```bash
# View logs
kubectl logs -n kube-system -l app=local-path-provisioner --tail=100

# Common errors and solutions:

# "node not found"
# → Check node name in ConfigMap matches actual node
kubectl get nodes
kubectl get configmap local-path-config -n kube-system -o yaml

# "permission denied"
# → Check directory permissions on host
ssh pi@pibox "ls -la /mnt/k3s-storage/"

# "no space left"
# → Check disk usage
ssh pi@pibox "df -h /mnt/k3s-storage"
```

### PV Not Deleted After PVC Deletion

**Symptom:**
```bash
kubectl delete pvc my-pvc
# PVC deleted, but PV still exists

kubectl get pv
# NAME        CAPACITY   STATUS     CLAIM
# pv-abc123   1Gi        Released   default/my-pvc
```

**Cause:** PV stuck in Released state

**Solution:**
```bash
# Manually delete PV
kubectl delete pv pv-abc123

# Manually cleanup on host
ssh pi@pibox "sudo rm -rf /mnt/k3s-storage/local-path-provisioner/pvc-abc123*"
```

## Monitoring

**Check provisioner status:**
```bash
kubectl get pods -n kube-system -l app=local-path-provisioner
kubectl logs -n kube-system -l app=local-path-provisioner --tail=20
```

**Storage usage over time:**
```bash
# Script to monitor storage
watch -n 30 'df -h /mnt/k3s-storage && echo "" && kubectl get pvc -A'
```

**Prometheus metrics:**
```bash
# If Prometheus is installed, scrape kubelet metrics
# Includes volume stats for all PVs
```

## Backup & Restore

**Backup PV data:**
```bash
# Option 1: Backup entire LVM volume
ssh pi@pibox "sudo lvdisplay /dev/k3s-storage/data"
# Use LVM snapshot or rsync to backup

# Option 2: Backup per-PVC
ssh pi@pibox "sudo tar czf backup-pvc.tar.gz /mnt/k3s-storage/local-path-provisioner/pvc-{uuid}"
```

**Restore PV data:**
```bash
# 1. Recreate PVC (same name and namespace)
kubectl apply -f pvc.yaml

# 2. Wait for PV to be created
kubectl get pvc my-pvc -w

# 3. Copy backup data to new PV directory
PV_NAME=$(kubectl get pvc my-pvc -o jsonpath='{.spec.volumeName}')
PV_PATH=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.hostPath.path}')

ssh pi@pibox "sudo tar xzf backup-pvc.tar.gz -C $PV_PATH"

# 4. Start application pod
kubectl apply -f pod.yaml
```

## Storage Capacity Planning

**Current setup:**
- Total capacity: 2.7TB (dual SSDs via LVM)
- Raspberry Pi 4: 8GB RAM, 4 cores
- Expected usage: ~500GB for applications

**Recommendations:**
- Monitor usage weekly: `df -h /mnt/k3s-storage`
- Keep 20% free space for optimal performance
- Alert when usage exceeds 80%

**Adding more storage:**
```bash
# Option 1: Add another SSD to LVM
sudo vgextend k3s-storage /dev/sdc1
sudo lvextend -l +100%FREE /dev/k3s-storage/data
sudo resize2fs /dev/k3s-storage/data

# Option 2: Use external NFS for large files
# Configure NFS provisioner for media/backups
```

## Alternative Storage Options

**When to consider alternatives:**
- Need true high availability (multi-node)
- Want automatic replication
- Require shared storage (ReadWriteMany)
- Need snapshots and cloning

**Options:**
1. **Longhorn** - Cloud-native distributed storage
   - Pros: Replication, snapshots, disaster recovery
   - Cons: Requires 3+ nodes, higher resource usage

2. **NFS** - Network File System
   - Pros: Simple, supports ReadWriteMany
   - Cons: Single point of failure, network overhead

3. **Rook/Ceph** - Distributed storage system
   - Pros: Enterprise-grade, highly available
   - Cons: Complex, requires 3+ nodes, high resource usage

**For single-node Pi clusters:** `local-path-provisioner` is the best choice.

## Security Considerations

**Current security:**
- ✅ Storage isolated per namespace
- ✅ Each PVC gets unique directory
- ✅ Automatic cleanup on PVC deletion
- ⚠️  No encryption at rest (data stored as plain files)
- ⚠️  No access control beyond Kubernetes RBAC

**Recommendations:**
1. **Encrypt sensitive data at application level**
   - Use application-level encryption for secrets
   - Example: Nextcloud server-side encryption

2. **Regular backups**
   - Automate daily backups to external location
   - Test restore procedures regularly

3. **Monitor access**
   - Audit PVC creation/deletion
   - Alert on unusual storage usage

4. **Physical security**
   - Secure Pi location (locked cabinet)
   - Full disk encryption on SD card (rootfs)

## Files

- `storageclass.yaml` - StorageClass definition (WaitForFirstConsumer mode)
- `local-path-config.yaml` - ConfigMap for provisioner (optional customization)
- `test-storage.sh` - Test script to verify provisioning works
- `README.md` - This file

## References

- [K3s Storage Documentation](https://docs.k3s.io/storage)
- [local-path-provisioner GitHub](https://github.com/rancher/local-path-provisioner)
- [Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [LVM Administration Guide](https://tldp.org/HOWTO/LVM-HOWTO/)

## Summary

**Key Takeaways:**
- K3s includes local-path-provisioner out of the box
- MUST use `volumeBindingMode: WaitForFirstConsumer`
- PVCs stay Pending until a pod uses them (this is normal!)
- Backed by 2.7TB LVM volume on dual SSDs
- Each PVC gets isolated directory: `/mnt/k3s-storage/local-path-provisioner/pvc-{uuid}`
- Perfect for single-node Raspberry Pi clusters
