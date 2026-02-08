#!/usr/bin/env bash
set -euo pipefail

# Pizza Map Tracker — Web server setup for piserver (Raspberry Pi)
# Run ON the piserver (via SSH or directly)
#
# Serves the static site via Python and exposes it over Tailscale.
# The database lives on the ugreen — this script just serves the frontend.
#
# Usage:
#   sudo ./deploy/piserver-setup.sh [SUPABASE_ANON_KEY]
#
# If SUPABASE_ANON_KEY is provided, config.js is auto-generated.

APP_DIR="/opt/pizza-tracker"
SERVICE_NAME="pizza-tracker"
PORT=8000

UGREEN_DNS="ugreen.tail0e7f9c.ts.net"
UGREEN_API_PORT=8000
PISERVER_DNS="piserver.tail0e7f9c.ts.net"

ANON_KEY="${1:-}"

echo "==> Pizza Map Tracker — Web Server Setup (piserver)"
echo ""

# --- 1. Install dependencies ---
if ! command -v python3 &>/dev/null; then
    echo "==> Installing Python 3..."
    apt-get update -qq && apt-get install -y -qq python3
fi

if ! command -v git &>/dev/null; then
    echo "==> Installing git..."
    apt-get update -qq && apt-get install -y -qq git
fi

# --- 2. Ensure Tailscale is running ---
if ! command -v tailscale &>/dev/null; then
    echo "==> Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale status &>/dev/null; then
    echo "==> Tailscale is not connected. Run: tailscale up"
    echo "    Then re-run this script."
    exit 1
fi

echo "==> Tailscale connected as: $(tailscale status --self --json | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null || echo "$PISERVER_DNS")"

# --- 3. Copy app files ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Copying app files to $APP_DIR..."
mkdir -p "$APP_DIR"
# Copy only the frontend files (not deploy scripts, not .git)
for f in index.html app.js styles.css config.example.js taxonomy; do
    cp -r "$REPO_DIR/$f" "$APP_DIR/"
done

# --- 4. Generate config.js ---
if [ -n "$ANON_KEY" ]; then
    echo "==> Generating config.js with provided anon key..."
    cat > "$APP_DIR/config.js" <<CFGEOF
window.PIZZA_APP_CONFIG = {
  SUPABASE_URL: "http://${UGREEN_DNS}:${UGREEN_API_PORT}",
  SUPABASE_ANON_KEY: "${ANON_KEY}",
  DEFAULT_CENTER: [26.7153, -80.0534],
  DEFAULT_ZOOM: 11
};
CFGEOF
elif [ -f "$REPO_DIR/config.js" ]; then
    cp "$REPO_DIR/config.js" "$APP_DIR/config.js"
    echo "==> Copied existing config.js"
elif [ -f "$APP_DIR/config.js" ]; then
    echo "==> Using existing config.js in $APP_DIR"
else
    echo ""
    echo "WARNING: No config.js and no anon key provided."
    echo "  After running ugreen-db-setup.sh, re-run this with the anon key:"
    echo "    sudo ./deploy/piserver-setup.sh YOUR_ANON_KEY"
    echo ""
    echo "  Or manually create $APP_DIR/config.js"
    echo ""
fi

# --- 5. Create systemd service ---
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

# --- 6. Configure tailscale serve ---
echo "==> Configuring tailscale serve (HTTPS -> localhost:$PORT)"
tailscale serve --bg https / http://127.0.0.1:${PORT}

echo ""
echo "============================================"
echo "  WEB SERVER SETUP COMPLETE!"
echo ""
echo "  Pizza Tracker is live at:"
echo "    https://${PISERVER_DNS}"
echo ""
echo "  Database (ugreen):  http://${UGREEN_DNS}:${UGREEN_API_PORT}"
echo "  App files:          $APP_DIR"
echo ""
echo "  Only Tailscale devices can access this."
echo ""
echo "  Useful commands:"
echo "    systemctl status $SERVICE_NAME"
echo "    tailscale serve status"
echo "    journalctl -u $SERVICE_NAME -f"
echo "============================================"
