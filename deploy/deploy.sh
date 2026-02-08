#!/usr/bin/env bash
set -euo pipefail

# Pizza Map Tracker — Deploy from your Mac
# Orchestrates setup on both the ugreen (database) and piserver (web).
#
# Run from your MacBook (which is on the same Tailscale network):
#   ./deploy/deploy.sh
#
# Prerequisites:
#   - SSH access to both piserver and ugreen (password or key-based)
#   - Both machines connected to your Tailscale network
#   - Docker installed on ugreen (script will attempt to install if missing)

UGREEN_HOST="ugreen.tail0e7f9c.ts.net"
PISERVER_HOST="piserver.tail0e7f9c.ts.net"
UGREEN_USER="${UGREEN_USER:-david}"
PISERVER_USER="${PISERVER_USER:-david}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "  Pizza Map Tracker — Full Deployment"
echo "=========================================="
echo ""
echo "  Architecture:"
echo "    MacBook ──tailscale──> piserver (web)"
echo "                           │"
echo "                           └──tailscale──> ugreen (database)"
echo ""
echo "  ugreen:    ${UGREEN_USER}@${UGREEN_HOST}"
echo "  piserver:  ${PISERVER_USER}@${PISERVER_HOST}"
echo ""

# --- Connectivity check ---
echo "==> Checking Tailscale connectivity..."
for host in "$UGREEN_HOST" "$PISERVER_HOST"; do
    if ! ping -c 1 -W 3 "$host" &>/dev/null; then
        echo "ERROR: Cannot reach $host. Is Tailscale running?"
        exit 1
    fi
    echo "    $host — reachable"
done
echo ""

# ===================================================
# STEP 1: Set up the database on ugreen
# ===================================================
echo "==> STEP 1: Setting up database on ugreen..."
echo "    (You may be prompted for the SSH password)"
echo ""

# Copy the setup script to ugreen
scp "$SCRIPT_DIR/ugreen-db-setup.sh" "${UGREEN_USER}@${UGREEN_HOST}:/tmp/ugreen-db-setup.sh"

# Run it
ssh -t "${UGREEN_USER}@${UGREEN_HOST}" "chmod +x /tmp/ugreen-db-setup.sh && sudo /tmp/ugreen-db-setup.sh"

echo ""
echo "==> Fetching the generated anon key from ugreen..."
ANON_KEY=$(ssh "${UGREEN_USER}@${UGREEN_HOST}" "grep '^ANON_KEY=' /opt/pizza-tracker-db/.env | cut -d= -f2")

if [ -z "$ANON_KEY" ]; then
    echo "ERROR: Could not retrieve ANON_KEY from ugreen."
    echo "  Check if the setup completed: ssh ${UGREEN_USER}@${UGREEN_HOST} 'cat /opt/pizza-tracker-db/.env'"
    exit 1
fi
echo "    Got anon key: ${ANON_KEY:0:20}..."

# ===================================================
# STEP 2: Set up the web server on piserver
# ===================================================
echo ""
echo "==> STEP 2: Setting up web server on piserver..."
echo "    (You may be prompted for the SSH password)"
echo ""

# Create a tarball of the app files (excluding .git, deploy, config.js)
TMPTAR=$(mktemp /tmp/pizza-tracker-XXXX.tar.gz)
tar -czf "$TMPTAR" -C "$REPO_DIR" \
    --exclude='.git' \
    --exclude='config.js' \
    --exclude='pizza-map-tracker.zip' \
    .

# Copy files to piserver
scp "$TMPTAR" "${PISERVER_USER}@${PISERVER_HOST}:/tmp/pizza-tracker.tar.gz"
scp "$SCRIPT_DIR/piserver-setup.sh" "${PISERVER_USER}@${PISERVER_HOST}:/tmp/piserver-setup.sh"

# Extract and run setup
ssh -t "${PISERVER_USER}@${PISERVER_HOST}" bash -c "'
    mkdir -p /tmp/pizza-tracker-deploy
    tar -xzf /tmp/pizza-tracker.tar.gz -C /tmp/pizza-tracker-deploy
    chmod +x /tmp/pizza-tracker-deploy/deploy/piserver-setup.sh
    sudo /tmp/pizza-tracker-deploy/deploy/piserver-setup.sh \"${ANON_KEY}\"
    rm -rf /tmp/pizza-tracker-deploy /tmp/pizza-tracker.tar.gz /tmp/piserver-setup.sh
'"

rm -f "$TMPTAR"

# ===================================================
# STEP 3: Verify
# ===================================================
echo ""
echo "==> STEP 3: Verifying deployment..."

# Check ugreen API
if curl -sf "http://${UGREEN_HOST}:8000/rest/v1/" -H "apikey: ${ANON_KEY}" -o /dev/null 2>/dev/null; then
    echo "    ugreen API:  OK"
else
    echo "    ugreen API:  WAITING (may still be starting — try again in 30s)"
fi

# Check piserver web
if curl -sf "https://${PISERVER_HOST}" -o /dev/null 2>/dev/null; then
    echo "    piserver web: OK"
else
    echo "    piserver web: WAITING (may still be starting — try again in 30s)"
fi

echo ""
echo "============================================"
echo "  DEPLOYMENT COMPLETE!"
echo ""
echo "  Open in your browser:"
echo "    https://${PISERVER_HOST}"
echo ""
echo "  Supabase Studio (admin):"
echo "    http://${UGREEN_HOST}:3000"
echo ""
echo "  Only accessible from your Tailscale network."
echo ""
echo "  To invite friends/family:"
echo "    1. Go to https://login.tailscale.com/admin/users"
echo "    2. Invite by email"
echo "    3. They install Tailscale and can access the URL"
echo "============================================"
