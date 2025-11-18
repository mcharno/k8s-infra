
#!/bin/bash

# Script to export current Kubernetes configurations

# This helps populate the repository with your actual running configs

 

set -e

 

echo "Exporting current Kubernetes configurations..."

 

# Infrastructure

echo "Exporting ingress-nginx..."

kubectl get all,configmap,ingressclass -n ingress-nginx -o yaml > infrastructure/ingress-nginx/current-export.yaml

 

echo "Exporting cert-manager..."

kubectl get all,configmap -n cert-manager -o yaml > infrastructure/cert-manager/current-export.yaml

kubectl get clusterissuer -o yaml > infrastructure/cert-manager/clusterissuers.yaml

 

echo "Exporting database namespace..."

kubectl get all,configmap,pvc,statefulset -n database -o yaml > infrastructure/databases/current-export.yaml

 

# Applications

apps=("nextcloud" "wallabag" "jellyfin" "homeassistant" "homer")

for app in "${apps[@]}"; do

    if kubectl get namespace "$app" &> /dev/null; then

        echo "Exporting $app..."

        kubectl get all,ingress,configmap,pvc -n "$app" -o yaml > "apps/$app/base/current-export.yaml"

    else

        echo "Namespace $app not found, skipping..."

    fi

done

 

# Monitoring namespace (prometheus & grafana)

if kubectl get namespace monitoring &> /dev/null; then

    echo "Exporting monitoring (prometheus & grafana)..."

    kubectl get all,ingress,configmap,pvc -n monitoring -o yaml > apps/prometheus/base/monitoring-export.yaml

    # You'll need to split this into prometheus and grafana directories manually

fi

 

echo ""

echo "Export complete! Files saved as *-export.yaml"

echo ""

echo "Next steps:"

echo "1. Review each *-export.yaml file"

echo "2. Remove generated fields (resourceVersion, uid, status, etc.)"

echo "3. Split combined exports into individual resource files"

echo "4. Update kustomization.yaml to reference the actual files"

echo "5. Commit to git"

echo ""

echo "Tip: Use 'kubectl neat' plugin to clean up exported manifests:"

echo "  kubectl krew install neat"

echo "  kubectl get deployment <name> -o yaml | kubectl neat > deployment.yaml"

