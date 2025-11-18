
# Wallabag

 

## Description

Wallabag read-it-later service deployment.

 

## Required Secrets

```bash

kubectl create secret generic wallabag-db \

  --namespace=wallabag \

  --from-literal=db-host=postgres.database.svc.cluster.local \

  --from-literal=db-user=wallabag \

  --from-literal=db-password=<your-password> \

  --from-literal=db-name=wallabag

```

 

## Deploy

```bash

kubectl apply -k apps/wallabag/base/

```

