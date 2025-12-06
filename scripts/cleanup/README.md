# K3s Maintenance Scripts

This directory contains scripts for maintaining your K3s cluster and preventing disk pressure issues.

## Overview

The maintenance system consists of two components:

1. **System-level cleanup** (this directory) - Runs on the K3s node to clean container images, logs, and system resources
2. **Pod cleanup CronJob** (infra-k8s/infrastructure/cleanup) - Runs in Kubernetes to clean up stale pods

## Quick Start

### Initial Setup

SSH into your K3s node and run:

```bash
cd ~/projects/homelab
sudo bash scripts/install-cleanup-cron.sh
```

This will:
1. Install required tools (jq)
2. Set up a cron job for automated cleanup
3. Allow you to choose a cleanup schedule
4. Optionally run an immediate cleanup

### Manual Cleanup

To run cleanup manually at any time:

```bash
sudo k3s-cleanup
```

Or run the script directly:

```bash
sudo bash scripts/k3s-automated-cleanup.sh
```

## Scripts

### k3s-automated-cleanup.sh

The main cleanup script that performs:

- **Pod cleanup** - Removes failed, completed, and evicted Kubernetes pods
- **Image cleanup** - Removes unused container images
- **Container cleanup** - Removes stopped containers
- **Log cleanup** - Cleans old journal logs, containerd logs, and pod logs
- **Package cleanup** - Cleans apt/yum cache
- **Snapshot cleanup** - Removes old K3s ETCD snapshots

**Features:**
- Adaptive cleanup based on disk usage
- Detailed logging to `/var/log/k3s-cleanup/`
- Safe deletion (only removes old resources)
- Comprehensive summary report

**Cleanup Thresholds:**
- Below 80% usage: Minimal cleanup (keeps 7-day logs, 5 snapshots)
- 80-90% usage: Full cleanup (keeps 7-day logs, 5 snapshots)
- Above 90% usage: Aggressive cleanup (keeps 3-day logs, 3 snapshots)

### install-cleanup-cron.sh

Installation script that sets up automated cleanup. Offers several schedule options:

1. **Daily at 2:00 AM** - Good for small clusters with low activity
2. **Every 12 hours** - Good for busy clusters
3. **Every 6 hours** - Good for clusters with disk pressure issues
4. **Weekly** - Good for large storage setups
5. **Custom** - Define your own schedule

### disk-usage-analyzer.sh

Diagnostic script that helps identify what's consuming disk space:

```bash
bash scripts/disk-usage-analyzer.sh
```

Shows:
- Top-level directory sizes
- K3s persistent volume sizes
- Large files (>1GB)
- Large log files (>100MB)
- Old files that could be cleaned

## Logs

Cleanup logs are saved to `/var/log/k3s-cleanup/`:

```bash
# View most recent log
sudo ls -lt /var/log/k3s-cleanup/ | head -5

# View a specific log
sudo cat /var/log/k3s-cleanup/cleanup-20251202-140000.log

# Search for errors
sudo grep -i error /var/log/k3s-cleanup/*.log

# See how much space was freed
sudo grep "Space freed" /var/log/k3s-cleanup/*.log
```

Logs are automatically cleaned up after 30 days.

## Monitoring

### Check Disk Usage

```bash
# Current usage
df -h /

# Detailed usage analysis
sudo bash scripts/disk-usage-analyzer.sh

# Check K3s directories specifically
sudo du -sh /var/lib/rancher/k3s/*
```

### Check Cron Status

```bash
# View installed cron jobs
crontab -l

# View cron execution logs
sudo grep CRON /var/log/syslog | grep k3s-cleanup | tail -10

# Check if cleanup is running
ps aux | grep k3s-cleanup
```

### Verify Cleanup is Working

```bash
# Check cleanup logs
sudo tail -f /var/log/k3s-cleanup/cleanup-*.log

# Check Kubernetes events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i disk

# Check node conditions
kubectl describe node | grep -A 5 "Conditions:"
```

## Troubleshooting

### Disk Pressure Not Resolving

If disk pressure persists after cleanup:

1. **Run diagnostic script:**
   ```bash
   sudo bash scripts/disk-usage-analyzer.sh
   ```

2. **Check for large PersistentVolumes:**
   ```bash
   sudo du -sh /home/pi/data/local-path-provisioner/*
   ```

