
# Nextcloud

 

## Description

Nextcloud deployment configuration.

 

## Required Secrets

Create these secrets before deploying:

 

```bash

kubectl create secret generic nextcloud-db \

  --namespace=nextcloud \

  --from-literal=db-host=postgres.database.svc.cluster.local \

  --from-literal=db-user=nextcloud \

  --from-literal=db-password=<your-password> \

  --from-literal=db-name=nextcloud

 

kubectl create secret generic nextcloud-admin \

  --namespace=nextcloud \

  --from-literal=admin-user=admin \

  --from-literal=admin-password=<your-password>

```

 

## Persistent Storage

- Data volume: `/var/www/html/data`

- Config volume: `/var/www/html/config`

 

## Deploy

```bash

kubectl apply -k apps/nextcloud/base/

```

 

## Notes

- Add actual deployment, service, ingress, and PVC manifests based on your current setup

- Export current manifests: `kubectl get deployment,service,ingress,pvc -n nextcloud -o yaml > current-config.yaml`

