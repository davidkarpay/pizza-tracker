# Deploying Pizza Map Tracker on your Tailscale network

Private deployment for friends and family — all traffic stays on your Tailscale mesh.

## Architecture

```
┌─────────────────┐     Tailscale      ┌──────────────────────┐
│  davids-macbook  │◄──── mesh ────────►│  piserver (Pi)       │
│  + phones/guests │    encrypted       │  static web server   │
│                  │                    │  tailscale serve     │
└─────────────────┘                    │  https://piserver.   │
                                       │   tail0e7f9c.ts.net  │
                                       └──────────┬───────────┘
                                                  │ Tailscale
                                       ┌──────────▼───────────┐
                                       │  ugreen (NAS)        │
                                       │  self-hosted Supabase│
                                       │  PostgreSQL + API    │
                                       │  http://ugreen.      │
                                       │   tail0e7f9c.ts.net  │
                                       │   :8000 (API)        │
                                       │   :3000 (Studio)     │
                                       │   :5432 (Postgres)   │
                                       └──────────────────────┘
```

| Machine | Role | Tailscale hostname |
|---------|------|--------------------|
| **piserver** | Web server (static files + tailscale serve) | piserver.tail0e7f9c.ts.net |
| **ugreen** | Database (self-hosted Supabase via Docker) | ugreen.tail0e7f9c.ts.net |
| **davids-macbook-air** | Dev machine + browser | davids-macbook-air.tail0e7f9c.ts.net |
| **iphone-15-pro** | Mobile browser + SSH client | iphone-15-pro.tail0e7f9c.ts.net |

## One-command deploy (from your Mac)

```bash
cd pizza-tracker
./deploy/deploy.sh
```

This SSHs into both machines and sets everything up. You'll be prompted for passwords.

Default SSH user is `david` for both machines. Override if needed:
```bash
UGREEN_USER=other PISERVER_USER=other ./deploy/deploy.sh
```

### Deploy from your iPhone

SSH to your Mac first, then run the deploy from there:
```bash
ssh davidluciankarpay@davids-macbook-air.tail0e7f9c.ts.net
cd ~/pizza-tracker
./deploy/deploy.sh
```

Or run each machine directly from any SSH client on your phone:
```bash
# 1. Database
ssh david@ugreen.tail0e7f9c.ts.net
sudo /tmp/ugreen-db-setup.sh
# Note the ANON_KEY

# 2. Web server
ssh david@piserver.tail0e7f9c.ts.net
sudo /tmp/piserver-setup.sh THE_ANON_KEY
```

## Manual deploy (step by step)

### Step 1: Database on ugreen

SSH to the ugreen and run:
```bash
ssh david@ugreen.tail0e7f9c.ts.net

# Copy the script there (or git clone the repo)
sudo ./deploy/ugreen-db-setup.sh
```

This will:
1. Install Docker if needed
2. Generate all secrets (JWT, Postgres password, anon key)
3. Start Supabase (PostgreSQL + PostgREST + Kong + Studio) via Docker Compose
4. Bind all ports to the Tailscale IP only (not reachable from LAN or internet)
5. Create the `pizzas` table with RLS policies
6. Print the `ANON_KEY` you need for the next step

Credentials are saved to `/opt/pizza-tracker-db/.env` on the ugreen.

### Step 2: Web server on piserver

SSH to the piserver and run:
```bash
ssh david@piserver.tail0e7f9c.ts.net

# Copy the repo there (or scp the files)
sudo ./deploy/piserver-setup.sh YOUR_ANON_KEY_FROM_STEP_1
```

This will:
1. Copy app files to `/opt/pizza-tracker`
2. Generate `config.js` pointing at the ugreen database
3. Create a systemd service for the Python static file server
4. Configure `tailscale serve` for HTTPS

### Step 3: Open in browser

From any device on your tailnet:
```
https://piserver.tail0e7f9c.ts.net
```

Admin dashboard (Supabase Studio):
```
http://ugreen.tail0e7f9c.ts.net:3000
```

## Inviting friends and family

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/users)
2. Invite by email
3. They install Tailscale on their phone/laptop
4. They open `https://piserver.tail0e7f9c.ts.net`

No accounts, no passwords — if they're on your tailnet, they're in.

### Restricting access with ACLs

For tighter control, edit your [Tailscale ACL policy](https://login.tailscale.com/admin/acls):

```jsonc
{
  "acls": [
    {
      // Pizza crew can reach piserver (web) and ugreen (API)
      "action": "accept",
      "src": ["group:pizza-crew"],
      "dst": [
        "piserver:443",
        "ugreen:8000"
      ]
    }
  ],
  "groups": {
    "group:pizza-crew": [
      "alice@example.com",
      "bob@example.com"
    ]
  }
}
```

## Managing the deployment

### piserver (web)
```bash
ssh david@piserver.tail0e7f9c.ts.net

systemctl status pizza-tracker      # check web server
journalctl -u pizza-tracker -f      # view logs
systemctl restart pizza-tracker     # restart after file changes
tailscale serve status              # check tailscale serve
```

### ugreen (database)
```bash
ssh david@ugreen.tail0e7f9c.ts.net

cd /opt/pizza-tracker-db
docker compose ps                   # check all services
docker compose logs -f              # view logs
docker compose restart              # restart everything
docker compose down                 # stop everything
docker compose up -d                # start everything

# Connect to Postgres directly
docker compose exec db psql -U postgres
```

### Updating the app
```bash
# From your Mac:
scp app.js styles.css index.html david@piserver.tail0e7f9c.ts.net:/opt/pizza-tracker/
ssh david@piserver.tail0e7f9c.ts.net "sudo systemctl restart pizza-tracker"
```

## Security notes

- All services on ugreen are bound to the Tailscale IP (`100.112.53.44`), not `0.0.0.0`
- No ports are exposed to your local LAN or the internet
- The piserver serves only over `tailscale serve` (HTTPS, tailnet-only)
- Database credentials live in `/opt/pizza-tracker-db/.env` on the ugreen
- RLS is enabled: anonymous reads + inserts only, no updates/deletes
- Since this is friends-and-family only, spam risk is effectively zero
