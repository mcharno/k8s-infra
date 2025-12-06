# Prometheus

Prometheus monitoring system for Kubernetes cluster metrics collection and alerting.

## Quick Start

```bash
# Install Prometheus
./install.sh

# Check status
kubectl get pods -n monitoring -l app=prometheus

# View logs
kubectl logs -n monitoring -l app=prometheus -f
```

## Access

- **External**: https://p8s.charn.io (via Cloudflare Tunnel)
- **Local Network**: https://prometheus.local.charn.io
- **NodePort**: http://192.168.0.23:30090

## Configuration

### Default Settings

- **Image**: prom/prometheus:v2.47.0
- **Retention**: 30 days
- **Storage**: 20Gi PVC
- **Resources**: 250m CPU (request), 1 CPU (limit), 256Mi-1Gi RAM
- **Service Discovery**: Kubernetes API servers, nodes, pods, services

### Scrape Targets

Prometheus is configured with Kubernetes service discovery for:

- **API Servers**: Kubernetes API metrics
- **Nodes**: Node-level metrics (kubelet, cAdvisor)
- **Pods**: All pods with prometheus annotations
- **Services**: All services with prometheus annotations

### Adding Custom Scrape Targets

Edit the ConfigMap:

```bash
kubectl edit configmap prometheus-config -n monitoring
```

Add your scrape config under `scrape_configs`:

```yaml
- job_name: 'my-app'
  static_configs:
  - targets: ['my-app.namespace.svc.cluster.local:8080']
```

Restart Prometheus:

```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

### Annotations for Auto-Discovery

Add these annotations to your pods/services for automatic discovery:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Common Operations

### View Metrics

Access the Prometheus UI at any of the access URLs above and use PromQL:

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# Memory usage by namespace
sum(container_memory_working_set_bytes) by (namespace)

# Node CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod restarts
kube_pod_container_status_restarts_total

# Available disk space
node_filesystem_avail_bytes{mountpoint="/"}
```

### Restart Prometheus

```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

### Check Targets

Go to Status → Targets in the Prometheus UI to see all discovered scrape targets and their health.

### View Configuration

```bash
kubectl get configmap prometheus-config -n monitoring -o yaml
```

### Port Forward (Local Access)

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then access at http://localhost:9090

## Troubleshooting

### Prometheus Pod Not Starting

Check logs:
```bash
kubectl logs -n monitoring -l app=prometheus
```

Common issues:
- **RBAC permissions**: Verify ServiceAccount, ClusterRole, ClusterRoleBinding exist
- **ConfigMap syntax**: Check prometheus.yml syntax in ConfigMap
- **Storage**: Verify PVC is bound

### No Metrics from Kubernetes

Verify RBAC:
```bash
kubectl get clusterrole prometheus
kubectl get clusterrolebinding prometheus
kubectl get serviceaccount prometheus -n monitoring
```

### Targets Not Discovered

Check service discovery:
1. Go to Status → Service Discovery in Prometheus UI
2. Verify kubernetes_sd_configs is working
3. Check pod/service annotations

### Storage Issues

Check PVC:
```bash
kubectl get pvc -n monitoring
kubectl describe pvc prometheus-data -n monitoring
```

Verify disk usage inside pod:
```bash
kubectl exec -n monitoring -it deployment/prometheus -- df -h /prometheus
```

### Query Performance

If queries are slow:
- Reduce retention time (default 30d)
- Increase CPU/memory limits
- Add more specific label matchers to queries
- Use recording rules for frequently-used queries

## Integration with Grafana

Prometheus is pre-configured as a datasource in Grafana:

1. Access Grafana at https://grafana.charn.io
2. Data source: "Prometheus" (http://prometheus:9090)
3. Import dashboards using IDs:
   - **6417**: Kubernetes Cluster
   - **315**: Kubernetes Cluster Monitoring
   - **1860**: Node Exporter Full
   - **7249**: Kubernetes Cluster (Prometheus)

## Backup and Restore

### Backup Metrics Data

```bash
# Create a backup of the PVC
kubectl exec -n monitoring deployment/prometheus -- tar czf /tmp/prometheus-backup.tar.gz -C /prometheus .
kubectl cp monitoring/prometheus-xxx:/tmp/prometheus-backup.tar.gz ./prometheus-backup.tar.gz
```

### Restore Metrics Data

```bash
# Stop Prometheus
kubectl scale deployment/prometheus -n monitoring --replicas=0

# Copy backup to pod
kubectl cp ./prometheus-backup.tar.gz monitoring/prometheus-xxx:/tmp/

# Extract backup
kubectl exec -n monitoring prometheus-xxx -- sh -c "rm -rf /prometheus/* && tar xzf /tmp/prometheus-backup.tar.gz -C /prometheus"

# Restart Prometheus
kubectl scale deployment/prometheus -n monitoring --replicas=1
```

## Upgrading

To upgrade Prometheus version:

```bash
# Edit deployment
kubectl edit deployment prometheus -n monitoring

# Update image version
# spec.template.spec.containers[0].image: prom/prometheus:v2.XX.X

# Verify rollout
kubectl rollout status deployment/prometheus -n monitoring
```

## Useful PromQL Queries

### Resource Usage

```promql
# Total cluster CPU usage
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m]))

# Total cluster memory usage
sum(container_memory_working_set_bytes{container!=""})

# Disk usage by PVC
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100
```

### Pod Metrics

```promql
# Pods by phase
count(kube_pod_status_phase) by (phase)

# Container restarts in last hour
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod)

# Pods not ready
kube_pod_status_ready{condition="false"}
```

### Node Metrics

```promql
# Node memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Node disk usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Node load average
node_load1
```

## Resources

- **Official Docs**: https://prometheus.io/docs/
- **PromQL Guide**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Kubernetes SD**: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config
- **Recording Rules**: https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/
- **Alerting Rules**: https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/

## Related Applications

- **Grafana**: Visualization and dashboards at https://grafana.charn.io
- **Homer**: Dashboard at https://homer.charn.io includes Prometheus link
