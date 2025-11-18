
# Homer

 

## Description

Homer dashboard for application access.

 

## Configuration

- Dashboard configuration in `configmap.yaml`

- Store `config.yml` as a ConfigMap

 

## Deploy

```bash

kubectl apply -k apps/homer/base/

```

 

## Notes

- Lightweight, doesn't require persistent storage

- Configuration is entirely in ConfigMap

