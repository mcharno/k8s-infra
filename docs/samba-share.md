# Samba File Share

Single-pod Samba server for LAN file sharing, backed by hostPath storage and exposed via NodePort.

## Features

- ✅ Single-pod deployment for low resource usage
- ✅ hostPath storage (data persists on the k3s node)
- ✅ NodePort service for LAN accessibility
- ✅ Minimal CPU/RAM footprint (128Mi-512Mi RAM, 100m-500m CPU)
- ✅ Standard SMB/CIFS protocol (compatible with Windows, macOS, Linux)
- ✅ LAN-only access (not exposed to internet)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 LAN Clients                          │
│  (Windows, macOS, Linux, Mobile)                    │
└──────────────┬──────────────────────────────────────┘
               │ SMB/CIFS Protocol
               │ Port 445 (TCP) + NetBIOS ports
               ▼
┌─────────────────────────────────────────────────────┐
│             k3s Node (NodePort)                      │
│  NodePort 30445 (SMB/CIFS)                          │
│  NodePort 30137-30139 (NetBIOS)                     │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│         Samba Pod (namespace: samba)                 │
│  ┌─────────────────────────────────────────────┐    │
│  │  dperson/samba container                    │    │
│  │  Resources: 128Mi-512Mi RAM, 100m-500m CPU  │    │
│  └────────────┬────────────────────────────────┘    │
└───────────────┼─────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────┐
│      hostPath: /mnt/samba-share                      │
│      (PersistentVolume on k3s node)                  │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- k3s cluster running
- kubectl configured
- Sufficient disk space on k3s node at `/mnt/samba-share`

## Installation

### Step 1: Update Credentials

**IMPORTANT:** Change the default credentials before deploying!

Edit `base/secret.yaml`:

```bash
vim apps/samba/base/secret.yaml
```

Update these values:
```yaml
stringData:
  username: "your-username"      # Change this
  password: "YourSecurePass123"  # Change this (min 8 chars)
  userid: "1000"                 # Match your host user if needed
  groupid: "1000"                # Match your host group if needed
```

### Step 2: (Optional) Adjust Storage Size

Edit `base/persistentvolume.yaml` and `base/persistentvolumeclaim.yaml`:

```yaml
spec:
  capacity:
    storage: 100Gi  # Change to your desired size
```

### Step 3: (Optional) Customize Storage Path

By default, data is stored at `/mnt/samba-share` on the k3s host node.

To change this, edit `base/persistentvolume.yaml`:

```yaml
spec:
  hostPath:
    path: /mnt/samba-share  # Change to your desired path
```

### Step 4: Deploy

```bash
# Deploy using kustomize
kubectl apply -k apps/samba/base/

# Or use GitHub Actions workflow (if set up)
# Push changes to main branch
```

### Step 5: Verify Deployment

```bash
# Check pod status
kubectl get pods -n samba

# Check service
kubectl get svc -n samba

# View logs
kubectl logs -n samba deployment/samba

# Check storage
kubectl get pv,pvc -n samba
```

Expected output:
```
NAME        READY   STATUS    RESTARTS   AGE
pod/samba   1/1     Running   0          1m
```

## Accessing the Share

### Get the k3s Node IP

```bash
# Get your k3s node IP (LAN IP)
kubectl get nodes -o wide

# Or on the k3s node itself
hostname -I | awk '{print $1}'
```

### Connection Details

- **Server:** `<k3s-node-ip>` or `<hostname>`
- **Port:** `30445` (or just use default 445 if available)
- **Share Name:** `share`
- **Username:** (from your secret.yaml)
- **Password:** (from your secret.yaml)

### Windows

#### Method 1: File Explorer

1. Open File Explorer
2. In the address bar, type:
   ```
   \\<k3s-node-ip>\share
   ```
   or if using custom port:
   ```
   \\<k3s-node-ip>:30445\share
   ```

3. Enter credentials when prompted

#### Method 2: Map Network Drive

1. Right-click "This PC" → "Map network drive"
2. Choose drive letter (e.g., Z:)
3. Folder: `\\<k3s-node-ip>\share`
4. Check "Connect using different credentials"
5. Click Finish and enter username/password

