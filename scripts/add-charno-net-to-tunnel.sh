#!/bin/bash
# Add charno.net domains to Cloudflare Tunnel
# Run this on your Cloudflare Tunnel server (pi@192.168.0.23)

set -e

TUNNEL_ID="4e94af33-e120-45da-bbdc-2c0b0bb3ab78"
CONFIG_FILE="/etc/cloudflared/config.yml"

echo "========================================="
echo "Add charno.net domains to Cloudflare Tunnel"
echo "========================================="
echo ""

# Check if running on tunnel server
if ! command -v cloudflared &> /dev/null; then
    echo "ERROR: cloudflared not found"
    echo "This script must be run on your Cloudflare Tunnel server"
    echo ""
    echo "To run this script:"
    echo "  1. Copy it to your Pi: scp scripts/add-charno-net-to-tunnel.sh pi@192.168.0.23:~/"
    echo "  2. SSH to Pi: ssh pi@192.168.0.23"
    echo "  3. Run as root: sudo bash ~/add-charno-net-to-tunnel.sh"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo"
    echo "Usage: sudo bash $0"
    exit 1
fi

echo "Step 1: Adding DNS records to Cloudflare Tunnel..."
echo ""

# Add DNS routes for charno.net domains
cloudflared tunnel route dns "$TUNNEL_ID" charno.net
cloudflared tunnel route dns "$TUNNEL_ID" www.charno.net
cloudflared tunnel route dns "$TUNNEL_ID" lod.charno.net

echo "✓ DNS records added"
echo ""

echo "Step 2: Backing up current config..."
echo ""

cp "$CONFIG_FILE" "${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
echo "✓ Backup created"
echo ""

echo "Step 3: Checking if charno.net is already in config..."
echo ""

if grep -q "hostname: charno.net" "$CONFIG_FILE"; then
    echo "✓ charno.net already exists in config - skipping"
else
    echo "Adding charno.net entries to config..."

    # Find the line with the catch-all rule
    CATCH_ALL_LINE=$(grep -n "service: http_status:404" "$CONFIG_FILE" | cut -d: -f1)

    if [ -z "$CATCH_ALL_LINE" ]; then
        echo "ERROR: Could not find catch-all rule in config"
        exit 1
    fi

    # Insert before catch-all rule
    INSERT_LINE=$((CATCH_ALL_LINE - 1))

    # Create temp file with new entries
    {
        head -n "$INSERT_LINE" "$CONFIG_FILE"
        cat << 'EOF'
  # charno.net - Personal website
  - hostname: charno.net
    service: http://localhost:30280
    originRequest:
      httpHostHeader: charno.net
      noTLSVerify: false

  - hostname: www.charno.net
    service: http://localhost:30280
    originRequest:
      httpHostHeader: www.charno.net
      noTLSVerify: false

  # lod.charno.net - Linked Open Data Service
  - hostname: lod.charno.net
    service: http://localhost:30280
    originRequest:
      httpHostHeader: lod.charno.net
      noTLSVerify: false

EOF
        tail -n +"$((INSERT_LINE + 1))" "$CONFIG_FILE"
    } > "${CONFIG_FILE}.new"

    mv "${CONFIG_FILE}.new" "$CONFIG_FILE"

    echo "✓ Config file updated"
fi

echo ""

echo "Step 4: Validating config..."
echo ""

cloudflared tunnel ingress validate

echo "✓ Config validated"
echo ""

echo "Step 5: Restarting cloudflared service..."
echo ""

systemctl restart cloudflared
sleep 2
systemctl status cloudflared --no-pager

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "DNS records added:"
echo "  ✓ charno.net"
echo "  ✓ www.charno.net"
echo "  ✓ lod.charno.net"
echo ""
echo "All domains now route to:"
echo "  → http://localhost:30280 (nginx-ingress)"
echo "  → charno-frontend (charno.net, www.charno.net)"
echo "  → linked-data-service (lod.charno.net)"
echo ""
echo "Wait 1-2 minutes for DNS propagation, then test:"
echo "  https://charno.net"
echo "  https://www.charno.net"
echo "  https://lod.charno.net"
echo ""
echo "========================================="
