# CLAUDE.md

## Project overview

Pizza Map Tracker — a static site that displays pizza places on a Leaflet map backed by a Supabase database. Users can browse, filter, and add pizza entries through a browser UI. No build step, no bundler, no framework.

Two deployment modes:
1. **GitHub Pages** — public, static hosting
2. **Tailscale private network** — friends-and-family deployment across a Pi web server and NAS-hosted Supabase (see `deploy/`)

## Tech stack

- **Frontend**: Vanilla HTML/CSS/JS (no framework, no build tool)
- **Map**: Leaflet 1.9.4 with OpenStreetMap tiles (loaded from CDN)
- **Database**: Supabase (PostgreSQL + REST API via `@supabase/supabase-js` v2, loaded from CDN)
- **Hosting**: GitHub Pages or Tailscale-served static files
- **Taxonomy**: JSON-based pizza style/attribute classification in `taxonomy/`

All dependencies are CDN-based. There is no `package.json`, no npm, and no install step.

## File structure

```
index.html            — Single-page app entry point
app.js                — All application logic (async IIFE, ~243 lines)
styles.css            — Dark-theme CSS, grid layout, responsive at 980px breakpoint
config.example.js     — Template for Supabase credentials (copy to config.js)
config.js             — (gitignored) Actual Supabase URL + anon key
README.md             — Quick start guide
CLAUDE.md             — This file
SECURITY.md           — Notes on hardening (moderation queue, auth, anti-spam)
taxonomy/
  taxonomy.json       — Machine-readable styles and attribute tags (used by UI)
  styles.md           — Human-readable style definitions (11 styles)
  attributes.md       — Human-readable attribute tag list (58 tags in 6 categories)
  overview.md         — How to classify a pizza
supabase/
  schema.sql          — Table definition for `pizzas` (UUID PK, geo fields, jsonb attributes)
  policies.sql        — RLS policies: public read + public insert, no update/delete
deploy/
  README.md           — Tailscale deployment guide (architecture, commands, management)
  deploy.sh           — Orchestrates full deployment from Mac to piserver + ugreen
  setup.sh            — Basic single-machine Tailscale setup
  piserver-setup.sh   — Web server setup (systemd + tailscale serve)
  ugreen-db-setup.sh  — Self-hosted Supabase via Docker Compose on NAS
```

## Local development

No install or build step required. Open `index.html` directly, or serve with:

```bash
python -m http.server 8000
```

The app requires a valid `config.js` with Supabase credentials to load data. Without it, a missing-config error displays in the form area.

## Configuration

Copy `config.example.js` to `config.js` and fill in:
- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_ANON_KEY` — the public anon key (safe to expose with RLS)
- `DEFAULT_CENTER` — `[lat, lng]` for initial map view (default: West Palm Beach, FL)
- `DEFAULT_ZOOM` — initial zoom level (default: 11)

`config.js` is gitignored. Never commit real keys.

## Database schema

Single table `pizzas` with columns: `id` (uuid), `place_name`, `address`, `city`, `state`, `latitude`, `longitude`, `style_primary`, `style_secondary`, `attributes` (jsonb array), `rating` (1-10), `price_level` (1-4), `notes`, `source_url`, `created_by`, `created_at`.

- Index on `created_at DESC` (`pizzas_created_at_idx`) for query ordering
- RLS is enabled: anonymous users can SELECT and INSERT but cannot UPDATE or DELETE

## Architecture notes

- `app.js` is a single async IIFE — no modules, no imports, no exports
- Global dependencies: `L` (Leaflet), `supabase` client, `window.PIZZA_APP_CONFIG`
- All state lives in the `allRows` array; filtering and rendering happen client-side
- The map click handler auto-fills lat/lng inputs for the add form
- HTML escaping (`escapeHtml`, `escapeAttr`) is applied to all user-supplied content rendered in the DOM
- Taxonomy styles populate three `<select>` elements (filter, primary, secondary)
- Supabase queries are limited to 500 rows ordered by `created_at desc`
- Attributes are normalized: spaces converted to underscores, comma-separated input

## Coding conventions

- **No frameworks or build tools** — keep everything as vanilla HTML/CSS/JS
- **Single-file architecture** — all JS logic stays in `app.js` as one IIFE; do not split into modules
- **XSS prevention** — always use `escapeHtml()` / `escapeAttr()` for any user-supplied content before DOM insertion
- **Dark theme** — CSS uses custom properties (`--bg`, `--panel`, `--text`, `--accent`, etc.); maintain the dark palette
- **Responsive layout** — grid layout with a media query breakpoint at 980px
- **HTML5 semantics** — use `<header>`, `<main>`, `<section>`, `<footer>`; include `role` and `aria-*` attributes for form feedback
- **No secrets in code** — Supabase credentials go in gitignored `config.js`; the anon key is safe to expose client-side only because RLS is enabled

## Security considerations

The default mode is "easy mode" — public read + public insert via Supabase RLS. See `SECURITY.md` for hardening options:

1. **Moderation queue** — inserts go to a `submissions` table, admins promote to `pizzas`
2. **Authentication required** — email magic links or OAuth, RLS limits inserts to authenticated users
3. **Anti-spam** — hCaptcha/Cloudflare Turnstile, rate limiting via edge functions
4. **Allow-list** — only known users can insert

For the Tailscale deployment, all services bind to the Tailscale IP only (not `0.0.0.0`), so nothing is exposed to LAN or internet.

## Testing

No test suite exists. Manual testing only — open in browser and verify map loads, filters work, and form submission inserts into Supabase.

## Common tasks

- **Add a pizza style**: Add an entry to `taxonomy/taxonomy.json` under `styles` and document it in `taxonomy/styles.md`
- **Add an attribute tag**: Add to the `attributes` array in `taxonomy/taxonomy.json` and document in `taxonomy/attributes.md`
- **Change default map location**: Edit `DEFAULT_CENTER` and `DEFAULT_ZOOM` in `config.js`
- **Modify the DB schema**: Update `supabase/schema.sql`, run the migration in Supabase SQL Editor, and update `app.js` if new columns are needed
- **Deploy to Tailscale network**: Run `./deploy/deploy.sh` from your Mac (see `deploy/README.md` for details)
- **Update deployed app**: `scp` changed files to piserver and restart the systemd service
