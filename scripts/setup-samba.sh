#!/bin/bash
# Script to set up Samba file share on k3s cluster

set -e

NAMESPACE="samba"
STORAGE_PATH="/mnt/samba-share"

echo "======================================================"
echo "Samba File Share Setup for k3s"
echo "======================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check cluster connection
echo "Step 1: Verifying cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster."
    exit 1
fi
echo "✓ Connected to cluster"
echo ""

# Check if samba is already deployed
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "⚠ Warning: Samba namespace already exists."
    read -p "Do you want to continue and update the deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Prompt for credentials
echo "Step 2: Configure Samba credentials..."
echo ""
read -p "Enter Samba username [default: sambauser]: " SMB_USER
SMB_USER=${SMB_USER:-sambauser}

while true; do
    read -sp "Enter Samba password (min 8 characters): " SMB_PASS
    echo
    if [ ${#SMB_PASS} -lt 8 ]; then
        echo "⚠ Password must be at least 8 characters. Please try again."
    else
        break
    fi
done

read -p "Enter user ID [default: 1000]: " SMB_UID
SMB_UID=${SMB_UID:-1000}

read -p "Enter group ID [default: 1000]: " SMB_GID
SMB_GID=${SMB_GID:-1000}

echo ""
echo "Step 3: Configure storage..."
read -p "Enter storage path on k3s node [default: $STORAGE_PATH]: " CUSTOM_PATH
STORAGE_PATH=${CUSTOM_PATH:-$STORAGE_PATH}

read -p "Enter storage size [default: 100Gi]: " STORAGE_SIZE
STORAGE_SIZE=${STORAGE_SIZE:-100Gi}

echo ""
echo "Step 4: Creating storage directory on k3s node..."
# Create the directory on the host
sudo mkdir -p "$STORAGE_PATH"
sudo chown $SMB_UID:$SMB_GID "$STORAGE_PATH"
sudo chmod 755 "$STORAGE_PATH"
echo "✓ Created $STORAGE_PATH"
echo ""

# Update the secret with provided credentials
echo "Step 5: Creating Kubernetes resources..."
cd "$(dirname "$0")/.." || exit 1

# Create temporary secret file
cat > /tmp/samba-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: samba-credentials
  namespace: $NAMESPACE
  labels:
    app: samba
type: Opaque
stringData:
  username: "$SMB_USER"
  password: "$SMB_PASS"
  userid: "$SMB_UID"
  groupid: "$SMB_GID"
EOF

# Update PV path if custom
if [ "$STORAGE_PATH" != "/mnt/samba-share" ]; then
    echo "Updating storage path to $STORAGE_PATH..."
    sed -i "s|path: /mnt/samba-share|path: $STORAGE_PATH|g" apps/samba/base/persistentvolume.yaml
fi

# Update storage size if custom
if [ "$STORAGE_SIZE" != "100Gi" ]; then
    echo "Updating storage size to $STORAGE_SIZE..."
    sed -i "s|storage: 100Gi|storage: $STORAGE_SIZE|g" apps/samba/base/persistentvolume.yaml
    sed -i "s|storage: 100Gi|storage: $STORAGE_SIZE|g" apps/samba/base/persistentvolumeclaim.yaml
fi

# Deploy Samba (without the secret from file)
kubectl apply -f apps/samba/base/namespace.yaml
kubectl apply -f apps/samba/base/persistentvolume.yaml
kubectl apply -f apps/samba/base/persistentvolumeclaim.yaml
kubectl apply -f apps/samba/base/configmap.yaml
kubectl apply -f /tmp/samba-secret.yaml
kubectl apply -f apps/samba/base/deployment.yaml
kubectl apply -f apps/samba/base/service.yaml

# Clean up temp secret
rm -f /tmp/samba-secret.yaml

echo "✓ Resources created"
echo ""

# Wait for pod to be ready
echo "Step 6: Waiting for Samba pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=samba -n $NAMESPACE --timeout=120s || {
    echo "⚠ Warning: Pod not ready within timeout. Check status with:"
    echo "   kubectl get pods -n $NAMESPACE"
    echo "   kubectl logs -n $NAMESPACE deployment/samba"
}
echo ""

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "======================================================"
echo "Samba File Share Setup Complete!"
echo "======================================================"
echo ""
echo "Connection Details:"
echo "  Server:     $NODE_IP"
echo "  Port:       30445 (or use default SMB port)"
echo "  Share Name: share"
echo "  Username:   $SMB_USER"
echo "  Password:   ********"
echo ""
echo "Access the share:"
echo ""
echo "Windows:"
echo "  \\\\$NODE_IP\\share"
echo "  or: net use Z: \\\\$NODE_IP\\share /user:$SMB_USER"
echo ""
echo "macOS:"
echo "  smb://$NODE_IP/share"
echo "  or: Finder → Cmd+K → smb://$NODE_IP/share"
echo ""
echo "Linux:"
echo "  smb://$NODE_IP/share"
echo "  or: sudo mount -t cifs //$NODE_IP/share /mnt/samba \\"
echo "      -o username=$SMB_USER,password=<pass>"
echo ""
echo "Storage location on k3s node:"
echo "  $STORAGE_PATH"
echo ""
echo "To check status:"
echo "  kubectl get all -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE deployment/samba"
echo ""
echo "For detailed documentation, see:"
echo "  apps/samba/README.md"
echo ""
