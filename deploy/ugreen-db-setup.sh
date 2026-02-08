#!/usr/bin/env bash
set -euo pipefail

# Pizza Map Tracker — Database setup for ugreen NAS
# Run ON the ugreen (via SSH or directly)
#
# This installs a self-hosted Supabase (PostgreSQL + PostgREST + GoTrue)
# via Docker Compose, accessible only over the Tailscale network.
#
# Usage:
#   chmod +x deploy/ugreen-db-setup.sh
#   sudo ./deploy/ugreen-db-setup.sh

SUPABASE_DIR="/opt/pizza-tracker-db"
TAILSCALE_IP="100.112.53.44"
TAILSCALE_DNS="ugreen.tail0e7f9c.ts.net"

echo "==> Pizza Map Tracker — Database Setup (ugreen)"
echo ""

# --- 1. Check Docker ---
if ! command -v docker &>/dev/null; then
    echo "==> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "==> Docker installed."
else
    echo "==> Docker already installed: $(docker --version)"
fi

if ! command -v docker compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    echo "ERROR: docker compose (v2) not found. Install Docker Compose v2."
    exit 1
fi

# --- 2. Generate secrets ---
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 40
}

JWT_SECRET=$(generate_secret)
ANON_KEY=""  # Will be generated below
SERVICE_KEY="" # Will be generated below
POSTGRES_PASSWORD=$(generate_secret)
DASHBOARD_PASSWORD=$(generate_secret)

echo "==> Generated database secrets."

# --- 3. Create project directory ---
mkdir -p "$SUPABASE_DIR"

# --- 4. Generate JWT tokens using Python (no extra deps needed) ---
# Supabase needs specific JWT tokens with role claims
python3 - "$JWT_SECRET" <<'PYEOF' > "$SUPABASE_DIR/jwt_tokens.env"
import hmac, hashlib, base64, json, sys, time

secret = sys.argv[1]

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def make_jwt(payload, secret):
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload_b64 = b64url(json.dumps(payload).encode())
    sig_input = f"{header}.{payload_b64}".encode()
    sig = b64url(hmac.new(secret.encode(), sig_input, hashlib.sha256).digest())
    return f"{header}.{payload_b64}.{sig}"

# 10-year expiry
exp = int(time.time()) + (10 * 365 * 24 * 3600)

anon = make_jwt({"role": "anon", "iss": "supabase", "iat": int(time.time()), "exp": exp}, secret)
service = make_jwt({"role": "service_role", "iss": "supabase", "iat": int(time.time()), "exp": exp}, secret)

print(f"ANON_KEY={anon}")
print(f"SERVICE_ROLE_KEY={service}")
PYEOF

# shellcheck source=/dev/null
source "$SUPABASE_DIR/jwt_tokens.env"
echo "==> Generated JWT tokens."

# --- 5. Write .env file ---
cat > "$SUPABASE_DIR/.env" <<EOF
# --- Secrets (auto-generated — keep safe) ---
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}

# --- Networking (Tailscale only) ---
# Bind to Tailscale IP so only tailnet devices can reach the DB
API_EXTERNAL_URL=http://${TAILSCALE_DNS}:8000
SUPABASE_PUBLIC_URL=http://${TAILSCALE_DNS}:8000

# Kong (API gateway) listens on port 8000
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

# Studio (admin dashboard) on port 3000
STUDIO_PORT=3000

# --- Postgres ---
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

# --- Site URL (the piserver frontend) ---
SITE_URL=https://piserver.tail0e7f9c.ts.net
EOF

echo "==> Wrote $SUPABASE_DIR/.env"

# --- 6. Write docker-compose.yml ---
cat > "$SUPABASE_DIR/docker-compose.yml" <<'COMPOSEFILE'
# Self-hosted Supabase — minimal set for Pizza Map Tracker
# Based on https://supabase.com/docs/guides/self-hosting/docker

services:
  db:
    image: supabase/postgres:15.6.1.145
    restart: unless-stopped
    ports:
      - "${TAILSCALE_IP:-0.0.0.0}:5432:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  rest:
    image: postgrest/postgrest:v12.2.3
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB:-postgres}
      PGRST_DB_SCHEMAS: public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: "false"

  auth:
    image: supabase/gotrue:v2.158.1
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: ${API_EXTERNAL_URL}
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB:-postgres}
      GOTRUE_SITE_URL: ${SITE_URL}
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_JWT_EXP: 3600
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_EXTERNAL_EMAIL_ENABLED: "false"
      GOTRUE_MAILER_AUTOCONFIRM: "true"

  kong:
    image: kong:2.8.1
    restart: unless-stopped
    ports:
      - "${TAILSCALE_IP:-0.0.0.0}:${KONG_HTTP_PORT:-8000}:8000"
      - "${TAILSCALE_IP:-0.0.0.0}:${KONG_HTTPS_PORT:-8443}:8443"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl
      KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: 160k
      KONG_NGINX_PROXY_PROXY_BUFFERS: 64 160k
    volumes:
      - ./kong.yml:/var/lib/kong/kong.yml:ro
    depends_on:
      - rest
      - auth

  studio:
    image: supabase/studio:20240422-5cf8f30
    restart: unless-stopped
    ports:
      - "${TAILSCALE_IP:-0.0.0.0}:${STUDIO_PORT:-3000}:3000"
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: "Pizza Tracker"
      DEFAULT_PROJECT_NAME: "pizza-tracker"
      SUPABASE_URL: http://kong:8000
      SUPABASE_PUBLIC_URL: ${SUPABASE_PUBLIC_URL}
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}
    depends_on:
      - kong
      - meta

  meta:
    image: supabase/postgres-meta:v0.83.2
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: ${POSTGRES_DB:-postgres}
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}

