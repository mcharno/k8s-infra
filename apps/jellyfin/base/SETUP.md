# Jellyfin Setup Documentation

## Overview

Jellyfin is an open-source media server that allows you to manage and stream your media collection. This deployment runs on K3s on a Raspberry Pi 4 (8GB RAM, 4 cores).

**Current Status:** Production deployment with external and local HTTPS access

## Deployment History

### Version 1: Initial NodePort Deployment (install_jellyfin.sh)

**When:** Initial deployment
**Approach:** NodePort service for direct access

**Configuration:**
```yaml
Service: NodePort
  - HTTP: 30096
  - HTTPS: 30920
  - DLNA: 1900 (UDP)
  - Discovery: 7359 (UDP)

Storage:
  - Config: 20Gi PVC
  - Media: 500Gi PVC
  - Cache: 10Gi PVC

Published URL: http://<PI_IP>:30096
```

**Key Features:**
- Three separate PVCs for config, media, and cache
- Software transcoding only (no GPU acceleration on Pi)
- Direct access via NodePort
- Simple deployment for local network access

**Limitations:**
- No external access without port forwarding
- HTTP only (no HTTPS)
- Manual media file management required

### Version 2: Current Ingress-Based Deployment

**When:** Production deployment with Ingress
**What Changed:** Added HTTPS ingress for both external and local access

**Configuration:**
```yaml
Ingress:
  External:
    - Host: jellyfin.charn.io
    - TLS: Let's Encrypt via Cloudflare
    - Annotations:
      - force-ssl-redirect: "false" (Cloudflare sends HTTP)
      - proxy-body-size: "0" (unlimited for streaming)
      - proxy-buffering: "off" (better streaming)

  Local:
    - Host: jellyfin.local.charn.io
    - TLS: Local wildcard certificate
    - Annotations:
      - force-ssl-redirect: "true" (can force SSL locally)
      - ssl-protocols: "TLSv1.2 TLSv1.3"

Deployment:
  Published URL: https://jellyfin.charn.io
  Health Probes:
    - Startup: 30s delay, 30 failures (5min total)
    - Readiness: 60s delay
    - Liveness: 120s delay

Resources:
  Requests: 500m CPU, 512Mi RAM
  Limits: 2 CPU cores, 2Gi RAM
```

**Why These Changes:**
1. **Hybrid HTTPS Access Pattern:**
   - External: Cloudflare Tunnel → HTTP → Nginx → Jellyfin
   - Local: Direct HTTPS → Nginx → Jellyfin
   - Faster local access, secure external access

2. **Unlimited Body Size:**
   - Streaming can involve large files
   - `proxy-body-size: "0"` removes any upload limits
   - Required for large media file uploads via web UI

3. **Buffering Disabled:**
   - `proxy-buffering: off` and `proxy-request-buffering: off`
   - Reduces latency for streaming
   - Better real-time performance

4. **Health Probes:**
   - Jellyfin can take 2-3 minutes to start
   - Startup probe allows 5 minutes before marking as failed
   - Prevents premature pod restarts

