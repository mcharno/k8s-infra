# Home Assistant Setup and Deployment Guide

This document describes how Home Assistant was deployed on the K3s cluster, including configuration decisions, troubleshooting steps, and operational notes.

## Overview

Home Assistant is deployed as a containerized application on the K3s cluster with:
- 5Gi persistent storage for configuration
- Hybrid HTTPS access (external via Cloudflare, local direct)
- Resource limits tuned for Raspberry Pi 4
- Security-first configuration without hostNetwork

## Deployment Iterations

### Version 1: hostNetwork Mode

**Script:** `docs/apps-ha.sh`

**Configuration:**
```yaml
hostNetwork: true
dnsPolicy: ClusterFirst
resources:
  requests:
    memory: 512Mi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 2000m
```

**Pros:**
- Full device discovery (mDNS, UPnP, etc.)
- Direct access via port 8123
- Works with all IoT protocols

**Cons:**
- Security risk: container has host network access
- Port conflicts if running multiple instances
- Not Kubernetes-native networking

**Outcome:** Works but security concerns led to iteration 2

### Version 2: NodePort with Security Context

**Script:** `docs/install_homeassistant_simple.sh`

**Configuration:**
```yaml
# Init container for permissions
initContainers:
  - name: init-permissions
    image: busybox:1.36
    command: ['sh', '-c', 'mkdir -p /config && chown -R 1000:1000 /config && chmod -R 755 /config']

# Security context
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  runAsNonRoot: true

# Service
type: NodePort
nodePort: 30123

# Resources (reduced for Pi)
resources:
  requests:
    memory: 384Mi
    cpu: 300m
  limits:
    memory: 1536Mi
    cpu: 1500m
```

**Pros:**
- Better security (no host network)
- Explicit permissions handling
- Lower resource requirements
- Direct access via NodePort

**Cons:**
- Limited device discovery
- Requires manual device configuration
- NodePort not ideal for production

**Outcome:** More secure but still using NodePort

### Version 3: Current Production (Ingress-based)

**Location:** `apps/homeassistant/base/`

**Configuration:**
```yaml
# No hostNetwork
# No init containers (current image handles permissions)
# ClusterIP Service + Ingress

# Environment
env:
  - name: TZ
    value: America/New_York
  - name: HA_EXTERNAL_URL
    value: https://home.charn.io
  - name: HA_INTERNAL_URL
    value: https://home.local.charn.io

# Probes with appropriate delays
startupProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30  # 5 minutes total
livenessProbe:
  initialDelaySeconds: 120
  periodSeconds: 30
readinessProbe:
  initialDelaySeconds: 60
  periodSeconds: 10

# Resources (optimized)
resources:
  requests:
    cpu: 300m
    memory: 384Mi
  limits:
    cpu: 1500m
    memory: 1536Mi

# Dual Ingress (external + local)
```

**Pros:**
- Production-ready Kubernetes networking
- Hybrid HTTPS access
- Better security
- Proper health checks
- No privileged access

**Cons:**
- Device discovery requires manual configuration
- Additional complexity (Ingress setup)

**Outcome:** Current production configuration

## Configuration Details

### Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: homeassistant-config
  namespace: homeassistant
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
```

**Notes:**
- Uses `local-path` provisioner with `WaitForFirstConsumer` mode
- PVC will stay Pending until pod is scheduled (this is normal)
- Stores all configuration, automations, database in /config
- Host location: `/mnt/lvm-storage/homeassistant-config-pvc-*`

### Networking

**Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: homeassistant
  namespace: homeassistant
spec:
  type: ClusterIP
  ports:
    - port: 8123
      targetPort: 8123
```

**External Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homeassistant-external
  namespace: homeassistant
  annotations:
    cert-manager.io/cluster-issuer: cloudflare-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - home.charn.io
      secretName: cloudflare-wildcard-tls
  rules:
    - host: home.charn.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: homeassistant
                port:
                  number: 8123
```

**Local Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homeassistant-local
  namespace: homeassistant
  annotations:
    cert-manager.io/cluster-issuer: local-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - home.local.charn.io
      secretName: local-wildcard-tls
  rules:
    - host: home.local.charn.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: homeassistant
                port:
                  number: 8123
```

### Resource Tuning

**Resource requests/limits chosen based on:**
1. Home Assistant typical usage patterns
2. Raspberry Pi 4 constraints (8GB RAM total)
3. Other applications running on cluster
4. Testing and monitoring

