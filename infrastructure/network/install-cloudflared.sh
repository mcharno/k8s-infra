#!/bin/bash

# Install and configure Cloudflare Tunnel (cloudflared) on Raspberry Pi
# Run with: bash install-cloudflared.sh

set -e

echo "=== Cloudflare Tunnel (cloudflared) Installation ==="
echo ""

# Check if running on ARM64
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "⚠️  Warning: This script is designed for ARM64 (Raspberry Pi)"
    echo "Current architecture: $ARCH"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Step 1: Install cloudflared
echo "1. Installing cloudflared..."
if command -v cloudflared &> /dev/null; then
    CURRENT_VERSION=$(cloudflared --version | head -n1)
    echo "✓ cloudflared already installed: $CURRENT_VERSION"
    read -p "Reinstall? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping installation..."
    else
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
        sudo dpkg -i cloudflared-linux-arm64.deb
        rm cloudflared-linux-arm64.deb
        echo "✓ cloudflared updated"
    fi
else
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
    sudo dpkg -i cloudflared-linux-arm64.deb
    rm cloudflared-linux-arm64.deb
    echo "✓ cloudflared installed"
fi
echo ""

# Verify installation
CLOUDFLARED_VERSION=$(cloudflared --version | head -n1)
echo "Installed version: $CLOUDFLARED_VERSION"
echo ""

# Step 2: Authenticate (if not already authenticated)
echo "2. Authenticating with Cloudflare..."
if [ -f "$HOME/.cloudflared/cert.pem" ]; then
    echo "✓ Already authenticated (cert.pem exists)"
else
    echo ""
    echo "Opening browser for authentication..."
    echo "(Log into your Cloudflare account and authorize access)"
    cloudflared tunnel login

    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        echo "✓ Authentication successful"
    else
        echo "❌ Authentication failed"
        exit 1
    fi
fi
echo ""

# Step 3: Create tunnel
echo "3. Creating Cloudflare Tunnel..."
read -p "Enter tunnel name (e.g., pi-hybrid): " TUNNEL_NAME

if [ -z "$TUNNEL_NAME" ]; then
    echo "❌ Tunnel name cannot be empty"
    exit 1
fi

# Check if tunnel already exists
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "⚠️  Tunnel '$TUNNEL_NAME' already exists"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    echo "Tunnel ID: $TUNNEL_ID"
else
    echo "Creating tunnel..."
    cloudflared tunnel create "$TUNNEL_NAME"

    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    echo ""
    echo "✓ Tunnel created successfully!"
    echo "Tunnel ID: $TUNNEL_ID"
fi
echo ""

# Step 4: Configure tunnel
echo "4. Configuring tunnel..."
sudo mkdir -p /etc/cloudflared

if [ -f "/etc/cloudflared/config.yml" ]; then
    echo "⚠️  Configuration file already exists"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping configuration..."
        echo ""
        echo "Manual configuration required:"
        echo "  sudo nano /etc/cloudflared/config.yml"
        echo ""
    else
        # Copy template and replace tunnel ID
        cp cloudflared-config.yml /tmp/cloudflared-config.yml
        sed -i "s/YOUR_TUNNEL_ID/$TUNNEL_ID/g" /tmp/cloudflared-config.yml
        sudo cp /tmp/cloudflared-config.yml /etc/cloudflared/config.yml
        rm /tmp/cloudflared-config.yml
        echo "✓ Configuration file created"
    fi
else
    # Copy template and replace tunnel ID
    cp cloudflared-config.yml /tmp/cloudflared-config.yml
    sed -i "s/YOUR_TUNNEL_ID/$TUNNEL_ID/g" /tmp/cloudflared-config.yml
    sudo cp /tmp/cloudflared-config.yml /etc/cloudflared/config.yml
    rm /tmp/cloudflared-config.yml
    echo "✓ Configuration file created at /etc/cloudflared/config.yml"
fi
echo ""

# Copy credentials file to expected location
CRED_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"
if [ -f "$CRED_FILE" ]; then
    sudo cp "$CRED_FILE" /root/.cloudflared/ 2>/dev/null || true
    echo "✓ Credentials file copied to /root/.cloudflared/"
