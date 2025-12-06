#!/bin/bash
# K3s Automated Disk Cleanup Script
# Runs periodically via cron to prevent disk pressure issues
# This script cleans up unused container images, build cache, and logs to free disk space

# Logging setup
LOG_DIR="/var/log/k3s-cleanup"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"
RETENTION_DAYS=30  # Keep logs for 30 days

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "K3s Automated Disk Cleanup Script"
echo "Started at: $(date)"
echo "========================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo"
    exit 1
fi

# Function to get disk usage percentage
get_disk_usage() {
    df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Check current disk usage
DISK_USAGE_BEFORE=$(get_disk_usage)
echo "Current disk usage: ${DISK_USAGE_BEFORE}%"
df -h /
echo ""

# Set cleanup thresholds
CLEANUP_THRESHOLD=80  # Start cleanup if usage is above this
AGGRESSIVE_THRESHOLD=90  # Use aggressive cleanup if above this

DISK_USAGE=$(get_disk_usage)
echo "Disk usage is at ${DISK_USAGE}%"

if [ "$DISK_USAGE" -lt "$CLEANUP_THRESHOLD" ]; then
    echo "Disk usage is below threshold (${CLEANUP_THRESHOLD}%), performing minimal cleanup only..."
    AGGRESSIVE=false
else
    echo "Disk usage is above threshold (${CLEANUP_THRESHOLD}%), performing full cleanup..."
    AGGRESSIVE=true
fi

if [ "$DISK_USAGE" -ge "$AGGRESSIVE_THRESHOLD" ]; then
    echo "WARNING: Disk usage is critically high (>=${AGGRESSIVE_THRESHOLD}%), using aggressive cleanup..."
    AGGRESSIVE=true
fi

echo ""

# 1. Clean up Kubernetes pods in completed/failed state
echo "Step 1: Cleaning up Kubernetes pods..."
if command -v kubectl &> /dev/null; then
    # Delete failed pods (older than 1 hour to avoid deleting recently failed pods that might be investigated)
    FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase=Failed -o json | \
        jq -r '.items[] | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 3600) | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null || echo "")

    if [ -n "$FAILED_PODS" ]; then
        echo "$FAILED_PODS" | while read -r namespace pod; do
            kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true 2>/dev/null && \
                echo "  Deleted failed pod: $namespace/$pod"
        done
    else
        echo "  No old failed pods to clean up"
    fi

    # Delete completed pods (older than 1 hour)
    COMPLETED_PODS=$(kubectl get pods -A --field-selector=status.phase=Succeeded -o json | \
        jq -r '.items[] | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 3600) | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null || echo "")

    if [ -n "$COMPLETED_PODS" ]; then
        echo "$COMPLETED_PODS" | while read -r namespace pod; do
            kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true 2>/dev/null && \
                echo "  Deleted completed pod: $namespace/$pod"
        done
    else
        echo "  No old completed pods to clean up"
    fi

    # Delete evicted pods
    EVICTED_PODS=$(kubectl get pods -A -o json | \
        jq -r '.items[] | select(.status.reason == "Evicted") | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null || echo "")

    if [ -n "$EVICTED_PODS" ]; then
        echo "$EVICTED_PODS" | while read -r namespace pod; do
            kubectl delete pod "$pod" -n "$namespace" --ignore-not-found=true 2>/dev/null && \
                echo "  Deleted evicted pod: $namespace/$pod"
        done
    else
        echo "  No evicted pods to clean up"
    fi
else
    echo "  kubectl not found, skipping Kubernetes pod cleanup"
fi

# 2. Clean up unused container images
echo ""
echo "Step 2: Removing unused container images..."
if command -v k3s &> /dev/null; then
    # Get image count before
    IMAGES_BEFORE=$(k3s crictl images 2>/dev/null | wc -l)

    # Remove unused images
    k3s crictl rmi --prune 2>/dev/null && echo "  Successfully pruned unused images" || echo "  No images to prune"

    # Get image count after
    IMAGES_AFTER=$(k3s crictl images 2>/dev/null | wc -l)
    IMAGES_REMOVED=$((IMAGES_BEFORE - IMAGES_AFTER))

    if [ "$IMAGES_REMOVED" -gt 0 ]; then
        echo "  Removed $IMAGES_REMOVED unused images"
    fi
else
    echo "  k3s not found, skipping image cleanup"
fi

# 3. Clean up stopped containers
echo ""
echo "Step 3: Removing stopped containers..."
if command -v k3s &> /dev/null; then
    STOPPED_CONTAINERS=$(k3s crictl ps -a -q --state=exited 2>/dev/null)
    if [ -n "$STOPPED_CONTAINERS" ]; then
        echo "$STOPPED_CONTAINERS" | xargs k3s crictl rm 2>/dev/null && \
            echo "  Removed stopped containers" || echo "  No stopped containers to remove"
    else
        echo "  No stopped containers to remove"
    fi
else
    echo "  k3s not found, skipping container cleanup"
fi

# 4. Clean up old logs
echo ""
echo "Step 4: Cleaning up old logs..."

# Determine log retention based on disk usage
if [ "$AGGRESSIVE" = true ]; then
    LOG_RETENTION_DAYS=3
    echo "  Using aggressive log retention: ${LOG_RETENTION_DAYS} days"
else
    LOG_RETENTION_DAYS=7
    echo "  Using normal log retention: ${LOG_RETENTION_DAYS} days"
fi

# Clean journal logs
if command -v journalctl &> /dev/null; then
    journalctl --vacuum-time=${LOG_RETENTION_DAYS}d 2>/dev/null && \
        echo "  Cleaned journal logs older than ${LOG_RETENTION_DAYS} days" || \
        echo "  Could not vacuum journal logs"
fi

# Clean containerd logs
if [ -d "/var/lib/rancher/k3s/agent/containerd" ]; then
    LOG_COUNT=$(find /var/lib/rancher/k3s/agent/containerd -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} 2>/dev/null | wc -l)
    if [ "$LOG_COUNT" -gt 0 ]; then
        find /var/lib/rancher/k3s/agent/containerd -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null && \
            echo "  Cleaned $LOG_COUNT containerd log files older than ${LOG_RETENTION_DAYS} days"
    else
        echo "  No old containerd logs to clean"
    fi
fi

# Clean pod logs
if [ -d "/var/log/pods" ]; then
    LOG_COUNT=$(find /var/log/pods -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} 2>/dev/null | wc -l)
    if [ "$LOG_COUNT" -gt 0 ]; then
        find /var/log/pods -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null && \
            echo "  Cleaned $LOG_COUNT pod log files older than ${LOG_RETENTION_DAYS} days"
    else
        echo "  No old pod logs to clean"
    fi
fi

# Clean this script's own logs
if [ -d "$LOG_DIR" ]; then
    OLD_LOGS=$(find "$LOG_DIR" -name "cleanup-*.log" -type f -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l)
    if [ "$OLD_LOGS" -gt 0 ]; then
        find "$LOG_DIR" -name "cleanup-*.log" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null && \
            echo "  Cleaned $OLD_LOGS cleanup log files older than ${RETENTION_DAYS} days"
    fi
fi

# 5. Clean package manager cache
echo ""
echo "Step 5: Cleaning package manager cache..."
if command -v apt-get &> /dev/null; then
    apt-get clean 2>/dev/null && echo "  Cleaned apt cache" || echo "  Could not clean apt cache"
    apt-get autoremove -y 2>/dev/null && echo "  Removed unused packages" || echo "  Could not autoremove packages"
elif command -v yum &> /dev/null; then
    yum clean all 2>/dev/null && echo "  Cleaned yum cache" || echo "  Could not clean yum cache"
fi

# 6. Remove old k3s snapshots
echo ""
echo "Step 6: Checking for old k3s snapshots..."
if [ -d "/var/lib/rancher/k3s/server/db/snapshots" ]; then
    SNAPSHOT_COUNT=$(find /var/lib/rancher/k3s/server/db/snapshots -name "*.zip" -type f 2>/dev/null | wc -l)

    # Keep more snapshots if disk usage is low, fewer if high
    if [ "$AGGRESSIVE" = true ]; then
        KEEP_SNAPSHOTS=3
    else
        KEEP_SNAPSHOTS=5
    fi

    if [ "$SNAPSHOT_COUNT" -gt "$KEEP_SNAPSHOTS" ]; then
        echo "  Found $SNAPSHOT_COUNT snapshots, keeping only the $KEEP_SNAPSHOTS most recent..."
        cd /var/lib/rancher/k3s/server/db/snapshots || exit 1
        ls -t *.zip 2>/dev/null | tail -n +$((KEEP_SNAPSHOTS + 1)) | xargs -r rm -f
        REMOVED_SNAPSHOTS=$((SNAPSHOT_COUNT - KEEP_SNAPSHOTS))
        echo "  Removed $REMOVED_SNAPSHOTS old snapshots"
    else
        echo "  Only $SNAPSHOT_COUNT snapshots found, keeping all"
    fi
else
    echo "  No snapshots directory found"
fi

# 7. Clean up temporary files (aggressive mode only)
if [ "$AGGRESSIVE" = true ]; then
    echo ""
    echo "Step 7: Cleaning temporary files (aggressive mode)..."

    # Clean /tmp files older than 7 days
    if [ -d "/tmp" ]; then
        TMP_COUNT=$(find /tmp -type f -mtime +7 -not -path "*/.*" 2>/dev/null | wc -l)
        if [ "$TMP_COUNT" -gt 0 ]; then
            find /tmp -type f -mtime +7 -not -path "*/.*" -delete 2>/dev/null && \
                echo "  Cleaned $TMP_COUNT old temporary files"
        else
            echo "  No old temporary files to clean"
        fi
    fi

    # Clean /var/tmp files older than 30 days
    if [ -d "/var/tmp" ]; then
        VAR_TMP_COUNT=$(find /var/tmp -type f -mtime +30 -not -path "*/.*" 2>/dev/null | wc -l)
        if [ "$VAR_TMP_COUNT" -gt 0 ]; then
            find /var/tmp -type f -mtime +30 -not -path "*/.*" -delete 2>/dev/null && \
                echo "  Cleaned $VAR_TMP_COUNT old var/tmp files"
        else
            echo "  No old var/tmp files to clean"
        fi
    fi
fi

# 8. Show summary
echo ""
echo "========================================="
echo "Cleanup Summary"
echo "========================================="
DISK_USAGE_AFTER=$(get_disk_usage)
SPACE_FREED=$((DISK_USAGE_BEFORE - DISK_USAGE_AFTER))

echo "Disk usage before: ${DISK_USAGE_BEFORE}%"
echo "Disk usage after:  ${DISK_USAGE_AFTER}%"
echo "Space freed:       ${SPACE_FREED}%"
echo ""
df -h /
echo ""

# Alert if disk usage is still high
if [ "$DISK_USAGE_AFTER" -ge "$AGGRESSIVE_THRESHOLD" ]; then
    echo "WARNING: Disk usage is still critically high (${DISK_USAGE_AFTER}%)!"
    echo "Manual intervention may be required."
    echo ""
elif [ "$DISK_USAGE_AFTER" -ge "$CLEANUP_THRESHOLD" ]; then
    echo "WARNING: Disk usage is still above threshold (${DISK_USAGE_AFTER}%)."
    echo "Consider increasing cleanup frequency or investigating large files."
    echo ""
fi

echo "========================================="
echo "Cleanup complete!"
echo "Completed at: $(date)"
echo "Log saved to: $LOG_FILE"
echo "========================================="

exit 0
