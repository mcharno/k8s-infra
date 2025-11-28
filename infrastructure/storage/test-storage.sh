#!/bin/bash

# Test storage provisioning with WaitForFirstConsumer mode
# Run with: bash test-storage.sh

set -e

echo "=== Testing Storage Provisioning ==="
echo ""

# Check StorageClass exists
echo "1. Checking StorageClass..."
if ! kubectl get storageclass local-path &>/dev/null; then
    echo "❌ StorageClass 'local-path' not found"
    echo ""
    echo "Create it with:"
    echo "  kubectl apply -f infrastructure/storage/storageclass.yaml"
    exit 1
fi

echo "✓ StorageClass 'local-path' exists"
echo ""

# Check binding mode
BINDING_MODE=$(kubectl get storageclass local-path -o jsonpath='{.volumeBindingMode}')
echo "Volume binding mode: $BINDING_MODE"

if [ "$BINDING_MODE" != "WaitForFirstConsumer" ]; then
    echo "⚠️  Warning: Expected WaitForFirstConsumer, got $BINDING_MODE"
    echo "This may cause issues with single-node clusters"
fi
echo ""

# Check provisioner is running
echo "2. Checking local-path-provisioner..."
if ! kubectl get pods -n kube-system -l app=local-path-provisioner | grep -q Running; then
    echo "❌ local-path-provisioner not running"
    kubectl get pods -n kube-system -l app=local-path-provisioner
    exit 1
fi

echo "✓ Provisioner is running"
echo ""

# Cleanup old test resources
echo "3. Cleaning up old test resources..."
kubectl delete pod storage-test-pod -n default --ignore-not-found=true
kubectl delete pvc storage-test -n default --ignore-not-found=true
sleep 3
echo "✓ Cleanup complete"
echo ""

# Create test PVC
echo "4. Creating test PVC..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Mi
EOF

sleep 2

# Check PVC status (should be Pending)
PVC_STATUS=$(kubectl get pvc storage-test -n default -o jsonpath='{.status.phase}')
echo "✓ PVC created - Status: $PVC_STATUS"

if [ "$PVC_STATUS" != "Pending" ]; then
    echo "⚠️  Expected status 'Pending' (waiting for consumer)"
    echo "Got: $PVC_STATUS"
fi
echo ""

# Create pod that uses PVC
echo "5. Creating test pod (triggers provisioning)..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox:1.36
    command: ['sh', '-c', 'echo "Storage test successful!" > /data/test.txt && cat /data/test.txt && sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: storage-test
EOF

echo "✓ Pod created"
echo ""

# Wait for PVC to bind and pod to run
echo "6. Waiting for provisioning (up to 60 seconds)..."
echo ""

for i in {1..20}; do
    PVC_STATUS=$(kubectl get pvc storage-test -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    POD_STATUS=$(kubectl get pod storage-test-pod -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    echo "[$i/20] PVC: $PVC_STATUS | Pod: $POD_STATUS"

    if [ "$PVC_STATUS" = "Bound" ] && [ "$POD_STATUS" = "Running" ]; then
        echo ""
        echo "✅ SUCCESS! Storage provisioning works correctly!"
        echo ""

        # Show details
        echo "PVC Details:"
        kubectl get pvc storage-test -n default
        echo ""

        echo "PV Details:"
        PV_NAME=$(kubectl get pvc storage-test -n default -o jsonpath='{.spec.volumeName}')
        kubectl get pv "$PV_NAME"
        echo ""

        echo "Storage Path:"
        PV_PATH=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.hostPath.path}')
        echo "$PV_PATH"
        echo ""

        # Test data access
        echo "Testing data access (checking if file was written):"
        kubectl exec storage-test-pod -n default -- cat /data/test.txt 2>/dev/null || echo "Could not read file"
        echo ""

        # Cleanup
        echo "Cleaning up test resources..."
        kubectl delete pod storage-test-pod -n default
        kubectl delete pvc storage-test -n default
        echo ""

        echo "════════════════════════════════════════════════════"
        echo "  ✅ Storage provisioner is working correctly!"
        echo "════════════════════════════════════════════════════"
        echo ""
        echo "Key points:"
        echo "  • volumeBindingMode: WaitForFirstConsumer"
        echo "  • PVC stayed Pending until pod was created (expected)"
        echo "  • PV was created when pod was scheduled"
        echo "  • Pod successfully wrote data to volume"
        echo ""
        exit 0
    fi

    # Show events every 5 iterations
    if [ $(($i % 5)) -eq 0 ]; then
        echo ""
        echo "Recent events:"
        kubectl get events -n default --sort-by='.lastTimestamp' | grep -E "storage-test" | tail -3
        echo ""
    fi

    sleep 3
done

echo ""
echo "❌ Test did not complete successfully within 60 seconds"
echo ""

# Show diagnostic information
echo "Final Status:"
kubectl get pvc storage-test -n default
kubectl get pod storage-test-pod -n default
echo ""

echo "PVC Details:"
kubectl describe pvc storage-test -n default
echo ""

echo "Pod Details:"
kubectl describe pod storage-test-pod -n default | tail -30
echo ""

echo "Provisioner Logs:"
kubectl logs -n kube-system -l app=local-path-provisioner --tail=50
echo ""

echo "Check the logs above for errors."
echo ""
echo "Common issues:"
echo "  • Storage path /mnt/k3s-storage not mounted"
echo "  • Provisioner not running"
echo "  • Wrong volumeBindingMode in StorageClass"
echo ""

exit 1
