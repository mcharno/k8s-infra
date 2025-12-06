# Grafana

Metrics visualization and dashboarding platform.

**Status:** Production deployment on K3s (Raspberry Pi 4)
**Access:** https://grafana.charn.io (external) | https://grafana.local.charn.io (local)

## Quick Start

```bash
# Deploy Grafana (requires Prometheus)
bash apps/grafana/base/install.sh

# Or manually
kubectl apply -k apps/grafana/base/

# Monitor startup
kubectl logs -f -n monitoring -l app=grafana
```

## Access URLs

- **External:** https://grafana.charn.io
- **Local:** https://grafana.local.charn.io (faster when at home)
- **NodePort:** http://192.168.0.23:30300 (testing only)

## Default Credentials

**⚠️ CHANGE ON FIRST LOGIN!**

```
Username: admin
Password: admin
```

You'll be prompted to change the password on first login.

## Pre-Configured Datasource

Prometheus datasource is automatically configured:
- **Name:** Prometheus
- **URL:** http://prometheus:9090
- **Access:** Proxy (via Grafana)

## Importing Dashboards

### Method 1: Import by ID (Recommended)

1. Login to https://grafana.charn.io
2. Click + → Import Dashboard
3. Enter dashboard ID from https://grafana.com/grafana/dashboards/
4. Select "Prometheus" as datasource

**Popular Dashboards:**
- **315** - Kubernetes Cluster Monitoring (Prometheus)
- **6417** - Kubernetes Pod Resources
- **1860** - Node Exporter Full
- **7249** - Kubernetes Cluster
- **13770** - Kubernetes Cluster Monitoring (Prometheus)

### Method 2: Import JSON

```bash
# Download dashboard JSON
curl -o dashboard.json https://grafana.com/api/dashboards/315/revisions/1/download

# Import via Grafana UI: + → Import → Upload JSON
```

## Common Operations

```bash
# View logs
kubectl logs -f -n monitoring -l app=grafana

# Check status
kubectl get pods,pvc,ingress -n monitoring

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Change admin password
kubectl exec -it -n monitoring deployment/grafana -- grafana-cli admin reset-admin-password newpassword

# Update image
kubectl set image deployment/grafana grafana=grafana/grafana:latest -n monitoring
```

## Configuration

### Add New Datasources

Edit the datasources ConfigMap:
```bash
kubectl edit configmap grafana-datasources -n monitoring
kubectl rollout restart deployment/grafana -n monitoring
```

### Persistent Storage

Grafana data (dashboards, users, settings) is stored in a 10Gi PVC:
```bash
kubectl get pvc -n monitoring | grep grafana
```

## Troubleshooting

### Cannot Login

Reset admin password:
```bash
kubectl exec -it -n monitoring deployment/grafana -- \
  grafana-cli admin reset-admin-password newpassword
```

### Dashboards Not Saving

Check PVC is bound:
```bash
kubectl get pvc grafana-data -n monitoring
```

### Prometheus Not Connected

Verify Prometheus is running:
```bash
kubectl get pods -n monitoring -l app=prometheus
```

Test connection from Grafana:
```bash
kubectl exec -it -n monitoring deployment/grafana -- \
  wget -O- http://prometheus:9090/api/v1/status/config
```

## Backup

```bash
# Backup Grafana data (dashboards, users, settings)
POD=$(kubectl get pod -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $POD -- tar czf /tmp/grafana-backup.tar.gz -C /var/lib/grafana .
kubectl cp monitoring/$POD:/tmp/grafana-backup.tar.gz ./grafana-backup-$(date +%Y%m%d).tar.gz

# Restore
kubectl cp ./grafana-backup-20250101.tar.gz monitoring/$POD:/tmp/
kubectl exec -n monitoring $POD -- tar xzf /tmp/grafana-backup.tar.gz -C /var/lib/grafana
kubectl rollout restart deployment/grafana -n monitoring
```

## Resources

- **CPU:** 100m request, 500m limit
- **Memory:** 128Mi request, 512Mi limit
- **Storage:** 10Gi PVC

## Dependencies

**Required:** Prometheus (http://prometheus:9090)

Deploy Prometheus first:
```bash
kubectl apply -k apps/prometheus/base/
```

## Documentation

- **Detailed Setup:** See SETUP.md
- **Official Docs:** https://grafana.com/docs/
- **Dashboard Library:** https://grafana.com/grafana/dashboards/
- **Provisioning:** https://grafana.com/docs/grafana/latest/administration/provisioning/

## Related

- **Installation Script:** install.sh
- **Manifests:** All Kubernetes manifests in this directory
- **Kustomize:** kustomization.yaml
- **Prometheus:** ../prometheus/base/