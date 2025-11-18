
# PostgreSQL

 

## Description

Shared PostgreSQL database for applications.

 

## Required Secrets

```bash

kubectl create secret generic postgres-credentials \

  --namespace=database \

  --from-literal=postgres-password=<your-secure-password>

```

 

## Databases

Create databases for each application:

- nextcloud

- wallabag

- (add others as needed)

 

## Persistent Storage

- Data directory: `/var/lib/postgresql/data`

- Recommend using StatefulSet with persistent volume claims

 

## Deploy

```bash

kubectl apply -k infrastructure/databases/postgres/

```

 

## Backup

Set up regular pg_dump backups:

```bash

kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup.sql

```

 

## Access

- Internal DNS: `postgres.database.svc.cluster.local:5432`