**Benefits:**
- Secure external access via HTTPS
- Fast local access when at home
- Better streaming performance
- Professional setup with automatic certificates

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    External Access                          │
│                                                             │
│  Internet → Cloudflare Tunnel → HTTP → Nginx Ingress       │
│             (jellyfin.charn.io)          ↓                  │
│                                          ↓                  │
│                    Local Access          ↓                  │
│                                          ↓                  │
│  Home Network → HTTPS → Nginx Ingress → Jellyfin Pod       │
│  (jellyfin.local.charn.io)               ↓                  │
│                                          ↓                  │
│                                    ┌─────────────┐          │
│                                    │  Jellyfin   │          │
│                                    │  Container  │          │
│                                    │  :8096      │          │
│                                    └─────────────┘          │
│                                          │                  │
│                     ┌────────────────────┼─────────────┐    │
│                     │                    │             │    │
│                ┌────▼────┐         ┌─────▼──┐    ┌─────▼──┐│
│                │ Config  │         │ Media  │    │ Cache  ││
│                │  PVC    │         │  PVC   │    │  PVC   ││
│                │  20Gi   │         │ 500Gi  │    │  10Gi  ││
│                └─────────┘         └────────┘    └────────┘│
│                                                             │
│          NodePort Backup: http://<PI_IP>:30096             │
└─────────────────────────────────────────────────────────────┘
```

## Storage Configuration

Jellyfin uses three separate PVCs:

### 1. Config PVC (20Gi) - jellyfin-config
- **Mount Point:** `/config`
- **Purpose:** Jellyfin configuration, database, metadata
- **Contents:**
  - User accounts and preferences
  - Library configurations
  - Metadata cache
  - Plugin data
  - Transcoding profiles
- **Backup Priority:** HIGH - Contains all settings and library metadata

### 2. Media PVC (500Gi) - jellyfin-media
- **Mount Point:** `/media`
- **Purpose:** Media files (movies, TV shows, music, photos)
- **Recommended Structure:**
  ```
  /media/
    ├── movies/
    │   ├── Movie Title (Year)/
    │   │   └── Movie Title (Year).mp4
    ├── tv/
    │   ├── Show Name/
    │   │   ├── Season 01/
    │   │   │   ├── S01E01.mp4
    │   │   │   └── S01E02.mp4
    ├── music/
    │   ├── Artist/
    │   │   └── Album/
    │   │       └── track.mp3
    └── photos/
  ```
- **Backup Priority:** CRITICAL - Your actual media files

### 3. Cache PVC (10Gi) - jellyfin-cache
- **Mount Point:** `/cache`
- **Purpose:** Temporary transcoding files, thumbnails
- **Contents:**
  - Transcoding temp files
  - Image cache
  - Download cache
- **Backup Priority:** LOW - Can be regenerated

## Adding Media Files

### Method 1: kubectl cp (For Small Files)
```bash
# Get pod name
POD_NAME=$(kubectl get pod -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].metadata.name}')

# Copy a single file
kubectl cp /path/to/movie.mp4 jellyfin/$POD_NAME:/media/movies/

# Copy a directory
kubectl cp /path/to/tv-show/ jellyfin/$POD_NAME:/media/tv/show-name/
```

**Limitations:** Slow for large files, times out for very large files

### Method 2: Direct PVC Access (Recommended for Large Files)
```bash
# 1. Find the PVC path on the node
kubectl get pvc jellyfin-media -n jellyfin -o jsonpath='{.spec.volumeName}'
# Example output: pvc-1234abcd-5678-90ef-ghij-klmnopqrstuv

# 2. SSH to the Pi and find the actual path
ssh pi@<PI_IP>
sudo find /var/lib/rancher/k3s/storage -name "pvc-1234abcd*" -type d

