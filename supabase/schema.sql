-- =====================================================================
--  Menzïli — comptes clients (Supabase)
--  À exécuter une fois dans Supabase > SQL Editor
-- =====================================================================

-- Profil du client (1 ligne par compte)
create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  name        text,
  phone       text,
  service     text,        -- service à Saint-Pierre
  location    text,        -- étage / local
  staff       boolean default false,
  updated_at  timestamptz default now()
);

-- Historique des commandes
create table if not exists public.orders (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  num         text not null,           -- ex. M482 (numéro affiché au client)
  mode        text,                    -- emporter | livraison
  when_label  text,                    -- ex. "Aujourd'hui · 12:30"
  total       numeric(10,2),
  items       jsonb not null,
  created_at  timestamptz default now()
);
create index if not exists orders_user_created on public.orders (user_id, created_at desc);

-- Sécurité : chaque client ne voit et ne modifie QUE ses propres données
alter table public.profiles enable row level security;
alter table public.orders   enable row level security;

drop policy if exists "profil perso" on public.profiles;
create policy "profil perso" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "commandes perso lecture" on public.orders;
create policy "commandes perso lecture" on public.orders
  for select using (auth.uid() = user_id);

drop policy if exists "commandes perso ajout" on public.orders;
create policy "commandes perso ajout" on public.orders
  for insert with check (auth.uid() = user_id);

drop policy if exists "commandes perso suppression" on public.orders;
create policy "commandes perso suppression" on public.orders
  for delete using (auth.uid() = user_id);
