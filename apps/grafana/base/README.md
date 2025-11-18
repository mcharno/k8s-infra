
# Grafana

 

## Description

Grafana dashboards and visualization.

 

## Required Secrets

```bash

kubectl create secret generic grafana-admin \

  --namespace=monitoring \

  --from-literal=admin-user=admin \

  --from-literal=admin-password=<your-password>

```

 

## Configuration

- Datasources configured via configmap

- Default datasource: Prometheus (http://prometheus.monitoring.svc.cluster.local:9090)

 

## Deploy

```bash

kubectl apply -k apps/grafana/base/

```

