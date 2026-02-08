# Deploying Pizza Map Tracker on Tailscale

Serve the pizza tracker on your private Tailscale network — only devices on your tailnet can access it.

## Prerequisites

- An always-on machine (home server, Raspberry Pi, VPS, etc.) running Ubuntu/Debian
- A [Tailscale account](https://tailscale.com) (free for personal use, up to 100 devices)
- Python 3 (pre-installed on most Linux distros)
- Your Supabase credentials (URL + anon key)

## Quick start

```bash
# 1. Clone the repo on your server
git clone <your-repo-url> ~/pizza-tracker
cd ~/pizza-tracker

# 2. Add your Supabase credentials
cp config.example.js config.js
nano config.js   # fill in SUPABASE_URL and SUPABASE_ANON_KEY

# 3. Run the setup script
sudo ./deploy/setup.sh
```

The script will:
1. Install Tailscale (if not present) and prompt you to authenticate
2. Create a systemd service that runs a Python static file server on `127.0.0.1:8000`
3. Configure `tailscale serve` to expose that as HTTPS on your tailnet

When done, you'll see your URL: `https://<machine-name>.<tailnet>.ts.net`

## Inviting friends and family

**Option A: Share your tailnet (simplest)**
1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/users)
2. Invite users by email — they install Tailscale on their device and join your network
3. They can immediately access `https://<machine-name>.<tailnet>.ts.net`

**Option B: Use Tailscale Funnel (public URL, limited access)**
If someone can't install Tailscale, you can use [Funnel](https://tailscale.com/kb/1223/funnel) to expose the site publicly — but this removes the network-level restriction. Only use this if you add app-level auth.

## Restricting access with ACLs

For tighter control, edit your [Tailscale ACL policy](https://login.tailscale.com/admin/acls) to limit who can reach this machine:

```jsonc
{
  "acls": [
    {
      // Allow the pizza-viewers group to reach the server on port 443
      "action": "accept",
      "src": ["group:pizza-viewers"],
      "dst": ["tag:pizza-server:443"]
    }
  ],
  "groups": {
    "group:pizza-viewers": [
      "alice@example.com",
      "bob@example.com"
    ]
  },
  "tagOwners": {
    "tag:pizza-server": ["autogroup:admin"]
  }
}
```

Then tag your server: `tailscale up --advertise-tags=tag:pizza-server`

## Managing the service

```bash
# Check status
systemctl status pizza-tracker
tailscale serve status

# View logs
journalctl -u pizza-tracker -f

# Restart after code changes
systemctl restart pizza-tracker

# Stop serving
tailscale serve --remove /
systemctl stop pizza-tracker

# Uninstall
systemctl disable pizza-tracker
rm /etc/systemd/system/pizza-tracker.service
systemctl daemon-reload
```
