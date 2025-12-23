# Database Security Hardening - Task 1.2.3

**Status:** 🔄 In Progress
**Date Started:** 2025-12-22

## Overview

This document provides implementation steps for hardening PostgreSQL and Redis databases with SSL/TLS encryption and authentication.

## Current State Assessment

### PostgreSQL
- ✅ Password authentication enabled
- ✅ Resource limits configured
- ✅ Liveness/readiness probes
- ❌ **No SSL/TLS encryption** (traffic in plaintext within cluster)
- ❌ No pg_hba.conf hardening
- ❌ No connection limits

### Redis
- ✅ Dangerous commands disabled (FLUSHDB, FLUSHALL, CONFIG)
- ✅ Protected mode enabled
- ✅ Persistence configured (RDB + AOF)
- ✅ Memory limits (200MB with LRU eviction)
- ❌ **No AUTH password** (anyone in cluster can connect)
- ❌ No TLS encryption

## Security Improvements Needed

### High Priority
1. **Redis AUTH Password** - Prevent unauthorized access
2. **PostgreSQL SSL Enforcement** - Encrypt database traffic
3. **Redis TLS** (optional - lower priority for internal cluster traffic)

### Medium Priority
4. PostgreSQL connection limits
5. pg_hba.conf hardening (host-based access control)
6. Regular credential rotation

---

## Implementation Plan

### Phase 1: Redis AUTH Password (Quick Win)

**Impact:** High
**Effort:** Low
**Risk:** Medium (requires app restarts)

#### Step 1: Generate Redis Password

```bash
# Generate a strong random password
openssl rand -base64 32

# Example output: xK7mN9pQ2rS3tU4vW5xY6zA7bC8dD9eE==
```

#### Step 2: Create Redis Password Secret

Using Sealed Secrets:

```bash
# On your Mac
cd /Users/charno/projects/homelab/infra-k8s

# Create plaintext secret (don't apply!)
kubectl create secret generic redis-auth \
  --from-literal=password='YOUR_GENERATED_PASSWORD' \
  --namespace=database \
  --dry-run=client -o yaml > /tmp/redis-auth-secret.yaml

# Encrypt it with kubeseal
kubeseal --format yaml \
  --cert=infrastructure/security/sealed-secrets/pub-cert.pem \
  < /tmp/redis-auth-secret.yaml \
  > infrastructure/databases/redis/redis-auth-sealed-secret.yaml

# Clean up plaintext
rm /tmp/redis-auth-secret.yaml

# Commit the sealed secret
git add infrastructure/databases/redis/redis-auth-sealed-secret.yaml
git commit -m "Add Redis AUTH password (sealed secret)"
```

#### Step 3: Update Redis ConfigMap

Edit `infrastructure/databases/redis/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: database
data:
  redis.conf: |
    # Redis configuration for K3s homelab

    # Network
    bind 0.0.0.0
    protected-mode yes
    port 6379

    # Authentication (password loaded from secret)
    # Note: Password will be set via command-line arg

    # General
    daemonize no
    pidfile /var/run/redis.pid
    loglevel notice

    # Persistence
    save 900 1      # Save if 1 key changed in 15 minutes
    save 300 10     # Save if 10 keys changed in 5 minutes
    save 60 10000   # Save if 10000 keys changed in 1 minute

    dir /data
    dbfilename dump.rdb

    # Append-only file (for better durability)
    appendonly yes
    appendfilename "appendonly.aof"
    appendfsync everysec

    # Memory management
    maxmemory 200mb
    maxmemory-policy allkeys-lru

    # Disable dangerous commands
    rename-command FLUSHDB ""
    rename-command FLUSHALL ""
    rename-command CONFIG ""
    rename-command KEYS ""
    rename-command SHUTDOWN "SHUTDOWN_SAFE_ONLY"

    # Performance
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300

    # Security - Connection limits
    maxclients 100
```

#### Step 4: Update Redis Deployment

Edit `infrastructure/databases/redis/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        command:
        - redis-server
        - /usr/local/etc/redis/redis.conf
        - --requirepass
        - $(REDIS_PASSWORD)
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-auth
              key: password
        volumeMounts:
        - name: config
          mountPath: /usr/local/etc/redis
        - name: data
          mountPath: /data
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - redis-cli -a $REDIS_PASSWORD ping
          initialDelaySeconds: 15
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - redis-cli -a $REDIS_PASSWORD ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: redis-config
      - name: data
        persistentVolumeClaim:
          claimName: redis-data
```

**Key Changes:**
- Added `--requirepass $(REDIS_PASSWORD)` to command
- Added `REDIS_PASSWORD` environment variable from secret
- Updated probes to use `-a $REDIS_PASSWORD` for authentication

#### Step 5: Update Applications to Use Redis Password

Applications using Redis need their connection strings updated:

**Nextcloud** (if using Redis for caching):
```yaml
env:
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-auth
      key: password
- name: REDIS_HOST
  value: "redis.database.svc.cluster.local"
```

**n8n** (if using Redis):
```yaml
env:
- name: QUEUE_BULL_REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-auth
      key: password
```