#### Method 3: Command Line

```cmd
net use Z: \\<k3s-node-ip>\share /user:<username> <password>
```

### macOS

#### Finder

1. Open Finder
2. Press `Cmd + K` (or Go → Connect to Server)
3. Enter:
   ```
   smb://<k3s-node-ip>/share
   ```
4. Click Connect
5. Enter username and password

#### Command Line

```bash
# Create mount point
mkdir -p ~/mnt/samba-share

# Mount the share
mount_smbfs //<username>:<password>@<k3s-node-ip>/share ~/mnt/samba-share
```

### Linux

#### Using File Manager

**Ubuntu/GNOME:**
1. Open Files (Nautilus)
2. Click "Other Locations"
3. In "Connect to Server" field, enter:
   ```
   smb://<k3s-node-ip>/share
   ```
4. Enter credentials

**KDE:**
1. Open Dolphin
2. Type in location bar:
   ```
   smb://<k3s-node-ip>/share
   ```

#### Command Line (CIFS)

```bash
# Install cifs-utils (if not installed)
sudo apt-get install cifs-utils  # Debian/Ubuntu
sudo dnf install cifs-utils      # Fedora
sudo pacman -S cifs-utils        # Arch

# Create mount point
sudo mkdir -p /mnt/samba-share

# Mount the share
sudo mount -t cifs //<k3s-node-ip>/share /mnt/samba-share \
  -o username=<username>,password=<password>,uid=$(id -u),gid=$(id -g)
```

#### Permanent Mount (fstab)

Create credentials file:
```bash
sudo vim /etc/samba/credentials
```

Add:
```
username=your-username
password=your-password
```

Secure it:
```bash
sudo chmod 600 /etc/samba/credentials
```

Add to `/etc/fstab`:
```
//<k3s-node-ip>/share  /mnt/samba-share  cifs  credentials=/etc/samba/credentials,uid=1000,gid=1000,iocharset=utf8  0  0
```

Mount:
```bash
sudo mount -a
```

### Mobile Devices

#### Android

1. Install a file manager that supports SMB (e.g., "Solid Explorer", "FX File Explorer")
2. Add network storage
3. Choose SMB/CIFS
4. Enter server IP, share name, username, password

#### iOS

1. Open Files app
2. Tap "..." → "Connect to Server"
3. Enter:
   ```
   smb://<k3s-node-ip>/share
   ```
4. Enter credentials

## Configuration

### Changing Credentials

```bash
# Edit the secret
kubectl edit secret samba-credentials -n samba

# Or update the file and reapply
vim apps/samba/base/secret.yaml
kubectl apply -k apps/samba/base/

# Restart the pod to apply changes
kubectl rollout restart deployment/samba -n samba
```

### Adjusting Resource Limits

Edit `base/deployment.yaml`:

```yaml
resources:
  requests:
    memory: "128Mi"  # Minimum RAM
    cpu: "100m"      # Minimum CPU
  limits:
    memory: "512Mi"  # Maximum RAM
    cpu: "500m"      # Maximum CPU
```

### Share Permissions

The share is configured as read-write for authenticated users. To modify, edit the `SHARE` environment variable in `base/deployment.yaml`:

```yaml
- name: SHARE
  # Format: name;path;browse;readonly;guest;users;admins;writelist;comment
  value: "share;/storage;yes;no;no;all;none;all;Shared Storage"
```

Parameters:
- `browse`: yes/no - visible in network browsing
- `readonly`: yes/no - read-only share
- `guest`: yes/no - allow guest access (not recommended)
- `users`: all/username - who can access
- `admins`: none/username - admin users
- `writelist`: all/username - who can write

## Monitoring

### Check Logs

```bash
# Follow logs
kubectl logs -f -n samba deployment/samba

# View recent logs
kubectl logs --tail=100 -n samba deployment/samba
```

### Check Resource Usage

```bash
kubectl top pod -n samba
```

### Check Storage Usage

```bash
# On the k3s node
du -sh /mnt/samba-share

# From within the pod
kubectl exec -n samba deployment/samba -- df -h /storage
```

