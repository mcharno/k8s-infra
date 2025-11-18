
# Prometheus

 

## Description

Prometheus monitoring system.

 

## Configuration

- Add your `prometheus.yml` configuration to `configmap.yaml`

- Configure scrape targets for your applications

 

## Persistent Storage

- TSDB data: `/prometheus`

 

## Deploy

```bash

kubectl apply -k apps/prometheus/base/

```

 

## Access

- Internal: `http://prometheus.monitoring.svc.cluster.local:9090`