# 3. Copy files directly
sudo cp -r /source/movies/* /var/lib/rancher/k3s/storage/pvc-1234abcd.../movies/

# 4. Fix permissions (Jellyfin runs as UID 1000)
sudo chown -R 1000:1000 /var/lib/rancher/k3s/storage/pvc-1234abcd...
```

### Method 3: NFS/Samba Share (Future Enhancement)
For easier media management, consider mounting an NFS or Samba share instead of using PVC for media.

## Media Library Setup

1. **Access Jellyfin Web UI**
   - External: https://jellyfin.charn.io
   - Local: https://jellyfin.local.charn.io
   - NodePort: http://<PI_IP>:30096

2. **First-Time Setup**
   - Create admin account
   - Set display language
   - Skip remote access (already configured via Ingress)

3. **Add Media Libraries**
   - Dashboard → Libraries → Add Media Library
   - **Movies:**
     - Content type: Movies
     - Folder: `/media/movies`
     - Metadata providers: TheMovieDB, OMDb
     - Enable: Download artwork, Extract chapter images
   - **TV Shows:**
     - Content type: Shows
     - Folder: `/media/tv`
     - Metadata providers: TheTVDB, TheMovieDB
   - **Music:**
     - Content type: Music
     - Folder: `/media/music`
     - Metadata providers: MusicBrainz, TheAudioDB

4. **Scan Library**
   - Jellyfin will automatically scan and download metadata
   - Initial scan can take hours for large libraries
   - Monitor progress in Dashboard → Scheduled Tasks

## Performance Optimization

### Raspberry Pi 4 Limitations

**Hardware Constraints:**
- CPU: ARM Cortex-A72 (4 cores @ 1.5GHz)
- RAM: 8GB
- No GPU acceleration for transcoding
- Limited CPU power for transcoding

**Recommendations:**

1. **Prefer Direct Play**
   - Use media in formats that clients support natively
   - **Recommended formats:**
     - Video: H.264 (1080p or lower), H.265 for newer clients
     - Audio: AAC, MP3
     - Container: MP4, MKV
   - **Avoid:** 4K content, HEVC on older clients, AVI files

2. **Disable Transcoding When Possible**
   - Dashboard → Playback → Transcoding
   - Set "Hardware acceleration" to "None"
   - Enable "Allow audio transcoding" only if needed
   - Disable "Throttle transcoding" (wastes CPU)

3. **Client Settings**
   - Use Jellyfin native clients (better Direct Play support)
   - Configure client to prefer Direct Play
   - Disable subtitle burning (forces transcode)

4. **Resource Limits**
   - Current: 2 CPU cores, 2Gi RAM
   - Sufficient for 2-3 simultaneous Direct Play streams
   - Only 1 transcode stream recommended

### Transcoding Performance

**Expected Performance:**
- **Direct Play:** 5-10 simultaneous streams (network limited)
- **Transcoding:** 1 stream at 720p (real-time)
- **Transcoding 1080p:** 0.3-0.5x speed (buffering likely)

**When Transcoding Occurs:**
- Client doesn't support codec
- Bitrate exceeds network capacity
- Subtitles are enabled (subtitle burning)
- Audio codec not supported

**How to Check:**
- Dashboard → Activity
- Look for "Transcoding" vs "Direct Play"
- If buffering occurs, check transcoding speed

## Configuration Details

### Environment Variables

```yaml
env:
  - name: TZ
    value: America/New_York
    # Purpose: Set timezone for logs and scheduled tasks

  - name: JELLYFIN_PublishedServerUrl
    value: https://jellyfin.charn.io
    # Purpose: URL shown to clients for remote access
    # Used by mobile/TV apps for server discovery
```

### Resource Limits

```yaml
resources:
  requests:
    cpu: 500m        # Minimum: 0.5 cores guaranteed
    memory: 512Mi    # Minimum: 512MB guaranteed
  limits:
    cpu: "2"         # Maximum: 2 cores (50% of Pi)
    memory: 2Gi      # Maximum: 2GB (25% of Pi)
```

**Why These Values:**
- **Requests:** Baseline for idle operation and Direct Play
- **Limits:** Allow burst for transcoding without starving system
- **CPU Limit:** Prevents single transcode from using all cores
- **Memory Limit:** Jellyfin typically uses 300-500Mi, spikes during scans

### Health Probes

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8096
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30    # 30 * 10s = 5 minutes total

readinessProbe:
  httpGet:
    path: /health
    port: 8096
  initialDelaySeconds: 60
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health
    port: 8096
  initialDelaySeconds: 120
  periodSeconds: 30
```

**Why These Settings:**
- Jellyfin startup time: 1-3 minutes (database init, plugin load)
- Startup probe: Allows 5 minutes before failing (generous for Pi)
- Readiness: 60s delay ensures basic functionality is ready
- Liveness: 120s delay, only checks if completely frozen

## Troubleshooting

### Pod Stuck in Pending

**Symptoms:**
```bash
$ kubectl get pods -n jellyfin
NAME                        READY   STATUS    RESTARTS   AGE
jellyfin-5f9c8d7b6c-xyz     0/1     Pending   0          5m
```

**Causes:**
1. **PVCs Not Bound:**
   ```bash
   kubectl get pvc -n jellyfin
   # If STATUS is "Pending", PVC is waiting for pod to schedule
   # This is normal with WaitForFirstConsumer
   ```
   - **Solution:** This is normal. PVC binds when pod schedules.

2. **Insufficient Storage:**
   ```bash
   df -h /var/lib/rancher/k3s/storage
   ```
   - **Solution:** Free up space or reduce PVC sizes

3. **Resource Constraints:**
   ```bash
   kubectl describe pod -n jellyfin <pod-name>
   # Look for "Insufficient cpu" or "Insufficient memory"
   ```
   - **Solution:** Reduce resource requests or free up resources

### Pod Crashes (CrashLoopBackOff)

**Check Logs:**
```bash
kubectl logs -n jellyfin -l app=jellyfin --tail=100
```

**Common Issues:**

1. **Permission Denied:**
   ```
   Error: Permission denied writing to /config
   ```
   - **Cause:** PVC permissions incorrect
   - **Solution:**
     ```bash
     # SSH to Pi
     PVC_PATH=$(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.name=="jellyfin-config")].spec.local.path}')
     sudo chown -R 1000:1000 $PVC_PATH
     ```

2. **Out of Memory (OOMKilled):**
   ```bash
   kubectl describe pod -n jellyfin <pod-name>
   # Look for "Reason: OOMKilled"
   ```
   - **Solution:** Increase memory limit or reduce concurrent streams

3. **Corrupted Database:**
   ```
   Error: SQLite error database disk image is malformed
   ```
   - **Solution:** Restore from backup or rebuild library

### Playback Issues

**Symptoms:** Buffering, stuttering, or failed playback

**Diagnosis:**
1. **Check Transcoding:**
   - Dashboard → Activity
   - If "Transcoding", this is the issue

2. **Check Network:**
   ```bash
   # From client machine
   ping jellyfin.charn.io
   curl -o /dev/null https://jellyfin.charn.io/static/test-10mb.bin
   ```

3. **Check Server Resources:**
   ```bash
   kubectl top pod -n jellyfin
   # If CPU near 2000m (2 cores), transcoding is maxed
   ```

**Solutions:**
- Use Direct Play compatible formats (H.264 MP4)
- Lower client quality settings
- Use local URL when at home (jellyfin.local.charn.io)
- Disable subtitle burning

### Metadata Not Downloading

**Symptoms:** No posters, descriptions, or episode info

**Checks:**
1. **Internet Access:**
   ```bash
   kubectl exec -it -n jellyfin deployment/jellyfin -- curl -I https://api.themoviedb.org
   ```

2. **File Naming:**
   - Movies: `Movie Title (Year)/Movie Title (Year).ext`
   - TV: `Show Name/Season 01/S01E01.ext`

3. **Metadata Providers:**
   - Dashboard → Libraries → Manage Libraries → Edit
   - Ensure TheMovieDB, TheTVDB are enabled
   - Try "Scan Library" → "Replace All Metadata"

### Large Library Scan Slow

**Expected Performance:**
- 100 movies: 5-10 minutes
- 1000 movies: 1-2 hours
- 10000 items: 5-10 hours

**Optimization:**
```bash
# Increase resources temporarily during scan
kubectl edit deployment -n jellyfin jellyfin
# Change limits.cpu to "4" and limits.memory to "4Gi"

# After scan completes, revert changes
```

## Client Setup

### Web Browser
- Just visit: https://jellyfin.charn.io
- No installation needed
- Best for testing, not ideal for watching

### Desktop Apps

**Official Clients:**
- **Jellyfin Media Player** (Windows, Mac, Linux)
  - Download: https://jellyfin.org/downloads/
  - Best desktop experience
  - Hardware acceleration support

**Configuration:**
- Server: https://jellyfin.charn.io
- Username/Password: Your Jellyfin account

### Mobile Apps

**Android:**
- **Jellyfin for Android** (Google Play or F-Droid)
- Best mobile experience
- Supports download for offline playback

**iOS:**
- **Jellyfin Mobile** (App Store)
- Full feature parity with Android

**Configuration:**
- Add server: https://jellyfin.charn.io
- Or use server discovery (may auto-detect)

### TV Apps

**Android TV / Fire TV:**
- Jellyfin for Android TV (available in stores)
- Best TV experience

**Roku:**
- Search "Jellyfin" in Roku Channel Store

**Samsung Tizen / LG webOS:**
- No official app
- Use web browser on TV

**Apple TV:**
- Swiftfin (Third-party client, App Store)

## Backup and Recovery

### What to Backup

**Critical (Must Backup):**
1. **Config PVC:** `/config`
   - All settings, users, library metadata
   - Size: ~5-10GB typically

**Important (Should Backup):**
2. **Media PVC:** `/media`
   - Your actual media files
   - Size: Variable (500GB in this setup)

**Optional (Can Skip):**
3. **Cache PVC:** `/cache`
   - Regenerated automatically

### Backup Methods

**Method 1: kubectl cp (Small Configs)**
```bash
# Backup config
kubectl exec -n jellyfin deployment/jellyfin -- tar czf /tmp/config-backup.tar.gz -C /config .
kubectl cp jellyfin/<pod-name>:/tmp/config-backup.tar.gz ./jellyfin-config-$(date +%Y%m%d).tar.gz

# Restore config
kubectl cp ./jellyfin-config-20250101.tar.gz jellyfin/<pod-name>:/tmp/
kubectl exec -n jellyfin deployment/jellyfin -- tar xzf /tmp/jellyfin-config-20250101.tar.gz -C /config
kubectl rollout restart -n jellyfin deployment/jellyfin
```

**Method 2: Direct PVC Backup (Recommended)**
```bash
# SSH to Pi
ssh pi@<PI_IP>

# Find PVC paths
sudo find /var/lib/rancher/k3s/storage -name "pvc-*" -type d

# Backup config
sudo tar czf /backup/jellyfin-config-$(date +%Y%m%d).tar.gz -C /var/lib/rancher/k3s/storage/pvc-config-... .

# Restore config
sudo tar xzf /backup/jellyfin-config-20250101.tar.gz -C /var/lib/rancher/k3s/storage/pvc-config-...
sudo chown -R 1000:1000 /var/lib/rancher/k3s/storage/pvc-config-...
```

**Method 3: Velero (For Complete Cluster Backups)**
- Future enhancement
- Automated backups of all PVCs
- Point-in-time recovery

## Monitoring

### Resource Usage
```bash
# Pod resources
kubectl top pod -n jellyfin

# Storage usage
kubectl exec -n jellyfin deployment/jellyfin -- df -h

# Logs
kubectl logs -f -n jellyfin -l app=jellyfin
```

### Active Streams
- Dashboard → Activity
- Shows current playback sessions
- CPU usage per stream
- Transcode vs Direct Play

### Scheduled Tasks
- Dashboard → Scheduled Tasks
- Library scans, log cleanup, backup tasks

## Common Operations

### Restart Jellyfin
```bash
kubectl rollout restart -n jellyfin deployment/jellyfin
```

### View Logs
```bash
# Recent logs
kubectl logs -n jellyfin -l app=jellyfin --tail=100

# Follow logs
kubectl logs -f -n jellyfin -l app=jellyfin

# Logs from specific time
kubectl logs --since=1h -n jellyfin -l app=jellyfin
```

### Shell Access
```bash
kubectl exec -it -n jellyfin deployment/jellyfin -- bash

# Inside pod
ls -la /config
ls -la /media
df -h
```

### Check Events
```bash
kubectl get events -n jellyfin --sort-by='.lastTimestamp'
```

### Update Image
```bash
# Edit deployment to change image tag
kubectl edit deployment -n jellyfin jellyfin

# Or use kubectl set image
kubectl set image deployment/jellyfin jellyfin=jellyfin/jellyfin:10.8.13 -n jellyfin

# Check rollout status
kubectl rollout status deployment/jellyfin -n jellyfin
```

## Security Considerations

### Network Access
- External: Secured via Cloudflare Tunnel + TLS
- Local: Direct HTTPS with TLS certificate
- NodePort: HTTP only, use for testing only

### Authentication
- Jellyfin built-in user management
- Create separate accounts for family members
- Enable password requirements in Dashboard → Users

### Data Privacy
- Media files stay on your server
- No telemetry sent to Jellyfin project (open source)
- Metadata fetched from public APIs (TheMovieDB, etc.)

### Updates
- Monitor Jellyfin releases: https://github.com/jellyfin/jellyfin/releases
- Test updates in non-production first
- Backup config before major updates

## Lessons Learned

### 1. Storage Planning is Critical
- **Mistake:** Initially underestimated media storage needs
- **Learning:** 500GB fills quickly with HD content
- **Recommendation:** Plan for 2-3x your current library size

### 2. Transcoding is Expensive on Pi
- **Mistake:** Expected Pi 4 to handle multiple transcodes
- **Learning:** Pi 4 struggles with even one 1080p transcode
- **Recommendation:** Use Direct Play compatible formats, avoid transcoding

### 3. Separate PVCs for Different Purposes
- **Decision:** Use three PVCs (config, media, cache)
- **Benefit:** Can backup/restore independently
- **Benefit:** Can resize individually
- **Benefit:** Cache can be cleared without affecting config

### 4. Disable Proxy Buffering for Streaming
- **Issue:** Default Nginx buffering caused playback lag
- **Solution:** `proxy-buffering: off`
- **Impact:** Much smoother streaming experience

### 5. Health Probes Need Long Delays
- **Issue:** Initial 30s startup delay caused restarts
- **Solution:** Increased to 5 minute total startup time
- **Reason:** Pi 4 takes longer to initialize database and plugins

### 6. Published Server URL is Important
- **Issue:** Mobile apps couldn't connect remotely
- **Solution:** Set `JELLYFIN_PublishedServerUrl` to public URL
- **Impact:** Apps now auto-discover server correctly

### 7. Media File Naming Matters
- **Issue:** Metadata wasn't downloading for some files
- **Solution:** Follow Jellyfin naming conventions strictly
- **Tools:** FileBot for bulk renaming

## Next Steps

### Short Term
- [ ] Add hardware monitoring dashboard
- [ ] Set up automated backups
- [ ] Configure fail2ban for admin panel
- [ ] Add more media libraries (Music, Photos)

### Long Term
- [ ] Investigate hardware transcoding (if possible on Pi)
- [ ] Consider NFS mount for media instead of PVC
- [ ] Set up Jellyfin plugins (Trakt, Kodi Sync Queue)
- [ ] Implement user quotas and parental controls

## References

- **Jellyfin Documentation:** https://jellyfin.org/docs/
- **Client Downloads:** https://jellyfin.org/downloads/clients/all
- **Community Forum:** https://forum.jellyfin.org/
- **GitHub Issues:** https://github.com/jellyfin/jellyfin/issues
- **Media Naming Guide:** https://jellyfin.org/docs/general/server/media/movies/
- **Hardware Transcoding:** https://jellyfin.org/docs/general/administration/hardware-acceleration/

## Support

For issues specific to this deployment:
- Check logs: `kubectl logs -n jellyfin -l app=jellyfin`
- Review events: `kubectl get events -n jellyfin`
- See troubleshooting section above

For Jellyfin application issues:
- Documentation: https://jellyfin.org/docs/
- Forum: https://forum.jellyfin.org/
- GitHub: https://github.com/jellyfin/jellyfin
