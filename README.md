# Pizza Map Tracker (GitHub Pages + Supabase + Leaflet)

This is a static GitHub Pages site that shows pizza places on a map and lets users add new entries to a shared database.

## What you get
- A Leaflet map (OpenStreetMap tiles)
- A list + map markers loaded from a Supabase table
- A simple “Add a pizza” form that inserts into the database
- A starter taxonomy for pizza styles and attributes

## Quick start (10–15 minutes)

### 1) Create the Supabase project
1. Create a project at Supabase.
2. In **SQL Editor**, run the schema in `supabase/schema.sql`.
3. In **Table Editor**, confirm table `pizzas` exists.

### 2) Set Row Level Security (RLS) policy
This starter repo is set up for **public insert + public read** (so anyone can add entries).
- In Supabase, go to **Authentication → Policies** (or **Database → Tables → pizzas → RLS**).
- Enable RLS on the `pizzas` table.
- Run the policies in `supabase/policies.sql`.

If you want safer options, see `SECURITY.md` for alternatives (moderation, CAPTCHA, allow-list, etc.).

### 3) Configure keys
1. Copy `config.example.js` to `config.js`
2. Fill in:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

Important: This repo assumes the anon key is okay to expose (Supabase is designed for this with RLS).
Do not put service-role keys in the client.

### 4) Publish on GitHub Pages
1. Create a new GitHub repo and upload these files.
2. Go to **Settings → Pages**.
3. Set Source to **Deploy from a branch**, branch `main`, folder `/ (root)`.
4. Visit your Pages URL.

## Data model (pizzas)
Each entry has:
- place_name, address, city, state
- latitude, longitude
- style_primary (from taxonomy)
- style_secondary (optional)
- attributes (JSON array of tags)
- rating (1–10)
- price_level (1–4)
- notes
- created_at, created_by (optional)

## Taxonomy
See `taxonomy/`:
- `taxonomy/styles.md` — style definitions
- `taxonomy/attributes.md` — attribute tags (crust/cheese/sauce/bake)
- `taxonomy/taxonomy.json` — machine-readable version used by the UI

## Local preview
Because this is static, you can open `index.html` directly.
If your browser blocks module fetches, run a tiny server:

```bash
python -m http.server 8000
```

Then open http://localhost:8000

---

If you want, you can add:
- photo uploads (Supabase Storage)
- “visited” tracking per user
- moderation queue (write to `submissions` table, admins approve to `pizzas`)
