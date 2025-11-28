#!/bin/bash

# K3s Installation Script Optimized for Raspberry Pi 4 (8GB)
# ARM Cortex-A72, 4 cores, 7.6GB RAM
# Run with sudo: sudo bash install-k3s.sh

set -e

echo "=== Installing K3s for Raspberry Pi 4 (ARM64) ==="

# Check system resources
echo "Current system resources:"
echo "CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
echo "Cores: $(nproc)"
echo "Architecture: $(uname -m)"
echo ""
echo "Memory:"
free -h
echo ""

# Pre-installation - enable necessary kernel modules
echo "Enabling required kernel modules..."

# Find the correct cmdline.txt location
CMDLINE_FILE=""
if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
    echo "Found cmdline at: $CMDLINE_FILE"

    # Check if cgroup settings already exist
    if ! grep -q "cgroup_enable=cpuset" "$CMDLINE_FILE"; then
        echo "Adding cgroup settings..."
        cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup"
        sed -i '$ s/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE_FILE"
        echo "✓ Cgroup settings added (reboot required)"
    else
        echo "✓ Cgroup settings already present"
    fi
else
    echo "⚠️  Warning: cmdline.txt not found, skipping cgroup configuration"
    echo "   K3s may still work, but if you have issues, manually add:"
    echo "   cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
    echo "   to your boot parameters"
fi

# Enable IP forwarding
echo "Enabling IP forwarding..."
cat <<EOF | tee /etc/sysctl.d/k3s.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/k3s.conf

# Install K3s with optimized settings for Pi 4
echo "Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --kube-apiserver-arg='default-not-ready-toleration-seconds=30' \
  --kube-apiserver-arg='default-unreachable-toleration-seconds=30' \
  --kubelet-arg='max-pods=110' \
  --kubelet-arg='eviction-hard=memory.available<500Mi,nodefs.available<10%' \
  --kubelet-arg='eviction-soft=memory.available<1Gi,nodefs.available<15%' \
  --kubelet-arg='eviction-soft-grace-period=memory.available=2m,nodefs.available=2m' \
  --kubelet-arg='eviction-max-pod-grace-period=120' \
  --kubelet-arg='kube-reserved=cpu=200m,memory=512Mi' \
  --kubelet-arg='system-reserved=cpu=200m,memory=512Mi'" sh -

# Wait for K3s to be ready
echo "Waiting for K3s to start..."
sleep 15

# Set up kubectl access
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

# Add kubectl alias to bashrc if not present
if ! grep -q "alias k=" ~/.bashrc 2>/dev/null; then
    echo "alias k=kubectl" >> ~/.bashrc
    echo "source <(kubectl completion bash)" >> ~/.bashrc
fi

echo "Waiting for node to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=300s

echo ""
echo "=== K3s Installation Complete ==="
echo ""

echo "📊 Cluster Information:"
kubectl get nodes -o wide
echo ""

echo "🎯 Configuration Highlights:"
echo "  • Max Pods: 110 (good for Pi 4)"
echo "  • Memory Reserved: 512Mi for system, 512Mi for kubelet"
echo "  • CPU Reserved: 200m for system, 200m for kubelet"
echo "  • Eviction Thresholds: Aggressive to prevent OOM"
echo "  • Available for workloads: ~6.5GB RAM, ~3.6 CPU cores"
echo ""

echo "📦 Default Storage:"
kubectl get storageclass
echo ""

echo "🔧 K3s Version:"
k3s --version
echo ""

echo "💡 Useful Commands:"
echo "  kubectl get nodes              - View cluster status"
echo "  kubectl get pods -A            - View all pods"
echo "  kubectl top nodes              - View resource usage (after metrics-server)"
echo "  k                              - Short alias for kubectl"
echo ""

echo "📝 Kubeconfig location: /etc/rancher/k3s/k3s.yaml"
echo "   Also copied to: ~/.kube/config"
echo ""

echo "⚠️  IMPORTANT: If this is your first install, you may need to reboot"
echo "   to ensure cgroup settings are active: sudo reboot"
echo ""
echo "Next step: Configure storage with setup-storage.sh"