#### Step 6: Apply Changes

```bash
# Apply sealed secret first
kubectl apply -f infrastructure/databases/redis/redis-auth-sealed-secret.yaml

# Wait for secret to be created
kubectl get secret redis-auth -n database

# Apply updated ConfigMap
kubectl apply -f infrastructure/databases/redis/configmap.yaml

# Apply updated Deployment
kubectl apply -f infrastructure/databases/redis/deployment.yaml

# Monitor rollout
kubectl rollout status deployment/redis -n database

# Verify Redis is running with AUTH
kubectl exec -it -n database deployment/redis -- redis-cli ping
# Should return: (error) NOAUTH Authentication required.

# Test with password
kubectl exec -it -n database deployment/redis -- sh -c 'redis-cli -a $REDIS_PASSWORD ping'
# Should return: PONG
```

---

### Phase 2: PostgreSQL SSL/TLS Enforcement

**Impact:** High
**Effort:** Medium
**Risk:** Medium-High (requires certificate management)

#### Overview

PostgreSQL SSL requires:
1. Server certificate and private key
2. CA certificate (for client verification - optional)
3. pg_hba.conf configured to require SSL
4. Applications updated to use `sslmode=require`

#### Step 1: Generate PostgreSQL SSL Certificates

Option A: Self-Signed Certificates (Simpler)

```bash
# On your Mac or Pi
mkdir -p /tmp/postgres-ssl

# Generate CA key and certificate
openssl req -new -x509 -days 3650 -nodes \
  -out /tmp/postgres-ssl/ca.crt \
  -keyout /tmp/postgres-ssl/ca.key \
  -subj "/CN=PostgreSQL-CA"

# Generate server key
openssl genrsa -out /tmp/postgres-ssl/server.key 2048

# Generate server certificate signing request
openssl req -new -key /tmp/postgres-ssl/server.key \
  -out /tmp/postgres-ssl/server.csr \
  -subj "/CN=postgres.database.svc.cluster.local"

# Sign server certificate with CA
openssl x509 -req -in /tmp/postgres-ssl/server.csr \
  -CA /tmp/postgres-ssl/ca.crt \
  -CAkey /tmp/postgres-ssl/ca.key \
  -CAcreateserial \
  -out /tmp/postgres-ssl/server.crt \
  -days 3650

# Set correct permissions (PostgreSQL requires strict permissions)
chmod 600 /tmp/postgres-ssl/server.key
chmod 644 /tmp/postgres-ssl/server.crt
chmod 644 /tmp/postgres-ssl/ca.crt
```

Option B: Use cert-manager (More Complex, Better for Production)

Create a Certificate resource that cert-manager will manage.

#### Step 2: Create PostgreSQL SSL Secret

```bash
# Create Kubernetes secret from certificates
kubectl create secret generic postgres-ssl-certs \
  --from-file=server.crt=/tmp/postgres-ssl/server.crt \
  --from-file=server.key=/tmp/postgres-ssl/server.key \
  --from-file=ca.crt=/tmp/postgres-ssl/ca.crt \
  --namespace=database \
  --dry-run=client -o yaml > /tmp/postgres-ssl-secret.yaml

# Seal it
kubeseal --format yaml \
  --cert=infrastructure/security/sealed-secrets/pub-cert.pem \
  < /tmp/postgres-ssl-secret.yaml \
  > infrastructure/databases/postgres/postgres-ssl-sealed-secret.yaml

# Clean up plaintext
rm /tmp/postgres-ssl-secret.yaml
rm -rf /tmp/postgres-ssl

# Commit sealed secret
git add infrastructure/databases/postgres/postgres-ssl-sealed-secret.yaml
git commit -m "Add PostgreSQL SSL certificates (sealed secret)"
```

#### Step 3: Update PostgreSQL StatefulSet

Edit `infrastructure/databases/postgres/statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: database
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-passwords
              key: admin-password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        command:
        - postgres
        - -c
        - ssl=on
        - -c
        - ssl_cert_file=/etc/postgresql/ssl/server.crt
        - -c
        - ssl_key_file=/etc/postgresql/ssl/server.key
        - -c
        - ssl_ca_file=/etc/postgresql/ssl/ca.crt
        - -c
        - ssl_min_protocol_version=TLSv1.2
        - -c
        - ssl_ciphers=HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!SRP:!CAMELLIA
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: init-script
          mountPath: /docker-entrypoint-initdb.d
        - name: ssl-certs
          mountPath: /etc/postgresql/ssl
          readOnly: true
        - name: pg-hba
          mountPath: /etc/postgresql
          readOnly: true
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: postgres-data
      - name: init-script
        configMap:
          name: postgres-init
      - name: ssl-certs
        secret:
          secretName: postgres-ssl-certs
          defaultMode: 0600
      - name: pg-hba
        configMap:
          name: postgres-hba
```

#### Step 4: Create pg_hba.conf ConfigMap

