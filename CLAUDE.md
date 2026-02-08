# CLAUDE.md

## Project overview

Pizza Map Tracker — a static GitHub Pages site that displays pizza places on a Leaflet map backed by a Supabase database. Users can browse, filter, and add pizza entries through a browser UI. No build step, no bundler, no framework.

## Tech stack

- **Frontend**: Vanilla HTML/CSS/JS (no framework, no build tool)
- **Map**: Leaflet 1.9.4 with OpenStreetMap tiles
- **Database**: Supabase (PostgreSQL + REST API via `@supabase/supabase-js` v2)
- **Hosting**: GitHub Pages (static files served from repo root)
- **Taxonomy**: JSON-based pizza style/attribute classification in `taxonomy/`

## File structure

```
index.html          — Single-page app entry point
app.js              — All application logic (IIFE, ~243 lines)
styles.css          — Dark-theme CSS, grid layout, responsive at 980px breakpoint
config.example.js   — Template for Supabase credentials (copy to config.js)
config.js           — (gitignored) Actual Supabase URL + anon key
taxonomy/
  taxonomy.json     — Machine-readable styles and attribute tags (used by UI)
  styles.md         — Human-readable style definitions
  attributes.md     — Human-readable attribute tag list
  overview.md       — How to classify a pizza
supabase/
  schema.sql        — Table definition for `pizzas` (UUID PK, geo fields, jsonb attributes)
  policies.sql      — RLS policies: public read + public insert, no update/delete
SECURITY.md         — Notes on hardening (moderation queue, auth, anti-spam)
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

RLS is enabled: anonymous users can SELECT and INSERT but cannot UPDATE or DELETE.

## Architecture notes

- `app.js` is a single async IIFE — no modules, no imports, no exports
- All state lives in the `allRows` array; filtering and rendering happen client-side
- The map click handler auto-fills lat/lng inputs for the add form
- HTML escaping (`escapeHtml`, `escapeAttr`) is applied to all user-supplied content rendered in the DOM
- Taxonomy styles populate three `<select>` elements (filter, primary, secondary)
- Supabase queries are limited to 500 rows ordered by `created_at desc`

## Testing

No test suite exists. Manual testing only — open in browser and verify map loads, filters work, and form submission inserts into Supabase.

## Common tasks

- **Add a pizza style**: Add an entry to `taxonomy/taxonomy.json` under `styles` and document it in `taxonomy/styles.md`
- **Add an attribute tag**: Add to the `attributes` array in `taxonomy/taxonomy.json` and document in `taxonomy/attributes.md`
- **Change default map location**: Edit `DEFAULT_CENTER` and `DEFAULT_ZOOM` in `config.js`
- **Modify the DB schema**: Update `supabase/schema.sql`, run the migration in Supabase SQL Editor, and update `app.js` if new columns are needed
