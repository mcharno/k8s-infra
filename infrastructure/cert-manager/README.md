
# Cert-Manager

 

## Description

Automatic SSL/TLS certificate management for Kubernetes.

 

## Installation

 

### Download Official Manifests

```bash

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

```

 

Or save to this directory:

```bash

curl -L -o infrastructure/cert-manager/cert-manager.yaml \

  https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

```

 

### ClusterIssuer Configuration

 

Create `clusterissuer-letsencrypt-prod.yaml`:

```yaml

apiVersion: cert-manager.io/v1

kind: ClusterIssuer

metadata:

  name: letsencrypt-prod

spec:

  acme:

    server: https://acme-v02.api.letsencrypt.org/directory

    email: your-email@example.com

    privateKeySecretRef:

      name: letsencrypt-prod

    solvers:

    - http01:

        ingress:

          class: nginx

```

 

## Deploy

```bash

kubectl apply -k infrastructure/cert-manager/

```

 

## Verify

```bash

kubectl get pods -n cert-manager

kubectl get clusterissuer

```

