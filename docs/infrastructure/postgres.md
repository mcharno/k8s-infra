# Shared PostgreSQL Database

This directory contains manifests for a shared PostgreSQL 15 instance that serves multiple applications.

## Overview

**Why Shared?**
- **Resource Efficiency:** Single instance uses ~256Mi RAM vs 768Mi for 3 separate instances
- **Easier Backups:** One `pg_dumpall` backs up all application databases
- **Centralized Management:** Single upgrade/maintenance point
- **Production Pattern:** Common in production environments

## Databases

| Database | User | Application |
|----------|------|-------------|
| nextcloud | nextcloud | Nextcloud file storage |
| wallabag | wallabag | Wallabag read-it-later |

## Connection String

Applications should connect using:

```
postgres-lb.database.svc.cluster.local:5432/DATABASE_NAME
```

## Deployment

**Prerequisites:**
- K3s cluster running
- local-path storage class configured

**Steps:**

1. **Create the secret** (passwords):
```bash
# From repository root
./scripts/databases/create-postgres-secret.sh
```

2. **Deploy PostgreSQL**:
```bash
kubectl apply -k infrastructure/databases/postgres/
```

3. **Wait for ready**:
```bash
kubectl wait --for=condition=Ready pod -l app=postgres -n database --timeout=180s
```

4. **Verify**:
```bash
kubectl get pods -n database
kubectl get pvc -n database
kubectl get svc -n database
```

## Resource Allocation

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

## Storage

- **Size:** 30Gi PersistentVolumeClaim
- **Storage Class:** local-path
- **Mount:** `/var/lib/postgresql/data`

## Accessing the Database

**Connect via kubectl:**
```bash
kubectl exec -it -n database postgres-0 -- psql -U postgres
```

**List databases:**
```sql
\l
```

**Connect to specific database:**
```sql
\c nextcloud
```

**List tables:**
```sql
\dt
```

## Backup & Restore

**Backup all databases:**
```bash
kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > postgres-backup-$(date +%Y%m%d).sql
```

**Backup specific database:**
```bash
kubectl exec -n database postgres-0 -- pg_dump -U postgres nextcloud > nextcloud-backup-$(date +%Y%m%d).sql
```

**Restore:**
```bash
kubectl exec -i -n database postgres-0 -- psql -U postgres < backup.sql
```

## Retrieving Passwords

**Admin password:**
```bash
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.admin-password}' | base64 -d
```

**Application passwords:**
```bash
# Nextcloud
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.nextcloud-password}' | base64 -d

# Wallabag
kubectl get secret postgres-passwords -n database -o jsonpath='{.data.wallabag-password}' | base64 -d
```

## Application Configuration

Applications need these environment variables:

**Nextcloud:**
```yaml
- name: POSTGRES_HOST
  value: postgres-lb.database.svc.cluster.local
- name: POSTGRES_DB
  value: nextcloud
- name: POSTGRES_USER
  value: nextcloud
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-passwords
      key: nextcloud-password
```

**Wallabag:**
```yaml
- name: POSTGRES_HOST
  value: postgres-lb.database.svc.cluster.local
- name: POSTGRES_DB
  value: wallabag
- name: POSTGRES_USER
  value: wallabag
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-passwords
      key: wallabag-password
```

## Monitoring

**Check pod status:**
```bash
kubectl get pods -n database
kubectl describe pod postgres-0 -n database
```

**View logs:**
```bash
kubectl logs -f -n database postgres-0
```

**Check resource usage:**
```bash
kubectl top pod postgres-0 -n database
```

## Troubleshooting

**Pod not starting:**
```bash
# Check events
kubectl get events -n database --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n database postgres-0

# Check PVC
kubectl get pvc -n database
kubectl describe pvc postgres-data -n database
```

**Connection refused:**
```bash
# Test from another pod
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- \
  psql -h postgres-lb.database -U postgres

# Check service
kubectl get svc -n database
kubectl get endpoints postgres-lb -n database
```

**Database initialization failed:**
```bash
# Check init script logs (first startup)
kubectl logs -n database postgres-0 | grep -A 20 "init"

# If needed, delete and recreate
kubectl delete statefulset postgres -n database
kubectl delete pvc postgres-data -n database
kubectl apply -k infrastructure/databases/postgres/
```

## Maintenance

**Upgrade PostgreSQL:**

1. Backup all databases
2. Update image version in `statefulset.yaml`
3. Apply changes:
```bash
kubectl apply -k infrastructure/databases/postgres/
kubectl rollout restart statefulset postgres -n database
```

**Vacuum databases:**
```bash
kubectl exec -n database postgres-0 -- vacuumdb -U postgres --all
```

## Security Considerations

- ✅ Passwords stored in Kubernetes Secret
- ✅ Passwords auto-generated (strong entropy)
- ✅ Each app has dedicated user
- ✅ Least privilege (apps can't access each other's data)
- ⚠️  Secret not encrypted at rest (consider: Sealed Secrets)
- ⚠️  No network policies (all pods can access)

**Recommendations:**
- Rotate passwords periodically
- Use Sealed Secrets for GitOps
- Implement network policies to restrict access
- Enable SSL/TLS for connections
- Regular backups automated via CronJob

## Adding New Database

To add a database for a new application:

1. **Update configmap.yaml** init script:
```sql
CREATE DATABASE myapp;
CREATE USER myapp WITH PASSWORD '${MYAPP_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp;
\c myapp
GRANT ALL ON SCHEMA public TO myapp;
```

2. **Update secret creation script**:
```bash
MYAPP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
kubectl create secret generic postgres-passwords \
  ... \
  --from-literal=myapp-password="${MYAPP_PASSWORD}" \
  ...
```

3. **Recreate secret and restart**:
```bash
./scripts/databases/create-postgres-secret.sh
kubectl rollout restart statefulset postgres -n database
```

## Files

- `namespace.yaml` - Database namespace
- `pvc.yaml` - 30Gi persistent storage
- `configmap.yaml` - Database initialization SQL
- `statefulset.yaml` - PostgreSQL StatefulSet
- `service.yaml` - Headless + LoadBalancer services
- `secret.yaml.example` - Secret structure (DO NOT COMMIT REAL PASSWORDS)
- `kustomization.yaml` - Kustomize configuration

## References

- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/15/)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
