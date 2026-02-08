// Copy this file to config.js and fill in your Supabase details.
// config.js is gitignored to avoid accidentally committing keys.
//
// For self-hosted Supabase on your Tailscale network:
//   SUPABASE_URL: "http://ugreen.tail0e7f9c.ts.net:8000"
//   SUPABASE_ANON_KEY: (from /opt/pizza-tracker-db/.env on ugreen)
//
// For Supabase Cloud:
//   SUPABASE_URL: "https://YOUR-PROJECT.supabase.co"
//   SUPABASE_ANON_KEY: (from Supabase dashboard)

window.PIZZA_APP_CONFIG = {
  SUPABASE_URL: "http://ugreen.tail0e7f9c.ts.net:8000",
  SUPABASE_ANON_KEY: "YOUR_SUPABASE_ANON_KEY",
  // Default map center (change to your city)
  DEFAULT_CENTER: [26.7153, -80.0534], // West Palm Beach, FL
  DEFAULT_ZOOM: 11
};