**Observed usage:**
- Idle: 200-300Mi RAM, 5-10% CPU
- Active: 300-500Mi RAM, 10-30% CPU
- Heavy automation: 500-800Mi RAM, 30-50% CPU

**Why these limits:**
- Requests (300m CPU, 384Mi RAM): Ensures pod can schedule and run basic operations
- Limits (1500m CPU, 1536Mi RAM): Allows bursts for heavy operations without starving other apps
- Testing showed OOMKills with 1Gi limit during heavy use, so increased to 1536Mi

## Deployment Process

### Initial Deployment

```bash
# 1. Create namespace
kubectl create namespace homeassistant

# 2. Deploy using Kustomize
kubectl apply -k apps/homeassistant/base/

# 3. Monitor startup
kubectl get pods -n homeassistant -w

# 4. Check logs
kubectl logs -f -n homeassistant -l app=homeassistant
```

### Installation Script

Created `install.sh` for automated deployment:
- Deploys all resources via Kustomize
- Monitors pod startup with detailed status
- Detects common failures (OOMKilled, CrashLoopBackOff)
- Provides access URLs and next steps
- Shows recent logs for debugging

### Common Issues During Deployment

**Issue 1: PVC Pending**
```
STATUS: Pending
REASON: WaitForFirstConsumer
```
**Solution:** This is normal! PVC binds when pod is scheduled.

**Issue 2: OOMKilled**
```
REASON: OOMKilled
```
**Solutions:**
- Reduce memory limits in deployment.yaml
- Free up RAM by stopping other applications
- Reboot Pi to clear memory fragmentation

**Issue 3: Init Container Permissions (v2 only)**
```
Error: permission denied on /config
```
**Solution:** Init container chowns to 1000:1000

**Issue 4: Startup Probe Timeout**
```
Startup probe failed
```
**Solution:** Increased `failureThreshold` to 30 (5 min total startup time)

## Smart Home Device Integration

### Devices Tested

**Working (IP-based configuration):**
- Philips Hue (via bridge IP)
- Google Home (cloud integration)
- Ring (cloud integration)
- ESPHome devices (MQTT)
- Tasmota devices (MQTT)
- Generic HTTP/REST devices

**Limited (auto-discovery issues):**
- Chromecast (mDNS discovery)
- Some UPnP devices
- Devices requiring multicast

### Recommended Setup

1. **Static IPs for all devices**
   - Set DHCP reservations on router
   - Document IP addresses in Home Assistant config

2. **Use MQTT for IoT devices**
   - More reliable than auto-discovery
   - Better for battery-powered devices
   - Centralized management

3. **Cloud integrations when available**
   - Google Home, Alexa integrations work fine
   - No local network discovery needed

4. **Manual configuration over discovery**
   - More explicit and reproducible
   - Easier to backup and restore
   - Better documentation

### If You Need Full Discovery

If device discovery is absolutely critical:

```yaml
# Add to deployment.yaml
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
```

**Trade-offs:**
- ✅ Full mDNS/UPnP discovery
- ❌ Security risk (container has host network)
- ❌ Port conflicts possible
- ❌ Not Kubernetes-native

**Recommendation:** Only enable if manual configuration is not feasible.

## Backup and Recovery

### What to Backup

1. **Configuration directory** (`/config`)
   - configuration.yaml
   - automations.yaml
   - scripts.yaml
   - secrets.yaml
   - .storage/ (contains UI config, users, etc.)
   - home-assistant_v2.db (SQLite database)

2. **Kubernetes manifests** (already in Git)
   - deployment.yaml
   - service.yaml
   - ingress files
   - pvc.yaml

### Backup Process

```bash
# Automated backup
kubectl exec -n homeassistant deployment/homeassistant -- tar czf /tmp/ha-backup.tar.gz /config
kubectl cp homeassistant/$(kubectl get pod -n homeassistant -l app=homeassistant -o jsonpath='{.items[0].metadata.name}'):/tmp/ha-backup.tar.gz ./ha-backup-$(date +%Y%m%d).tar.gz

# Or from host
sudo tar -czf ha-backup.tar.gz /mnt/lvm-storage/homeassistant-config-pvc-*/
```

### Recovery Process

```bash
# 1. Deploy fresh installation
kubectl apply -k apps/homeassistant/base/

# 2. Wait for pod to be running
kubectl wait --for=condition=Ready pod -l app=homeassistant -n homeassistant --timeout=300s

# 3. Restore backup
kubectl cp ./ha-backup.tar.gz homeassistant/$(kubectl get pod -n homeassistant -l app=homeassistant -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n homeassistant deployment/homeassistant -- tar xzf /tmp/ha-backup.tar.gz -C /

# 4. Restart
kubectl rollout restart deployment/homeassistant -n homeassistant
```

