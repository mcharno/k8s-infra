# Jellyfin Media Server

Open-source media server for managing and streaming your media collection.

**Status:** Production deployment on K3s (Raspberry Pi 4)
**Access:** https://jellyfin.charn.io (external) | https://jellyfin.local.charn.io (local)

## Quick Start

```bash
# Deploy Jellyfin
bash apps/jellyfin/base/install.sh

# Or manually
kubectl apply -k apps/jellyfin/base/

# Monitor startup
kubectl logs -f -n jellyfin -l app=jellyfin
```

## Access URLs

- **External:** https://jellyfin.charn.io (via Cloudflare Tunnel)
- **Local:** https://jellyfin.local.charn.io (faster when at home)
- **NodePort:** http://192.168.0.23:30096 (testing only)

## Storage

Three separate PVCs:
- **Config:** 20Gi - Settings, database, metadata
- **Media:** 500Gi - Movies, TV shows, music, photos
- **Cache:** 10Gi - Transcoding temp files, thumbnails

## Adding Media

```bash
# Get pod name
POD=$(kubectl get pod -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].metadata.name}')

# Copy media files
kubectl cp /local/movie.mp4 jellyfin/$POD:/media/movies/
kubectl cp /local/tv-show/ jellyfin/$POD:/media/tv/show-name/

# Or access PVC directly on Pi (faster for large files)
ssh pi@192.168.0.23
sudo find /var/lib/rancher/k3s/storage -name "pvc-*jellyfin-media*"
sudo cp -r /source/media/* /path/to/pvc/
sudo chown -R 1000:1000 /path/to/pvc/
```

## Media Library Setup

1. Access web UI: https://jellyfin.charn.io
2. Dashboard → Libraries → Add Media Library
3. Select content type (Movies, TV Shows, Music)
4. Add folder: `/media/movies` (or appropriate path)
5. Configure metadata providers (TheMovieDB, TheTVDB)
6. Jellyfin will scan and download metadata automatically

## Common Operations

```bash
# View logs
kubectl logs -f -n jellyfin -l app=jellyfin

# Check status
kubectl get pods,pvc,ingress -n jellyfin

# Restart Jellyfin
kubectl rollout restart -n jellyfin deployment/jellyfin

# Shell access
kubectl exec -it -n jellyfin deployment/jellyfin -- bash

# Check resource usage
kubectl top pod -n jellyfin

# View events (troubleshooting)
kubectl get events -n jellyfin --sort-by='.lastTimestamp'
```

## Performance Notes

**Raspberry Pi 4 Limitations:**
- No GPU transcoding (software only)
- Can handle 5-10 Direct Play streams
- Only 1 transcoding stream recommended (720p max)

**Recommendations:**
- Use Direct Play compatible formats (H.264 MP4)
- Avoid transcoding when possible
- Lower quality for remote access
- Use local URL when at home for better performance

## Client Apps

- **Web:** https://jellyfin.charn.io (any browser)
- **Desktop:** Jellyfin Media Player (Windows, Mac, Linux)
- **Mobile:** Jellyfin for Android/iOS
- **TV:** Jellyfin for Android TV, Roku, Apple TV (Swiftfin)

Download: https://jellyfin.org/downloads/clients/all

## Troubleshooting

### Pod Stuck in Pending
```bash
# Check PVC status (should be "Bound")
kubectl get pvc -n jellyfin

# Check storage space
df -h /var/lib/rancher/k3s/storage
```

### Playback Buffering
- Check if transcoding: Dashboard → Activity
- Use Direct Play compatible formats
- Lower client quality settings
- Use local URL when at home

### Metadata Not Downloading
- Verify internet access: `kubectl exec -it -n jellyfin deployment/jellyfin -- curl -I https://api.themoviedb.org`
- Check file naming (follow Jellyfin conventions)
- Dashboard → Libraries → Scan Library → Replace All Metadata

## Backup

```bash
# Backup config (critical)
POD=$(kubectl get pod -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n jellyfin $POD -- tar czf /tmp/config-backup.tar.gz -C /config .
kubectl cp jellyfin/$POD:/tmp/config-backup.tar.gz ./jellyfin-config-$(date +%Y%m%d).tar.gz

# Restore config
kubectl cp ./jellyfin-config-20250101.tar.gz jellyfin/$POD:/tmp/
kubectl exec -n jellyfin $POD -- tar xzf /tmp/jellyfin-config-20250101.tar.gz -C /config
kubectl rollout restart -n jellyfin deployment/jellyfin
```

## Resources

- **CPU:** 500m request, 2 cores limit
- **Memory:** 512Mi request, 2Gi limit
- **Storage:** 530Gi total (config + media + cache)

## Documentation

- **Detailed Setup Guide:** [SETUP.md](SETUP.md)
- **Application Docs:** [../../docs/applications/jellyfin.md](../../docs/applications/jellyfin.md)
- **Official Docs:** https://jellyfin.org/docs/
- **Community Forum:** https://forum.jellyfin.org/

## Related

- **Installation Script:** [install.sh](install.sh) - Automated deployment with monitoring
- **Manifests:** All Kubernetes manifests in this directory
- **Kustomize:** [kustomization.yaml](kustomization.yaml)