volumes:
  pgdata:
COMPOSEFILE

# --- 7. Write Kong config (API gateway routing) ---
cat > "$SUPABASE_DIR/kong.yml" <<'KONGYML'
_format_version: "2.1"
_transform: true

consumers:
  - username: anon
    keyauth_credentials:
      - key: ${ANON_KEY_PLACEHOLDER}
  - username: service_role
    keyauth_credentials:
      - key: ${SERVICE_KEY_PLACEHOLDER}

acls:
  - consumer: anon
    group: anon
  - consumer: service_role
    group: admin

services:
  - name: rest-v1
    url: http://rest:3000/
    routes:
      - name: rest-v1
        strip_path: true
        paths:
          - /rest/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
          key_names:
            - apikey
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - anon
            - admin

  - name: auth-v1
    url: http://auth:9999/
    routes:
      - name: auth-v1
        strip_path: true
        paths:
          - /auth/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
          key_names:
            - apikey
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - anon
            - admin
KONGYML

# Replace placeholder keys in kong.yml with actual values
sed -i "s|\${ANON_KEY_PLACEHOLDER}|${ANON_KEY}|g" "$SUPABASE_DIR/kong.yml"
sed -i "s|\${SERVICE_KEY_PLACEHOLDER}|${SERVICE_ROLE_KEY}|g" "$SUPABASE_DIR/kong.yml"

# --- 8. Create init SQL (schema + RLS + roles) ---
mkdir -p "$SUPABASE_DIR/init"
cat > "$SUPABASE_DIR/init/00-roles.sql" <<'ROLESQL'
-- Create roles needed by PostgREST and GoTrue
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT CREATEROLE;
  END IF;
END
$$;

-- Grant schema access
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- Auth admin needs superuser-like access to auth schema
ALTER ROLE supabase_auth_admin SET search_path = auth, public;
ROLESQL

# Copy the pizza schema + policies
cat > "$SUPABASE_DIR/init/01-schema.sql" <<'SCHEMASQL'
-- Pizza Map Tracker schema
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.pizzas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_name text NOT NULL,
  address text,
  city text,
  state text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  style_primary text NOT NULL,
  style_secondary text,
  attributes jsonb NOT NULL DEFAULT '[]'::jsonb,
  rating integer,
  price_level integer,
  notes text,
  source_url text,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pizzas_created_at_idx ON public.pizzas (created_at DESC);

-- RLS
ALTER TABLE public.pizzas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public read pizzas" ON public.pizzas;
CREATE POLICY "public read pizzas"
ON public.pizzas FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "public insert pizzas" ON public.pizzas;
CREATE POLICY "public insert pizzas"
ON public.pizzas FOR INSERT TO anon WITH CHECK (true);
SCHEMASQL

echo "==> Wrote Docker Compose and init SQL to $SUPABASE_DIR"

# --- 9. Bind services to Tailscale IP only ---
# Update docker-compose to use the actual tailscale IP
export TAILSCALE_IP
sed -i "s|\${TAILSCALE_IP:-0.0.0.0}|${TAILSCALE_IP}|g" "$SUPABASE_DIR/docker-compose.yml"

# --- 10. Start services ---
echo "==> Starting Supabase services (this may take a few minutes on first run)..."
cd "$SUPABASE_DIR"
docker compose up -d

echo ""
echo "==> Waiting for services to become healthy..."
sleep 10

# Check if API is responding
if curl -sf "http://${TAILSCALE_IP}:8000/rest/v1/" -H "apikey: ${ANON_KEY}" -o /dev/null 2>/dev/null; then
    echo "==> API is responding!"
else
    echo "==> API may still be starting. Check: docker compose -f $SUPABASE_DIR/docker-compose.yml logs"
fi

echo ""
echo "============================================"
echo "  DATABASE SETUP COMPLETE!"
echo ""
echo "  Supabase API:    http://${TAILSCALE_DNS}:8000"
echo "  Supabase Studio: http://${TAILSCALE_DNS}:3000"
echo "  PostgreSQL:      ${TAILSCALE_DNS}:5432"
echo ""
echo "  For your config.js on the piserver:"
echo "    SUPABASE_URL:      http://${TAILSCALE_DNS}:8000"
echo "    SUPABASE_ANON_KEY: ${ANON_KEY}"
echo ""
echo "  Credentials saved to: $SUPABASE_DIR/.env"
echo "  Admin dashboard password: ${DASHBOARD_PASSWORD}"
echo ""
echo "  ALL ports are bound to Tailscale IP only —"
echo "  not reachable from the public internet."
echo "============================================"

# --- 11. Save frontend config snippet ---
cat > "$SUPABASE_DIR/config-snippet.js" <<CFGEOF
// Paste this into config.js on the piserver
window.PIZZA_APP_CONFIG = {
  SUPABASE_URL: "http://${TAILSCALE_DNS}:8000",
  SUPABASE_ANON_KEY: "${ANON_KEY}",
  DEFAULT_CENTER: [26.7153, -80.0534],
  DEFAULT_ZOOM: 11
};
CFGEOF

echo ""
echo "Config snippet also saved to: $SUPABASE_DIR/config-snippet.js"
