#!/bin/bash

# Setup both SSDs with LVM for K3s storage
# This combines sda (1TB) + sdb (2TB) into one large volume
# Run with sudo: sudo bash setup-lvm.sh

set -e

echo "=== Dual SSD LVM Setup for K3s ==="
echo ""

# 1. Show current setup
echo "Current LVM setup:"
pvs 2>/dev/null || echo "No physical volumes"
vgs 2>/dev/null || echo "No volume groups"
lvs 2>/dev/null || echo "No logical volumes"
echo ""

# 2. Warning
echo "⚠️  WARNING: This will erase ALL data on /dev/sda and /dev/sdb!"
echo ""
echo "Drives to be used:"
echo "  • /dev/sda (1TB SSD)"
echo "  • /dev/sdb (2TB SSD)"
echo "  • Combined size: ~2.7TB"
echo ""
read -p "Continue? Type 'yes' to proceed: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cancelled."
    exit 0
fi

# 3. Unmount if mounted
echo ""
echo "Unmounting drives..."
umount /dev/sda* 2>/dev/null || true
umount /dev/sdb* 2>/dev/null || true

# 4. Remove old LVM setup if exists
echo ""
echo "Removing old LVM setup..."
vgremove -f k3s-storage 2>/dev/null || true
pvremove -f /dev/sda1 2>/dev/null || true
pvremove -f /dev/sdb1 2>/dev/null || true

# 5. Wipe partition tables
echo ""
echo "Wiping partition tables..."
wipefs -a /dev/sda
wipefs -a /dev/sdb

# 6. Create new partitions
echo ""
echo "Creating partitions..."
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary 0% 100%
parted -s /dev/sda set 1 lvm on

parted -s /dev/sdb mklabel gpt
parted -s /dev/sdb mkpart primary 0% 100%
parted -s /dev/sdb set 1 lvm on

sleep 2

# 7. Create physical volumes
echo ""
echo "Creating LVM physical volumes..."
pvcreate /dev/sda1
pvcreate /dev/sdb1

# 8. Create volume group
echo ""
echo "Creating volume group 'k3s-storage'..."
vgcreate k3s-storage /dev/sda1 /dev/sdb1

# 9. Create logical volume (use 100% of space)
echo ""
echo "Creating logical volume..."
lvcreate -l 100%FREE -n data k3s-storage

# 10. Format the volume
echo ""
echo "Formatting logical volume..."
mkfs.ext4 -F /dev/k3s-storage/data

# 11. Create mount point
echo ""
echo "Creating mount point..."
mkdir -p /mnt/k3s-storage

# 12. Add to fstab
echo ""
echo "Adding to /etc/fstab..."
if grep -q "/mnt/k3s-storage" /etc/fstab 2>/dev/null; then
    sed -i '\|/mnt/k3s-storage|d' /etc/fstab
fi

echo "/dev/k3s-storage/data /mnt/k3s-storage ext4 defaults,nofail 0 2" >> /etc/fstab

# 13. Mount
echo ""
echo "Mounting..."
mount /mnt/k3s-storage

# 14. Set permissions and create directories
echo ""
echo "Setting up directories..."
chmod 755 /mnt/k3s-storage
mkdir -p /mnt/k3s-storage/local-path-provisioner
mkdir -p /mnt/k3s-storage/data

chmod 755 /mnt/k3s-storage/local-path-provisioner
chmod 755 /mnt/k3s-storage/data

echo ""
echo "=== LVM Setup Complete ==="
echo ""
echo "📊 LVM Summary:"
pvs
echo ""
vgs
echo ""
lvs
echo ""

echo "💾 Storage Information:"
df -h /mnt/k3s-storage
echo ""

echo "✓ Combined storage: ~2.7TB"
echo "✓ Mounted at: /mnt/k3s-storage"
echo "✓ Auto-mount configured in /etc/fstab"
echo ""

echo "Benefits of LVM:"
echo "  • Single large volume from two drives"
echo "  • Can add more drives later if needed"
echo "  • Snapshots capability (optional)"
echo ""

echo "Next step: Configure K3s to use this storage"