3. **Identify large files:**
   ```bash
   sudo find /var/lib/rancher/k3s -type f -size +1G -exec ls -lh {} \;
   ```

4. **Check container logs:**
   ```bash
   sudo du -sh /var/log/pods/*
   ```

### Cleanup Script Failing

Check the logs for errors:

```bash
# View most recent log
sudo cat /var/log/k3s-cleanup/cleanup-*.log | tail -100

# Check for permission errors
sudo grep -i "permission denied" /var/log/k3s-cleanup/*.log

# Check for missing commands
sudo grep -i "command not found" /var/log/k3s-cleanup/*.log
```

### Cron Not Running

```bash
# Verify cron service is running
sudo systemctl status cron

# Check cron logs
sudo grep CRON /var/log/syslog | tail -20

# Manually trigger to test
sudo bash scripts/k3s-automated-cleanup.sh
```

## Configuration

### Changing Cleanup Schedule

Edit the crontab:

```bash
crontab -e
```

Find the line with `k3s-cleanup` and modify the schedule. Examples:

```cron
# Every 6 hours
0 */6 * * * /usr/local/bin/k3s-cleanup >/dev/null 2>&1

# Daily at 3 AM
0 3 * * * /usr/local/bin/k3s-cleanup >/dev/null 2>&1

# Every Sunday at 2 AM
0 2 * * 0 /usr/local/bin/k3s-cleanup >/dev/null 2>&1

# Every 30 minutes (aggressive)
*/30 * * * * /usr/local/bin/k3s-cleanup >/dev/null 2>&1
```

### Adjusting Cleanup Thresholds

Edit [k3s-automated-cleanup.sh](k3s-automated-cleanup.sh) and modify these variables:

```bash
CLEANUP_THRESHOLD=80      # Start cleanup at 80% disk usage
AGGRESSIVE_THRESHOLD=90   # Aggressive cleanup at 90%
RETENTION_DAYS=30         # Keep cleanup logs for 30 days
LOG_RETENTION_DAYS=7      # Keep system logs for 7 days (normal)
LOG_RETENTION_DAYS=3      # Keep system logs for 3 days (aggressive)
```

## Uninstalling

To remove the automated cleanup:

```bash
# Remove cron job
crontab -e
# Delete the line containing 'k3s-cleanup'

# Remove symlink
sudo rm /usr/local/bin/k3s-cleanup

# Optionally remove logs
sudo rm -rf /var/log/k3s-cleanup
```

## Integration with Kubernetes CronJob

For complete disk management, also deploy the Kubernetes CronJob for pod cleanup:

```bash
kubectl apply -k infra-k8s/infrastructure/cleanup/
```

**Recommended scheduling:**
- System cleanup (this script): Daily at 2 AM
- Pod cleanup (K8s CronJob): Every 6 hours

This ensures they don't run simultaneously and provides comprehensive coverage.

## Best Practices

1. **Start with daily cleanup** and adjust based on disk usage patterns
2. **Monitor logs** for the first week to ensure cleanup is working
3. **Check disk usage** regularly: `df -h /`
4. **Keep both cleanup systems** (system-level and pod cleanup) running
5. **Don't set thresholds too low** - allow some buffer (80% is good)
6. **Review large PVs** periodically - application data may need manual cleanup

## Emergency Cleanup

If you're experiencing immediate disk pressure:

```bash
# 1. Run aggressive cleanup immediately
sudo bash scripts/k3s-automated-cleanup.sh

# 2. Clean up old pods manually
kubectl delete pods --field-selector=status.phase=Failed -A
kubectl delete pods --field-selector=status.phase=Succeeded -A

# 3. Prune container images aggressively
sudo k3s crictl rmi --prune

# 4. Check what's using space
sudo du -sh /var/lib/rancher/k3s/* | sort -h

# 5. If still critical, consider cleaning specific directories
sudo journalctl --vacuum-time=1d
sudo find /var/log/pods -name "*.log" -delete
```

## Related Documentation

- [Pod Cleanup CronJob](../infra-k8s/infrastructure/cleanup/README.md)
- [Home Assistant SETUP.md](../infra-k8s/apps/homeassistant/base/SETUP.md)
- [Disk Usage Analyzer](disk-usage-analyzer.sh)
