#!/bin/bash
# Installation script for K3s automated cleanup cron job
# This script sets up automated disk cleanup on the K3s node

set -e

echo "========================================="
echo "K3s Automated Cleanup - Installation"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo"
    echo "Usage: sudo bash install-cleanup-cron.sh"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/k3s-automated-cleanup.sh"

# Check if cleanup script exists
if [ ! -f "$CLEANUP_SCRIPT" ]; then
    echo "ERROR: Cleanup script not found at: $CLEANUP_SCRIPT"
    exit 1
fi

# Make cleanup script executable
chmod +x "$CLEANUP_SCRIPT"
echo "Made cleanup script executable: $CLEANUP_SCRIPT"

# Create symlink in /usr/local/bin for easy access
SYMLINK_PATH="/usr/local/bin/k3s-cleanup"
if [ -L "$SYMLINK_PATH" ] || [ -f "$SYMLINK_PATH" ]; then
    echo "Removing existing symlink: $SYMLINK_PATH"
    rm -f "$SYMLINK_PATH"
fi

ln -s "$CLEANUP_SCRIPT" "$SYMLINK_PATH"
echo "Created symlink: $SYMLINK_PATH -> $CLEANUP_SCRIPT"

# Install required tools if not present
echo ""
echo "Checking for required tools..."

# Check for jq (used in the cleanup script)
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y jq
    elif command -v yum &> /dev/null; then
        yum install -y jq
    else
        echo "WARNING: Could not install jq. Please install it manually."
    fi
else
    echo "jq is already installed"
fi

# Set up cron job
echo ""
echo "Setting up cron job..."
echo ""
echo "Please choose a cleanup schedule:"
echo "1) Daily at 2:00 AM (recommended for small clusters)"
echo "2) Every 12 hours (recommended for busy clusters)"
echo "3) Every 6 hours (recommended for clusters with disk pressure issues)"
echo "4) Weekly on Sunday at 2:00 AM (recommended for large storage)"
echo "5) Custom schedule"
echo ""

read -p "Enter your choice (1-5): " SCHEDULE_CHOICE

case $SCHEDULE_CHOICE in
    1)
        CRON_SCHEDULE="0 2 * * *"
        SCHEDULE_DESC="Daily at 2:00 AM"
        ;;
    2)
        CRON_SCHEDULE="0 */12 * * *"
        SCHEDULE_DESC="Every 12 hours"
        ;;
    3)
        CRON_SCHEDULE="0 */6 * * *"
        SCHEDULE_DESC="Every 6 hours"
        ;;
    4)
        CRON_SCHEDULE="0 2 * * 0"
        SCHEDULE_DESC="Weekly on Sunday at 2:00 AM"
        ;;
    5)
        read -p "Enter custom cron schedule (e.g., '0 3 * * *'): " CRON_SCHEDULE
        SCHEDULE_DESC="Custom: $CRON_SCHEDULE"
        ;;
    *)
        echo "Invalid choice. Using default: Daily at 2:00 AM"
        CRON_SCHEDULE="0 2 * * *"
        SCHEDULE_DESC="Daily at 2:00 AM"
        ;;
esac

# Create cron job entry
CRON_ENTRY="$CRON_SCHEDULE $SYMLINK_PATH >/dev/null 2>&1  # K3s automated cleanup"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "k3s-automated-cleanup.sh\|k3s-cleanup"; then
    echo "Existing cleanup cron job found. Removing it..."
    crontab -l 2>/dev/null | grep -v "k3s-automated-cleanup.sh\|k3s-cleanup" | crontab -
fi

# Add new cron job
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""
echo "Cleanup script installed at: $CLEANUP_SCRIPT"
echo "Symlink created at: $SYMLINK_PATH"
echo "Schedule: $SCHEDULE_DESC"
echo "Cron job: $CRON_SCHEDULE"
echo ""
echo "Logs will be saved to: /var/log/k3s-cleanup/"
echo ""
echo "To view current cron jobs:"
echo "  crontab -l"
echo ""
echo "To run cleanup manually:"
echo "  sudo k3s-cleanup"
echo ""
echo "To remove the cron job:"
echo "  crontab -e"
echo "  (then delete the line containing 'k3s-cleanup')"
echo ""
echo "========================================="
echo ""

# Offer to run cleanup now
read -p "Would you like to run the cleanup now? (y/n): " RUN_NOW

if [ "$RUN_NOW" = "y" ] || [ "$RUN_NOW" = "Y" ]; then
    echo ""
    echo "Running cleanup now..."
    echo ""
    "$CLEANUP_SCRIPT"
else
    echo "Skipping initial cleanup. The cron job will run on schedule."
fi

echo ""
echo "Installation complete!"
