# Redis Cache

Shared Redis instance for caching and session storage across applications.

## Overview

**Why Redis?**
- Fast in-memory cache for application data
- Session storage for stateless applications
- Message queue/pub-sub capabilities
- Shared resource across multiple apps

## Configuration

This Redis deployment includes:

- **Persistence:** Both RDB snapshots and AOF (append-only file)
- **Memory Limit:** 200MB with LRU eviction policy
- **Security:** Dangerous commands disabled (FLUSHDB, FLUSHALL, CONFIG)
- **Durability:** fsync every second for AOF

## Deployment

**Prerequisites:**
- K3s cluster running
- local-path storage class configured
- Database namespace exists

**Deploy:**
```bash
kubectl apply -k infrastructure/databases/redis/
```

**Wait for ready:**
```bash
kubectl wait --for=condition=Ready pod -l app=redis -n database --timeout=120s
```

**Verify:**
```bash
kubectl get pods -n database | grep redis
kubectl get pvc -n database | grep redis
kubectl get svc -n database | grep redis
```

## Connection Details

**Service:** `redis.database.svc.cluster.local:6379`

**From application pods:**
```yaml
env:
- name: REDIS_HOST
  value: redis.database.svc.cluster.local
- name: REDIS_PORT
  value: "6379"
```

## Resource Allocation

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

## Storage

- **Size:** 5Gi PersistentVolumeClaim
- **Storage Class:** local-path
- **Mount:** `/data`
- **Persistence:** RDB + AOF enabled

## Persistence Strategy

**RDB Snapshots:**
- Every 15 minutes if 1+ key changed
- Every 5 minutes if 10+ keys changed
- Every 1 minute if 10000+ keys changed

**AOF (Append-Only File):**
- fsync every second
- Better durability than RDB alone
- Auto-rewrite when file gets too large

## Testing Connection

**From kubectl:**
```bash
# Test Redis connectivity
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never -- \
  redis-cli -h redis.database.svc.cluster.local ping

# Should return: PONG
```

**Interactive session:**
```bash
kubectl run -it --rm redis-cli --image=redis:7-alpine --restart=Never -- \
  redis-cli -h redis.database.svc.cluster.local

# Try commands:
> PING
> SET test "hello"
> GET test
> DEL test
> EXIT
```

## Common Operations

**Set a key:**
```bash
kubectl exec -n database deployment/redis -- \
  redis-cli SET mykey "myvalue"
```

**Get a key:**
```bash
kubectl exec -n database deployment/redis -- \
  redis-cli GET mykey
```

**Check memory usage:**
```bash
kubectl exec -n database deployment/redis -- \
  redis-cli INFO memory
```

**Monitor commands:**
```bash
kubectl exec -n database deployment/redis -- \
  redis-cli MONITOR
```

**View stats:**
```bash
kubectl exec -n database deployment/redis -- \
  redis-cli INFO stats
```

## Backup & Restore

**Backup (RDB snapshot):**
```bash
# Trigger immediate snapshot
kubectl exec -n database deployment/redis -- redis-cli BGSAVE

# Copy RDB file
kubectl cp database/REDIS_POD:/data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb
```

**Restore:**
```bash
# 1. Scale down Redis
kubectl scale deployment redis -n database --replicas=0

# 2. Copy backup to PVC
kubectl cp redis-backup.rdb database/REDIS_POD:/data/dump.rdb

# 3. Scale up Redis
kubectl scale deployment redis -n database --replicas=1
```

## Monitoring

**Check pod status:**
```bash
kubectl get pods -n database -l app=redis
kubectl describe pod -n database -l app=redis
```

**View logs:**
```bash
kubectl logs -f -n database -l app=redis
```

**Resource usage:**
```bash
kubectl top pod -n database -l app=redis
```

**Redis metrics:**
```bash
# Connect to Redis
kubectl exec -it -n database deployment/redis -- redis-cli

# Inside redis-cli:
> INFO
> INFO stats
> INFO memory
> INFO replication
```

## Troubleshooting

