#!/usr/bin/env bash
set -euo pipefail

# Pizza Map Tracker — Tailscale deployment script
# Run on your always-on machine (Ubuntu/Debian)
#
# Usage:
#   chmod +x deploy/setup.sh
#   sudo ./deploy/setup.sh
#
# What this does:
#   1. Installs Tailscale (if not already installed)
#   2. Installs a lightweight static file server (Python 3)
#   3. Creates a systemd service for always-on serving on port 8000
#   4. Configures `tailscale serve` to expose port 8000 as HTTPS on your tailnet

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="pizza-tracker"
PORT=8000

echo "==> Pizza Map Tracker — Tailscale Deployment"
echo "    App directory: $APP_DIR"
echo ""

# --- 1. Install Tailscale if missing ---
if ! command -v tailscale &>/dev/null; then
    echo "==> Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "==> Tailscale already installed: $(tailscale version | head -1)"
fi

# --- 2. Ensure Tailscale is running and authenticated ---
if ! tailscale status &>/dev/null; then
    echo ""
    echo "==> Tailscale is not connected. Starting authentication..."
    echo "    Follow the link below to log in:"
    echo ""
    tailscale up
fi

TAILSCALE_HOSTNAME=$(tailscale status --self --json | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null || echo "your-machine.tailnet-name.ts.net")
echo "==> Tailscale connected as: $TAILSCALE_HOSTNAME"

# --- 3. Check for config.js ---
if [ ! -f "$APP_DIR/config.js" ]; then
    echo ""
    echo "WARNING: config.js not found."
    echo "  Copy config.example.js to config.js and add your Supabase credentials:"
    echo "    cp $APP_DIR/config.example.js $APP_DIR/config.js"
    echo "    nano $APP_DIR/config.js"
    echo ""
fi

# --- 4. Create systemd service for the static server ---
echo "==> Creating systemd service: $SERVICE_NAME"
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Pizza Map Tracker static file server
After=network.target tailscaled.service

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 -m http.server $PORT --bind 127.0.0.1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
echo "==> Static server running on 127.0.0.1:$PORT"

# --- 5. Configure tailscale serve ---
echo "==> Configuring tailscale serve (HTTPS on tailnet -> localhost:$PORT)"
tailscale serve --bg https / http://127.0.0.1:${PORT}

echo ""
echo "============================================"
echo "  DONE!"
echo ""
echo "  Your pizza tracker is live at:"
echo "    https://$TAILSCALE_HOSTNAME"
echo ""
echo "  Only devices on your Tailscale network"
echo "  can reach this URL."
echo ""
echo "  Useful commands:"
echo "    systemctl status $SERVICE_NAME   # check server"
echo "    tailscale serve status            # check serve config"
echo "    journalctl -u $SERVICE_NAME -f    # view logs"
echo "============================================"
