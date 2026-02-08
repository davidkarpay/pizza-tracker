-- Schema for Pizza Map Tracker

create extension if not exists pgcrypto;

create table if not exists public.pizzas (
  id uuid primary key default gen_random_uuid(),
  place_name text not null,
  address text,
  city text,
  state text,
  latitude double precision not null,
  longitude double precision not null,
  style_primary text not null,
  style_secondary text,
  attributes jsonb not null default '[]'::jsonb,
  rating integer,
  price_level integer,
  notes text,
  source_url text,
  created_by text,
  created_at timestamptz not null default now()
);

-- Helpful index for geo-ish bounding box queries (still client-side here)
create index if not exists pizzas_created_at_idx on public.pizzas (created_at desc);
