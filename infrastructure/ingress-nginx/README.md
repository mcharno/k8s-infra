
# Ingress NGINX

 

## Description

NGINX Ingress Controller for managing external access to services.

 

## Installation Options

 

### Option 1: Export Current Configuration

```bash

kubectl get all,configmap,secret -n ingress-nginx -o yaml > infrastructure/ingress-nginx/current-config.yaml

# Then split into appropriate files

```

 

### Option 2: Use Official Manifests

```bash

curl -o infrastructure/ingress-nginx/deploy.yaml \

  https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

```

 

### Option 3: Helm Template

```bash

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm template ingress-nginx ingress-nginx/ingress-nginx \

  --namespace ingress-nginx \

  --set controller.service.type=LoadBalancer \

  > infrastructure/ingress-nginx/helm-generated.yaml

```

 

## Deploy

```bash

kubectl apply -k infrastructure/ingress-nginx/

```

 

## Verify

```bash

kubectl get pods -n ingress-nginx

kubectl get svc -n ingress-nginx

```