**Pod not starting:**
```bash
# Check events
kubectl get events -n database --sort-by='.lastTimestamp' | grep redis

# Check logs
kubectl logs -n database -l app=redis

# Check PVC
kubectl describe pvc redis-data -n database
```

**Connection refused:**
```bash
# Test from another pod
kubectl run -it --rm debug --image=redis:7-alpine --restart=Never -- \
  redis-cli -h redis.database.svc.cluster.local ping

# Check service
kubectl get svc redis -n database
kubectl get endpoints redis -n database
```

**High memory usage:**
```bash
# Check current memory
kubectl exec -n database deployment/redis -- \
  redis-cli INFO memory | grep used_memory_human

# View largest keys
kubectl exec -n database deployment/redis -- \
  redis-cli --bigkeys

# If needed, flush specific database
kubectl exec -n database deployment/redis -- \
  redis-cli SELECT 0
kubectl exec -n database deployment/redis -- \
  redis-cli FLUSHDB  # Note: This command is disabled in config
```

**Persistence issues:**
```bash
# Check RDB save status
kubectl exec -n database deployment/redis -- \
  redis-cli LASTSAVE

# Check AOF status
kubectl exec -n database deployment/redis -- \
  redis-cli INFO persistence
```

## Security Considerations

- ✅ Dangerous commands disabled (FLUSHDB, FLUSHALL, CONFIG)
- ✅ Protected mode enabled
- ✅ Bind to all interfaces (within cluster only)
- ⚠️  No password authentication (relies on network isolation)
- ⚠️  No TLS encryption

**Recommendations:**
- Add password authentication for production
- Implement network policies to restrict access
- Enable TLS for encrypted connections
- Regular backups
- Monitor for unusual access patterns

**To add password authentication:**
```yaml
# Add to configmap.yaml:
requirepass YOUR_SECURE_PASSWORD

# Update application connections:
redis-cli -h redis.database.svc.cluster.local -a YOUR_SECURE_PASSWORD
```

## Use Cases

**Session storage:**
- Store user sessions across multiple application pods
- Fast session lookup
- Auto-expiration with TTL

**Caching:**
- Cache database query results
- Cache API responses
- Reduce database load

**Rate limiting:**
- Track API request counts
- Implement sliding window rate limits

**Pub/Sub:**
- Real-time messaging between services
- Event broadcasting

## Application Configuration Examples

**Nextcloud (Redis caching):**
```php
'memcache.distributed' => '\OC\Memcache\Redis',
'memcache.locking' => '\OC\Memcache\Redis',
'redis' => [
  'host' => 'redis.database.svc.cluster.local',
  'port' => 6379,
],
```

**Django (session storage):**
```python
CACHES = {
    'default': {
        'BACKEND': 'django_redis.cache.RedisCache',
        'LOCATION': 'redis://redis.database.svc.cluster.local:6379/1',
    }
}
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
```

**Node.js (ioredis):**
```javascript
const Redis = require('ioredis');
const redis = new Redis({
  host: 'redis.database.svc.cluster.local',
  port: 6379,
});
```

## Maintenance

**Restart Redis:**
```bash
kubectl rollout restart deployment redis -n database
```

**Update Redis version:**
```bash
# Update image in deployment.yaml
# Then apply
kubectl apply -k infrastructure/databases/redis/
```

**Clear all data (if really needed):**
```bash
# Delete PVC (all data lost!)
kubectl delete pvc redis-data -n database

# Recreate
kubectl apply -k infrastructure/databases/redis/
```

## Files

- `pvc.yaml` - 5Gi persistent storage
- `configmap.yaml` - Redis configuration
- `deployment.yaml` - Redis deployment
- `service.yaml` - ClusterIP service
- `kustomization.yaml` - Kustomize configuration

## References

- [Redis Documentation](https://redis.io/docs/)
- [Redis Docker Hub](https://hub.docker.com/_/redis)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [Redis Security](https://redis.io/docs/management/security/)
- [Redis Configuration](https://redis.io/docs/management/config/)
