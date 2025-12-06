# K3s Automated Cleanup System

This directory contains a Kubernetes CronJob that automatically cleans up stale pods to prevent disk pressure issues.

## Overview

The cleanup system consists of two components:

1. **Kubernetes CronJob** (this directory) - Cleans up stale pods within the cluster
2. **System-level cron** (scripts directory) - Cleans up container images, logs, and system resources

## What This CronJob Does

The pod cleanup CronJob runs every 6 hours and removes:

- Failed pods (older than 1 hour)
- Completed/Succeeded pods (older than 1 hour)
- Evicted pods (any age)
- Pods in Unknown/ContainerStatusUnknown state (older than 1 hour)

## Deployment

Deploy the cleanup CronJob:

```bash
kubectl apply -k infra-k8s/infrastructure/cleanup/
```

Verify deployment:

```bash
# Check if CronJob was created
kubectl get cronjob -n k3s-maintenance

# Check CronJob schedule
kubectl describe cronjob pod-cleanup -n k3s-maintenance

# View recent jobs
kubectl get jobs -n k3s-maintenance

# View logs from most recent job
kubectl logs -n k3s-maintenance -l app=pod-cleanup --tail=100
```

## Configuration

### Adjusting the Schedule

Edit [cronjob.yaml](cronjob.yaml) and change the `schedule` field:

```yaml
spec:
  # Examples:
  schedule: "0 */6 * * *"    # Every 6 hours (default)
  schedule: "0 */12 * * *"   # Every 12 hours
  schedule: "0 2 * * *"      # Daily at 2 AM
  schedule: "*/30 * * * *"   # Every 30 minutes (aggressive)
```

### Adjusting Pod Age Threshold

By default, pods must be older than 1 hour (3600 seconds) before being deleted. To change this, edit [cronjob.yaml](cronjob.yaml) and modify the `3600` values in the jq filters:

```bash
# Change 3600 to desired seconds:
# 1800  = 30 minutes
# 3600  = 1 hour (default)
# 7200  = 2 hours
# 14400 = 4 hours

jq -r '.items[] | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 3600) | ...'
```

## Manual Cleanup

To trigger an immediate cleanup without waiting for the schedule:

```bash
# Create a one-time job from the CronJob
kubectl create job --from=cronjob/pod-cleanup manual-cleanup-$(date +%s) -n k3s-maintenance

# Watch the job progress
kubectl get jobs -n k3s-maintenance -w

# View logs
kubectl logs -n k3s-maintenance -l job-name=manual-cleanup-<timestamp> -f
```

## Monitoring

### Check CronJob Status

```bash
# View CronJob details
kubectl get cronjob pod-cleanup -n k3s-maintenance

# View recent job runs
kubectl get jobs -n k3s-maintenance

# View job history
kubectl get jobs -n k3s-maintenance --sort-by=.metadata.creationTimestamp
```

### View Logs

```bash
# View logs from most recent run
kubectl logs -n k3s-maintenance -l app=pod-cleanup --tail=100

# View logs from a specific job
kubectl logs -n k3s-maintenance -l job-name=<job-name>

# Follow logs in real-time
kubectl logs -n k3s-maintenance -l app=pod-cleanup -f
```

### Check for Failed Jobs

```bash
# List failed jobs
kubectl get jobs -n k3s-maintenance --field-selector status.successful=0

# Describe a failed job to see why it failed
kubectl describe job <job-name> -n k3s-maintenance
```

## Permissions

The CronJob uses a ServiceAccount with ClusterRole permissions to:

- List pods across all namespaces
- Get pod details and status
- Delete pods

See [clusterrole.yaml](clusterrole.yaml) for the full permission set.

## Troubleshooting

### CronJob Not Running

```bash
# Check if CronJob is suspended
kubectl get cronjob pod-cleanup -n k3s-maintenance -o jsonpath='{.spec.suspend}'

# If true, unsuspend it
kubectl patch cronjob pod-cleanup -n k3s-maintenance -p '{"spec":{"suspend":false}}'

# Check for scheduling errors
kubectl describe cronjob pod-cleanup -n k3s-maintenance
```

### Jobs Failing

```bash
# View recent events
kubectl get events -n k3s-maintenance --sort-by='.lastTimestamp'

# Check job logs
kubectl logs -n k3s-maintenance -l app=pod-cleanup --tail=50

# Describe the failed job
kubectl get jobs -n k3s-maintenance
kubectl describe job <job-name> -n k3s-maintenance
```

### Insufficient Permissions

If you see permission errors in the logs:

```bash
# Verify ServiceAccount exists
kubectl get sa pod-cleanup -n k3s-maintenance

# Verify ClusterRole exists
kubectl get clusterrole pod-cleanup

# Verify ClusterRoleBinding exists
kubectl get clusterrolebinding pod-cleanup

# Re-apply RBAC configuration
kubectl apply -f serviceaccount.yaml
kubectl apply -f clusterrole.yaml
kubectl apply -f clusterrolebinding.yaml
```

## Uninstalling

To remove the cleanup system:

```bash
# Delete all resources
kubectl delete -k infra-k8s/infrastructure/cleanup/

# Or delete manually
kubectl delete namespace k3s-maintenance
kubectl delete clusterrole pod-cleanup
kubectl delete clusterrolebinding pod-cleanup
```

## Integration with System-Level Cleanup

This Kubernetes CronJob handles pod cleanup. For a complete solution, also set up the system-level cleanup script on the K3s node:

```bash
# On the K3s node (pibox)
cd ~/projects/homelab
sudo bash scripts/install-cleanup-cron.sh
```

The system-level script handles:
- Container image cleanup
- Log file rotation
- K3s snapshot cleanup
- Package cache cleanup

## Best Practices

1. **Monitor disk usage** regularly to ensure cleanup is working
2. **Check logs** periodically to ensure no errors
3. **Adjust schedule** based on cluster size and activity
4. **Keep job history** limited (3 successful, 1 failed) to save space
5. **Coordinate timing** between pod cleanup and system cleanup (run them at different times)

## Related Documentation

- [System-level cleanup script](../../../scripts/k3s-automated-cleanup.sh)
- [Installation guide](../../../scripts/install-cleanup-cron.sh)
- [Home Assistant SETUP.md](../../apps/homeassistant/base/SETUP.md) - Documents the disk pressure issue that led to this solution