## Performance Optimization

### Database Optimization

Home Assistant uses SQLite by default. For better performance:

```yaml
# In configuration.yaml
recorder:
  purge_keep_days: 7  # Reduce from default 10 days
  commit_interval: 30  # Increase from default 1 second
  exclude:
    domains:
      - automation  # Don't record automation state changes
      - updater
    entity_globs:
      - sensor.weather_*  # Exclude high-frequency sensors
```

### Resource Optimization

```yaml
# In configuration.yaml
http:
  server_host: 0.0.0.0  # Listen on all interfaces
  use_x_forwarded_for: true  # Trust proxy headers
  trusted_proxies:
    - 10.0.0.0/8  # Trust Kubernetes pod network
```

### Startup Time Optimization

- Remove unused integrations
- Disable discovery for unused protocols
- Use startup probe with appropriate timeout
- Consider component-specific initialization order

## Monitoring and Logging

### Useful Monitoring Commands

```bash
# Resource usage
kubectl top pod -n homeassistant

# Events (sorted by time)
kubectl get events -n homeassistant --sort-by='.lastTimestamp'

# Logs with timestamps
kubectl logs -n homeassistant -l app=homeassistant --timestamps --tail=100

# Follow logs
kubectl logs -f -n homeassistant -l app=homeassistant

# Search logs for errors
kubectl logs -n homeassistant -l app=homeassistant | grep -i error
```

### Log Levels

Configure in configuration.yaml:

```yaml
logger:
  default: info
  logs:
    homeassistant.core: debug  # Core debugging
    homeassistant.components.mqtt: debug  # MQTT debugging
```

## Future Improvements

### Potential Enhancements

1. **Prometheus Integration**
   - Export Home Assistant metrics
   - Monitor via Grafana dashboards
   - Alert on sensor failures

2. **MQTT Broker**
   - Deploy MQTT broker (Mosquitto) in cluster
   - Use for ESPHome/Tasmota devices
   - Better reliability than cloud MQTT

3. **Database Migration**
   - Consider PostgreSQL instead of SQLite
   - Better performance for large installations
   - Easier backup/restore

4. **High Availability**
   - Not currently possible (SQLite limitation)
   - Would require PostgreSQL + shared storage
   - Overkill for single-user home setup

### Known Limitations

1. **Device Discovery** - Limited without hostNetwork
2. **Single Instance** - No HA possible with SQLite
3. **Resource Constraints** - Pi 4 limits simultaneous automations
4. **USB Devices** - Not currently supported (would need nodeSelector + hostPath)

## Lessons Learned

### What Worked Well

- **Ingress-based access** - Clean separation of external/local
- **Reduced resources** - 384Mi requests work fine for typical use
- **Security context** - Runs well without privileges
- **Startup probe** - 5 minute timeout handles slow first boot
- **Hybrid access** - Best of both worlds (Cloudflare security + local speed)

### What Needed Iteration

- **Resource limits** - Initial 1Gi too low, increased to 1536Mi
- **Init containers** - Not needed with current image
- **hostNetwork** - Started with it, removed for security
- **Probe timings** - Had to tune based on Pi performance

### Best Practices Established

- **Always backup** before making configuration changes
- **Test with NodePort** before adding Ingress
- **Monitor resource usage** to tune limits
- **Document device IPs** for reproducibility
- **Use MQTT** instead of auto-discovery when possible

## References

- **Home Assistant Documentation:** https://www.home-assistant.io/docs/
- **Container Image:** https://github.com/home-assistant/core
- **Installation Scripts:**
  - Current: `apps/homeassistant/base/install.sh`
  - V1 (hostNetwork): `docs/apps-ha.sh`
  - V2 (NodePort): `docs/install_homeassistant_simple.sh`
- **Application Documentation:** `docs/applications/home-assistant.md`
- **Kubernetes Manifests:** `apps/homeassistant/base/`

## Related Documentation

- [Main README](README.md) - Quick reference and operations
- [Application Documentation](../../../docs/applications/home-assistant.md) - User-facing docs
- [Disaster Recovery](../../../docs/disaster-recovery.md) - Cluster rebuild procedures
- [Storage Documentation](../../../docs/infrastructure/storage.md) - PVC and storage class configuration
- [Network Documentation](../../../docs/infrastructure/network.md) - Ingress and Cloudflare setup
