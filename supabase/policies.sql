-- RLS policies (EASY MODE: public read + public insert)
-- Enable RLS:
alter table public.pizzas enable row level security;

-- Allow anyone to read
drop policy if exists "public read pizzas" on public.pizzas;
create policy "public read pizzas"
on public.pizzas
for select
to anon
using (true);

-- Allow anyone to insert (spam risk)
drop policy if exists "public insert pizzas" on public.pizzas;
create policy "public insert pizzas"
on public.pizzas
for insert
to anon
with check (true);

-- No public updates/deletes (keeps vandalism down a bit)