Create `infrastructure/databases/postgres/pg-hba-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-hba
  namespace: database
data:
  pg_hba.conf: |
    # PostgreSQL Host-Based Authentication Configuration
    # TYPE  DATABASE        USER            ADDRESS                 METHOD

    # "local" is for Unix domain socket connections only
    local   all             all                                     md5

    # IPv4 local connections - require SSL
    hostssl all             all             10.42.0.0/16            md5
    hostssl all             all             10.43.0.0/16            md5

    # Reject non-SSL connections
    hostnossl all           all             all                     reject

    # Replication connections (if needed)
    # hostssl replication     replicator      10.42.0.0/16            md5
```

**Note:** This configuration:
- Requires SSL for all TCP connections
- Rejects non-SSL connections
- Allows connections from pod network (10.42.0.0/16) and service network (10.43.0.0/16)

#### Step 5: Apply PostgreSQL SSL Changes

```bash
# Apply sealed secret
kubectl apply -f infrastructure/databases/postgres/postgres-ssl-sealed-secret.yaml

# Apply pg_hba configmap
kubectl apply -f infrastructure/databases/postgres/pg-hba-configmap.yaml

# Apply updated statefulset
kubectl apply -f infrastructure/databases/postgres/statefulset.yaml

# Monitor rollout
kubectl rollout status statefulset/postgres -n database

# Verify SSL is enabled
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "SHOW ssl;"
# Should show: ssl | on
```

#### Step 6: Update Application Connection Strings

Applications need to add `sslmode=require` to their PostgreSQL connection strings:

**Example - Nextcloud:**
```yaml
env:
- name: POSTGRES_HOST
  value: "postgres-lb.database.svc.cluster.local"
- name: POSTGRES_DB
  value: "nextcloud"
- name: POSTGRES_USER
  value: "nextcloud"
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-passwords
      key: nextcloud-password
# Add SSL mode
- name: POSTGRES_SSL_MODE
  value: "require"
```

For applications using connection strings directly:
```
postgresql://user:password@postgres-lb.database.svc.cluster.local:5432/dbname?sslmode=require
```

---

## Verification

### Redis AUTH Verification

```bash
# Test connection without password (should fail)
kubectl exec -it -n database deployment/redis -- redis-cli ping
# Expected: (error) NOAUTH Authentication required.

# Test with password (should succeed)
kubectl exec -it -n database deployment/redis -- sh -c 'redis-cli -a $REDIS_PASSWORD ping'
# Expected: PONG

# Check if apps can connect
kubectl logs -n <app-namespace> <app-pod> | grep -i redis
```

### PostgreSQL SSL Verification

```bash
# Check SSL is enabled
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "SHOW ssl;"
# Expected: on

# Check SSL cipher
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "SELECT ssl_cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();"

# Check active connections use SSL
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "SELECT datname, usename, ssl, client_addr FROM pg_stat_ssl JOIN pg_stat_activity ON pg_stat_ssl.pid = pg_stat_activity.pid;"

# Test connection from app pod
kubectl exec -it -n nextcloud <nextcloud-pod> -- psql "postgresql://nextcloud:password@postgres-lb.database.svc.cluster.local:5432/nextcloud?sslmode=require" -c "\conninfo"
```

---

## Rollback Procedures

### Redis AUTH Rollback

```bash
# Remove password requirement
kubectl edit deployment redis -n database
# Remove --requirepass line and REDIS_PASSWORD env var

# Revert configmap
git checkout infrastructure/databases/redis/configmap.yaml
kubectl apply -f infrastructure/databases/redis/configmap.yaml

# Delete sealed secret
kubectl delete secret redis-auth -n database
```

### PostgreSQL SSL Rollback

```bash
# Revert to non-SSL configuration
git checkout infrastructure/databases/postgres/statefulset.yaml
kubectl apply -f infrastructure/databases/postgres/statefulset.yaml

# Remove pg_hba configmap
kubectl delete configmap postgres-hba -n database

# Delete SSL certificates
kubectl delete secret postgres-ssl-certs -n database
```

---

## CIS Controls Addressed

| CIS Control | Description | Implementation |
|-------------|-------------|----------------|
| 5.4.1 | Prefer using secrets as files | ✅ Using Sealed Secrets |
| 5.4.2 | External secret storage | ✅ Sealed Secrets (encrypted in Git) |
| Custom | Database encryption in transit | ✅ PostgreSQL SSL, Redis AUTH |
| Custom | Strong authentication | ✅ Password-based auth with secrets |
| Custom | Principle of least privilege | ⚠️ Future: per-app database users |

---

## Next Steps

After completing database security:

1. **Application Updates**: Update all apps to use Redis AUTH and PostgreSQL SSL
2. **Monitoring**: Add alerts for failed authentication attempts
3. **Credential Rotation**: Establish quarterly rotation policy
4. **Future Enhancements**:
   - Per-application database users (not just shared passwords)
   - Connection pooling with PgBouncer
   - PostgreSQL Row-Level Security (RLS) policies
   - Redis Sentinel for high availability

---

**Status**: Ready for Implementation
**Estimated Time**: 2-3 hours
**Risk Level**: Medium (requires application updates and restarts)
