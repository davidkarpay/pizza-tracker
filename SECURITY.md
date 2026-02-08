# Security notes (read this)

This starter repo supports *public read + public insert* so anyone can add pizzas.
That is convenient, but it is also abusable (spam, vandalism).

Safer patterns:
1) Moderation queue:
   - Public inserts go to a `submissions` table.
   - Only an admin process (or authenticated admins) can move records into `pizzas`.
2) Authentication required:
   - Users must sign in (email magic link, OAuth).
   - RLS only allows inserts by authenticated users.
3) Anti-spam controls:
   - Add hCaptcha/Cloudflare Turnstile on the client.
   - Add a rate limit table keyed by IP hash (requires edge function or gateway).
4) Allow-list:
   - Only allow inserts from a known set of users.

For GitHub Pages (pure static hosting), option (1) or (2) is usually the most realistic.

This repo ships with (0) “easy mode” and includes SQL policies for that mode in `supabase/policies.sql`.
