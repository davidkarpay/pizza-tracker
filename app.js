/* global L, supabase, window */
(async function () {
  const cfg = window.PIZZA_APP_CONFIG;
  const msgEl = document.getElementById("formMsg");
  const resultsEl = document.getElementById("results");
  const resultsMetaEl = document.getElementById("resultsMeta");

  function setMsg(text, isError=false) {
    msgEl.textContent = text || "";
    msgEl.style.color = isError ? "#fca5a5" : "#9ca3af";
  }

  if (!cfg || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
    setMsg("Missing config.js. Copy config.example.js → config.js and add Supabase URL + anon key.", true);
    return;
  }

  // Load taxonomy
  const taxonomy = await fetch("taxonomy/taxonomy.json").then(r => r.json());
  const styleFilter = document.getElementById("styleFilter");
  const stylePrimary = document.getElementById("stylePrimary");
  const styleSecondary = document.getElementById("styleSecondary");

  function populateStyleSelect(selectEl, includeAllOption=false) {
    if (includeAllOption) {
      // already has "All"
    } else {
      selectEl.innerHTML = "";
    }
    taxonomy.styles.forEach(s => {
      const opt = document.createElement("option");
      opt.value = s.id;
      opt.textContent = s.label;
      selectEl.appendChild(opt);
    });
  }
  populateStyleSelect(styleFilter, true);
  populateStyleSelect(stylePrimary, false);
  // secondary: keep first option "None"
  taxonomy.styles.forEach(s => {
    const opt = document.createElement("option");
    opt.value = s.id;
    opt.textContent = s.label;
    styleSecondary.appendChild(opt);
  });

  // Supabase client
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

  // Map
  const map = L.map("map").setView(cfg.DEFAULT_CENTER, cfg.DEFAULT_ZOOM);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  const markersLayer = L.layerGroup().addTo(map);
  let allRows = [];

  // Click-to-fill lat/lng
  map.on("click", (e) => {
    document.getElementById("latInput").value = e.latlng.lat.toFixed(6);
    document.getElementById("lngInput").value = e.latlng.lng.toFixed(6);
    setMsg("Lat/Lng filled from map click.");
  });

  function labelForStyle(id) {
    const hit = taxonomy.styles.find(s => s.id === id);
    return hit ? hit.label : id;
  }

  function normalizeAttributes(input) {
    if (!input) return [];
    return input
      .split(",")
      .map(s => s.trim())
      .filter(Boolean)
      .map(s => s.replace(/\s+/g, "_"));
  }

  function matchesFilters(row) {
    const style = styleFilter.value;
    const q = (document.getElementById("searchBox").value || "").toLowerCase().trim();
    const minRating = document.getElementById("minRating").value;

    if (style && row.style_primary !== style) return false;
    if (minRating && typeof row.rating === "number" && row.rating < Number(minRating)) return false;
    if (minRating && row.rating == null) return false;

    if (q) {
      const blob = [
        row.place_name, row.address, row.city, row.state,
        row.notes, row.style_primary, row.style_secondary,
        Array.isArray(row.attributes) ? row.attributes.join(" ") : ""
      ].filter(Boolean).join(" ").toLowerCase();
      if (!blob.includes(q)) return false;
    }
    return true;
  }

  function render() {
    markersLayer.clearLayers();
    resultsEl.innerHTML = "";

    const rows = allRows.filter(matchesFilters);
    resultsMetaEl.textContent = `${rows.length} result(s)`;

    rows.forEach(row => {
      const m = L.marker([row.latitude, row.longitude]).addTo(markersLayer);
      const popup = `
        <div>
          <strong>${escapeHtml(row.place_name)}</strong><br/>
          <span>${escapeHtml([row.address, row.city, row.state].filter(Boolean).join(", "))}</span><br/>
          <span>${escapeHtml(labelForStyle(row.style_primary))}${row.style_secondary ? " • " + escapeHtml(labelForStyle(row.style_secondary)) : ""}</span><br/>
          ${row.rating != null ? `<span>Rating: ${row.rating}/10</span><br/>` : ""}
          ${row.source_url ? `<a href="${escapeAttr(row.source_url)}" target="_blank" rel="noreferrer">Link</a><br/>` : ""}
          ${row.notes ? `<div style="margin-top:6px">${escapeHtml(row.notes)}</div>` : ""}
        </div>
      `;
      m.bindPopup(popup);

      const card = document.createElement("div");
      card.className = "card";
      card.innerHTML = `
        <div class="name">${escapeHtml(row.place_name)}</div>
        <div class="line">${escapeHtml([row.city, row.state].filter(Boolean).join(", "))}</div>
        <div class="line">${escapeHtml(labelForStyle(row.style_primary))}${row.style_secondary ? " • " + escapeHtml(labelForStyle(row.style_secondary)) : ""}</div>
        ${row.rating != null ? `<div class="line">Rating: ${row.rating}/10</div>` : ""}
        <div>
          ${(Array.isArray(row.attributes) ? row.attributes : []).slice(0, 10).map(a => `<span class="badge">${escapeHtml(a)}</span>`).join("")}
        </div>
      `;
      card.addEventListener("click", () => {
        map.setView([row.latitude, row.longitude], Math.max(map.getZoom(), 14));
        m.openPopup();
      });
      resultsEl.appendChild(card);
    });
  }

  function escapeHtml(s) {
    return String(s ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }
  function escapeAttr(s) {
    return String(s ?? "").replaceAll('"', "&quot;");
  }

  async function loadPizzas() {
    setMsg("Loading pizzas…");
    const { data, error } = await sb
      .from("pizzas")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(500);

    if (error) {
      setMsg("Error loading pizzas: " + error.message, true);
      return;
    }
    // Supabase returns jsonb as object/array already; ensure attributes is array
    allRows = (data || []).map(r => ({
      ...r,
      attributes: Array.isArray(r.attributes) ? r.attributes : (r.attributes ? [String(r.attributes)] : [])
    }));
    setMsg("");
    render();
  }

  // Filters re-render
  ["styleFilter", "searchBox", "minRating"].forEach(id => {
    document.getElementById(id).addEventListener("input", render);
  });

  // Form submit
  const form = document.getElementById("addForm");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    setMsg("");

    const fd = new FormData(form);
    const place_name = (fd.get("place_name") || "").toString().trim();
    const latitude = Number(fd.get("latitude"));
    const longitude = Number(fd.get("longitude"));
    const style_primary = (fd.get("style_primary") || "").toString();
    const style_secondary = (fd.get("style_secondary") || "").toString() || null;

    if (!place_name || Number.isNaN(latitude) || Number.isNaN(longitude) || !style_primary) {
      setMsg("Missing required fields (place name, latitude, longitude, primary style).", true);
      return;
    }

    const payload = {
      place_name,
      address: (fd.get("address") || "").toString().trim() || null,
      city: (fd.get("city") || "").toString().trim() || null,
      state: (fd.get("state") || "").toString().trim().toUpperCase() || null,
      latitude,
      longitude,
      style_primary,
      style_secondary,
      attributes: normalizeAttributes((fd.get("attributes") || "").toString()),
      rating: fd.get("rating") ? Number(fd.get("rating")) : null,
      price_level: fd.get("price_level") ? Number(fd.get("price_level")) : null,
      notes: (fd.get("notes") || "").toString().trim() || null,
      source_url: (fd.get("source_url") || "").toString().trim() || null
    };

    // Basic sanity
    if (payload.rating != null && (payload.rating < 1 || payload.rating > 10)) {
      setMsg("Rating must be 1–10.", true);
      return;
    }
    if (payload.price_level != null && (payload.price_level < 1 || payload.price_level > 4)) {
      setMsg("Price level must be 1–4.", true);
      return;
    }

    const btn = document.getElementById("submitBtn");
    btn.disabled = true;
    btn.textContent = "Adding…";

    const { error } = await sb.from("pizzas").insert(payload);
    if (error) {
      setMsg("Insert failed: " + error.message, true);
      btn.disabled = false;
      btn.textContent = "Add to map";
      return;
    }

    form.reset();
    setMsg("Added. Reloading list…");
    btn.disabled = false;
    btn.textContent = "Add to map";
    await loadPizzas();
  });

  await loadPizzas();
})();