else
    echo "⚠️  Warning: Credentials file not found at $CRED_FILE"
    echo "You may need to manually copy it to /root/.cloudflared/$TUNNEL_ID.json"
fi
echo ""

# Step 5: Route DNS
echo "5. Routing DNS through tunnel..."
echo ""
echo "You need to route your domains through this tunnel."
echo "Example commands:"
echo ""
echo "  # charn.io services"
echo "  cloudflared tunnel route dns $TUNNEL_NAME homer.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME nextcloud.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME jellyfin.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME grafana.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME prometheus.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME wallabag.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME home.charn.io"
echo "  cloudflared tunnel route dns $TUNNEL_NAME k8s.charn.io"
echo ""
echo "  # charno.net services"
echo "  cloudflared tunnel route dns $TUNNEL_NAME charno.net"
echo "  cloudflared tunnel route dns $TUNNEL_NAME www.charno.net"
echo ""
read -p "Route all domains now? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Routing domains..."

    # Route charn.io services
    cloudflared tunnel route dns "$TUNNEL_NAME" homer.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" nextcloud.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" jellyfin.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" grafana.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" prometheus.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" wallabag.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" home.charn.io
    cloudflared tunnel route dns "$TUNNEL_NAME" k8s.charn.io

    # Route charno.net services
    cloudflared tunnel route dns "$TUNNEL_NAME" charno.net
    cloudflared tunnel route dns "$TUNNEL_NAME" www.charno.net

    echo ""
    echo "✓ DNS routes configured"
fi
echo ""

# Step 6: Test configuration
echo "6. Testing tunnel configuration..."
echo ""
echo "Starting tunnel in test mode (Ctrl+C to stop)..."
echo "Watch for 'Connection registered' messages"
echo ""
read -p "Press Enter to start test..."

sudo cloudflared tunnel --config /etc/cloudflared/config.yml run "$TUNNEL_NAME" &
TEST_PID=$!

sleep 10

# Check if still running
if kill -0 $TEST_PID 2>/dev/null; then
    echo ""
    echo "✓ Tunnel is running"
    echo ""

    # Stop test
    sudo kill $TEST_PID
    sleep 2
else
    echo ""
    echo "❌ Tunnel failed to start"
    echo "Check logs above for errors"
    exit 1
fi

# Step 7: Install as service
echo "7. Installing tunnel as system service..."
read -p "Install as systemd service? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Stop existing service if running
    sudo systemctl stop cloudflared 2>/dev/null || true

    # Install service
    sudo cloudflared service install

    # Start service
    sudo systemctl start cloudflared

    # Enable on boot
    sudo systemctl enable cloudflared

    echo ""
    echo "✓ Service installed and started"
    echo ""

    # Check status
    sleep 3
    sudo systemctl status cloudflared --no-pager
fi
echo ""

# Summary
echo "════════════════════════════════════════════════════"
echo "  ✅ Cloudflare Tunnel Installation Complete!"
echo "════════════════════════════════════════════════════"
echo ""
echo "Tunnel Information:"
echo "  Name: $TUNNEL_NAME"
echo "  ID: $TUNNEL_ID"
echo "  Config: /etc/cloudflared/config.yml"
echo "  Credentials: /root/.cloudflared/$TUNNEL_ID.json"
echo ""
echo "Useful Commands:"
echo "  sudo systemctl status cloudflared"
echo "  sudo systemctl restart cloudflared"
echo "  sudo journalctl -u cloudflared -f"
echo "  cloudflared tunnel list"
echo "  cloudflared tunnel info $TUNNEL_NAME"
echo ""
echo "Next Steps:"
echo "  1. Verify tunnel is connected: sudo systemctl status cloudflared"
echo "  2. Check DNS records in Cloudflare dashboard"
echo "  3. Configure Nginx Ingress (if not done)"
echo "  4. Deploy applications with ingress resources"
echo "  5. Test external access: https://homer.charn.io"
echo ""
echo "Troubleshooting:"
echo "  • If tunnel won't start: sudo journalctl -u cloudflared -n 50"
echo "  • Verify credentials file exists and has correct tunnel ID"
echo "  • Check config.yml has correct tunnel ID"
echo "  • Ensure Nginx Ingress is running on port 30280"
echo ""