## Troubleshooting

### Cannot Connect to Share

1. **Check pod is running:**
   ```bash
   kubectl get pods -n samba
   ```

2. **Check service and NodePort:**
   ```bash
   kubectl get svc -n samba
   ```

3. **Verify firewall allows SMB ports:**
   ```bash
   # On k3s node
   sudo ufw status
   # Allow if needed:
   sudo ufw allow 30445/tcp
   sudo ufw allow 30137:30139/tcp
   sudo ufw allow 30137:30138/udp
   ```

4. **Test connectivity:**
   ```bash
   # From client machine
   telnet <k3s-node-ip> 30445
   ```

### Permission Denied

1. **Check credentials are correct**

2. **Verify user/group IDs match:**
   ```bash
   # On k3s node, check ownership of /mnt/samba-share
   ls -ld /mnt/samba-share

   # Should match userid/groupid in secret (default 1000)
   ```

3. **Check share configuration:**
   ```bash
   kubectl logs -n samba deployment/samba | grep -i share
   ```

### Pod Won't Start

1. **Check pod events:**
   ```bash
   kubectl describe pod -n samba
   ```

2. **Check PV/PVC binding:**
   ```bash
   kubectl get pv,pvc -n samba
   ```

3. **Verify hostPath directory exists:**
   ```bash
   # On k3s node
   ls -ld /mnt/samba-share
   ```

### Performance Issues

1. **Check resource limits:**
   ```bash
   kubectl top pod -n samba
   ```

2. **Increase resources if needed** (edit deployment.yaml)

3. **Check network latency:**
   ```bash
   ping <k3s-node-ip>
   ```

## Security Considerations

### LAN-Only Access

- ✅ Service is NodePort (not LoadBalancer/Ingress)
- ✅ Only accessible within LAN
- ✅ Ensure k3s node is behind firewall
- ❌ **DO NOT expose port 30445 to the internet**

### Credentials

- ✅ Change default credentials immediately
- ✅ Use strong passwords (min 12+ characters)
- ✅ Credentials stored as Kubernetes Secret (base64 encoded)
- ⚠️ Consider using Sealed Secrets for Git storage

### Network Security

Recommended firewall rules on k3s node:

```bash
# Allow from LAN only (example: LAN is 192.168.1.0/24)
sudo ufw allow from 192.168.1.0/24 to any port 30445 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 30137:30139

# Or be more restrictive to specific IPs
sudo ufw allow from 192.168.1.50 to any port 30445
```

## Backup

### Manual Backup

```bash
# On k3s node
sudo rsync -av /mnt/samba-share/ /backup/samba-share/
```

### Automated Backup

Create a CronJob or use external backup tools to regularly backup `/mnt/samba-share`.

## Uninstallation

```bash
# Delete all Samba resources
kubectl delete -k apps/samba/base/

# Optionally, remove data (CAUTION: This deletes all files!)
# On k3s node:
sudo rm -rf /mnt/samba-share
```

## Performance Tuning

For better performance on high-traffic shares:

1. **Increase resource limits** in deployment.yaml
2. **Use SSD storage** for /mnt/samba-share
3. **Enable SMB3** (already enabled by default)
4. **Adjust TCP parameters** on k3s node

## Advanced Configuration

### Multiple Shares

Edit the deployment and add additional `SHARE` environment variables:

```yaml
- name: SHARE
  value: "share1;/storage/share1;yes;no;no;all;none;all;Share 1"
- name: SHARE2
  value: "share2;/storage/share2;yes;yes;no;all;none;none;Read-Only Share"
```

### Custom smb.conf

For advanced Samba configuration, you can mount a custom smb.conf via ConfigMap.

## Support

For issues with:
- **Kubernetes deployment:** Check pod logs and events
- **Samba server:** Consult [dperson/samba documentation](https://github.com/dperson/samba)
- **SMB protocol:** Check client-side SMB/CIFS configuration

## References

- [Samba Documentation](https://www.samba.org/samba/docs/)
- [dperson/samba Docker Image](https://github.com/dperson/samba)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [SMB Protocol](https://en.wikipedia.org/wiki/Server_Message_Block)
