
# Redis

 

## Description

Shared Redis cache and message broker.

 

## Configuration

- Persistence enabled (AOF + RDB)

- MaxMemory policy: allkeys-lru

 

## Required Secrets

```bash

kubectl create secret generic redis-credentials \

  --namespace=database \

  --from-literal=redis-password=<your-secure-password>

```

 

## Persistent Storage

- Data directory: `/data`

 

## Deploy

```bash

kubectl apply -k infrastructure/databases/redis/

```

 

## Access

- Internal DNS: `redis.database.svc.cluster.local:6379`

 

## Monitoring

Connect Prometheus to Redis exporter if needed.

