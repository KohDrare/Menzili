-- =====================================================================
--  Menzïli — INSTALLATION COMPLÈTE (nouveau projet Supabase)
--  = schema.sql + points.sql + commandes.sql, dans le bon ordre.
--  À coller en entier dans Supabase > SQL Editor, puis Run. Ré-exécutable sans risque.
-- =====================================================================



-- ############################ schema.sql ############################

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


-- ############################ points.sql ############################

-- =====================================================================
--  Menzïli — système de points (QR client scanné par le personnel)
--  À exécuter une fois dans Supabase > SQL Editor (après schema.sql)
--  Ré-exécutable sans risque.
-- =====================================================================

-- 1) Le personnel autorisé à scanner (rempli UNIQUEMENT par toi, ici dans Supabase)
--    Les clients ne peuvent ni lire la liste ni s'y ajouter.
create table if not exists public.team (
  user_id    uuid primary key references auth.users on delete cascade,
  name       text not null,               -- affiché dans l'historique (ex. « Karim »)
  created_at timestamptz default now()
);

-- 2) Mouvements de points : +12 après une commande, −50 pour un soft offert…
create table if not exists public.points_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users on delete cascade,  -- le client
  delta      integer not null check (delta between -1000 and 1000 and delta <> 0),
  reason     text,
  by_user    uuid references auth.users on delete set null,          -- qui a scanné
  created_at timestamptz default now()
);
create index if not exists points_ledger_user on public.points_ledger (user_id, created_at desc);

-- 3) QR temporaires : le QR du client change toutes les quelques minutes,
--    une capture d'écran ne marche donc pas longtemps.
create table if not exists public.qr_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users on delete cascade,
  expires_at timestamptz not null
);
create index if not exists qr_tokens_user on public.qr_tokens (user_id);

alter table public.team          enable row level security;
alter table public.points_ledger enable row level security;
alter table public.qr_tokens     enable row level security;

-- Le client lit SES mouvements. Personne n'écrit directement : tout passe par les fonctions ci-dessous.
drop policy if exists "points perso lecture" on public.points_ledger;
create policy "points perso lecture" on public.points_ledger
  for select using (auth.uid() = user_id);
-- (aucune policy sur team et qr_tokens : inaccessibles en direct)

-- ---------------------------------------------------------------------
--  Fonctions (security definer = s'exécutent avec les droits du serveur,
--  mais vérifient elles-mêmes qui appelle)
-- ---------------------------------------------------------------------

-- Suis-je du personnel ?
create or replace function public.is_team() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team where user_id = auth.uid());
$$;

-- Mon solde
create or replace function public.my_points() returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(sum(delta), 0)::int from points_ledger where user_id = auth.uid();
$$;

-- Nouveau QR pour le client connecté (valable 10 minutes)
create or replace function public.my_qr_token() returns text
language plpgsql volatile security definer set search_path = public as $$
declare t text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  delete from qr_tokens where user_id = auth.uid() or expires_at < now();
  t := '';
  for i in 1..9 loop
    t := t || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  insert into qr_tokens(token, user_id, expires_at) values (t, auth.uid(), now() + interval '10 minutes');
  return t;
end $$;

-- Personnel : retrouver le client d'un QR
create or replace function public.team_lookup(p_token text)
returns table (name text, points integer, since timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid;
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  select q.user_id into uid from qr_tokens q
   where q.token = upper(regexp_replace(p_token, '[^A-Za-z0-9]', '', 'g')) and q.expires_at > now();
  if uid is null then raise exception 'QR inconnu ou expiré'; end if;
  return query
    select coalesce(nullif(p.name, ''), 'Client'),
           (select coalesce(sum(delta), 0)::int from points_ledger l where l.user_id = uid),
           u.created_at
      from auth.users u left join profiles p on p.id = u.id
     where u.id = uid;
end $$;

-- Personnel : ajouter (delta > 0) ou retirer (delta < 0) des points. Renvoie le nouveau solde.
create or replace function public.team_add_points(p_token text, p_delta integer, p_reason text)
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid; bal int;
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  if p_delta = 0 or p_delta not between -1000 and 1000 then raise exception 'montant invalide'; end if;
  select q.user_id into uid from qr_tokens q
   where q.token = upper(regexp_replace(p_token, '[^A-Za-z0-9]', '', 'g')) and q.expires_at > now();
  if uid is null then raise exception 'QR inconnu ou expiré'; end if;
  select coalesce(sum(delta), 0)::int into bal from points_ledger where user_id = uid;
  if bal + p_delta < 0 then raise exception 'pas assez de points'; end if;
  insert into points_ledger(user_id, delta, reason, by_user) values (uid, p_delta, left(p_reason, 80), auth.uid());
  return bal + p_delta;
end $$;

-- Personnel : derniers mouvements (pour vérifier / annuler une erreur de frappe)
create or replace function public.team_recent()
returns table (id bigint, client text, delta integer, reason text, by_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  return query
    select l.id, coalesce(nullif(p.name, ''), 'Client'), l.delta, l.reason, coalesce(t.name, '?'), l.created_at
      from points_ledger l
      left join profiles p on p.id = l.user_id
      left join team t on t.user_id = l.by_user
     where l.created_at > now() - interval '2 days'
     order by l.created_at desc limit 20;
end $$;

-- Personnel : annuler un mouvement fait il y a moins de 15 minutes (erreur de saisie)
create or replace function public.team_undo(p_id bigint) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  delete from points_ledger where id = p_id and created_at > now() - interval '15 minutes';
  if not found then raise exception 'trop tard pour annuler'; end if;
end $$;

-- Droits d'appel : uniquement les comptes connectés
revoke all on function public.is_team(), public.my_points(), public.my_qr_token(),
  public.team_lookup(text), public.team_add_points(text, integer, text), public.team_recent(),
  public.team_undo(bigint) from public, anon;
grant execute on function public.is_team(), public.my_points(), public.my_qr_token(),
  public.team_lookup(text), public.team_add_points(text, integer, text), public.team_recent(),
  public.team_undo(bigint) to authenticated;

-- =====================================================================
--  AJOUTER UNE PERSONNE DU PERSONNEL (à refaire pour chaque employé)
--  1. La personne se connecte une fois sur le site (Mon profil) avec son e-mail.
--  2. Remplace l'e-mail et le prénom ci-dessous, puis exécute ces 2 lignes :
--
--  insert into public.team (user_id, name)
--  select id, 'Prénom' from auth.users where email = 'adresse@exemple.be'
--  on conflict (user_id) do update set name = excluded.name;
--
--  Retirer quelqu'un :  delete from public.team where user_id = (select id from auth.users where email = 'adresse@exemple.be');
-- =====================================================================


-- ############################ commandes.sql ############################

-- =====================================================================
--  Menzïli — commandes en ligne reçues dans l'espace personnel (/staff/)
--  À exécuter une fois dans Supabase > SQL Editor (après schema.sql et points.sql)
--  Ré-exécutable sans risque.
-- =====================================================================

create table if not exists public.shop_orders (
  id             bigint generated always as identity primary key,
  num            text not null,                 -- ex. M482, affiché au client et au comptoir
  track          text not null unique,          -- code secret du lien de suivi
  user_id        uuid references auth.users on delete set null,  -- vide si commande sans compte
  status         text not null default 'new'
                 check (status in ('new','prep','ready','done','cancelled')),
  mode           text not null check (mode in ('emporter','livraison')),
  day            date not null,                 -- jour de retrait / livraison
  slot           text,                          -- "12:30" ou "ASAP"
  when_label     text,
  name           text not null,
  phone          text not null,
  service        text,                          -- service à Saint-Pierre (livraison)
  location       text,
  note           text,
  staff_disc     boolean default false,         -- réduction personnel Saint-Pierre
  items          jsonb not null,
  subtotal       numeric(10,2) not null,
  discount       numeric(10,2) not null default 0,
  total          numeric(10,2) not null,
  points_awarded integer not null default 0,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now(),
  updated_by     uuid references auth.users on delete set null
);
create index if not exists shop_orders_day on public.shop_orders (day, created_at);
create index if not exists shop_orders_user on public.shop_orders (user_id, created_at desc);

alter table public.shop_orders enable row level security;

-- Le personnel voit toutes les commandes (nécessaire pour le temps réel), le client connecté voit les siennes.
drop policy if exists "commandes visibles par le personnel" on public.shop_orders;
create policy "commandes visibles par le personnel" on public.shop_orders
  for select to authenticated using (public.is_team());
drop policy if exists "commandes visibles par leur client" on public.shop_orders;
create policy "commandes visibles par leur client" on public.shop_orders
  for select to authenticated using (user_id is not null and user_id = auth.uid());
-- Aucune écriture directe : tout passe par les fonctions ci-dessous.

-- ---------------------------------------------------------------------
--  Passer une commande (avec ou sans compte)
-- ---------------------------------------------------------------------
create or replace function public.place_order(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name text := btrim(coalesce(p->>'name', ''));
  v_phone text := btrim(coalesce(p->>'phone', ''));
  v_mode text := coalesce(p->>'mode', '');
  v_items jsonb := coalesce(p->'items', '[]'::jsonb);
  v_total numeric := coalesce((p->>'total')::numeric, -1);
  v_day date := coalesce((p->>'day')::date, current_date);
  v_num text; v_track text; i int;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if length(v_name) not between 1 and 40 then raise exception 'prénom invalide'; end if;
  if length(regexp_replace(v_phone, '\D', '', 'g')) < 9 then raise exception 'téléphone invalide'; end if;
  if v_mode not in ('emporter','livraison') then raise exception 'mode invalide'; end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) not between 1 and 60 then raise exception 'panier invalide'; end if;
  if v_total < 0 or v_total > 2000 then raise exception 'total invalide'; end if;
  if v_day < current_date - 1 or v_day > current_date + 14 then raise exception 'jour invalide'; end if;
  if length(v_items::text) > 20000 then raise exception 'panier trop grand'; end if;
  -- anti-abus : 6 commandes max par numéro sur 10 minutes
  if (select count(*) from shop_orders where phone = v_phone and created_at > now() - interval '10 minutes') >= 6 then
    raise exception 'trop de commandes, réessaie dans quelques minutes';
  end if;

  -- numéro court unique sur le jour
  loop
    v_num := 'M' || (100 + floor(random() * 900))::int;
    exit when not exists (select 1 from shop_orders where num = v_num and day = v_day);
  end loop;
  v_track := '';
  for i in 1..14 loop
    v_track := v_track || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;

  insert into shop_orders (num, track, user_id, mode, day, slot, when_label, name, phone, service, location, note,
                           staff_disc, items, subtotal, discount, total)
  values (v_num, v_track, auth.uid(), v_mode, v_day, left(p->>'slot', 10), left(p->>'when', 60), v_name, left(v_phone, 30),
          left(nullif(btrim(coalesce(p->>'service','')), ''), 60), left(nullif(btrim(coalesce(p->>'location','')), ''), 80),
          left(nullif(btrim(coalesce(p->>'note','')), ''), 300), coalesce((p->>'staff')::boolean, false), v_items,
          coalesce((p->>'subtotal')::numeric, v_total), coalesce((p->>'discount')::numeric, 0), v_total);
  return jsonb_build_object('num', v_num, 'track', v_track);
end $$;

-- Suivi d'une commande via son lien (fonctionne sans compte)
create or replace function public.order_track(p_track text)
returns table (num text, status text, mode text, when_label text, total numeric, items jsonb, name text, created_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select num, status, mode, when_label, total, items, name, created_at, updated_at
    from shop_orders where track = p_track;
$$;

-- ---------------------------------------------------------------------
--  Personnel
-- ---------------------------------------------------------------------
-- Commandes à traiter : aujourd'hui, les pré-commandes à venir et celles des dernières 24 h
create or replace function public.team_orders()
returns setof public.shop_orders
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  return query select * from shop_orders
    where day >= current_date or created_at > now() - interval '24 hours'
    order by day, created_at;
end $$;

-- Changer le statut : new → prep → ready → done (ou cancelled)
create or replace function public.team_set_status(p_id bigint, p_status text)
returns public.shop_orders
language plpgsql volatile security definer set search_path = public as $$
declare r shop_orders;
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  if p_status not in ('new','prep','ready','done','cancelled') then raise exception 'statut invalide'; end if;
  update shop_orders set status = p_status, updated_at = now(), updated_by = auth.uid()
   where id = p_id returning * into r;
  if r.id is null then raise exception 'commande introuvable'; end if;
  return r;
end $$;

-- Donner les points d'une commande à son client (s'il a un compte), une seule fois
create or replace function public.team_award_order(p_id bigint, p_points integer)
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare r shop_orders;
begin
  if not is_team() then raise exception 'réservé au personnel'; end if;
  select * into r from shop_orders where id = p_id for update;
  if r.id is null then raise exception 'commande introuvable'; end if;
  if r.user_id is null then raise exception 'client sans compte'; end if;
  if r.points_awarded > 0 then return 0; end if;
  if p_points <= 0 or p_points > ceil(r.total * 5) then raise exception 'montant invalide'; end if;
  insert into points_ledger(user_id, delta, reason, by_user) values (r.user_id, p_points, 'Commande ' || r.num, auth.uid());
  update shop_orders set points_awarded = p_points where id = p_id;
  return p_points;
end $$;

revoke all on function public.place_order(jsonb), public.order_track(text), public.team_orders(),
  public.team_set_status(bigint, text), public.team_award_order(bigint, integer) from public;
grant execute on function public.place_order(jsonb), public.order_track(text) to anon, authenticated;
grant execute on function public.team_orders(), public.team_set_status(bigint, text),
  public.team_award_order(bigint, integer) to authenticated;
grant select on public.shop_orders to authenticated;

-- Temps réel : les nouvelles commandes arrivent instantanément dans l'espace personnel
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = 'shop_orders') then
    execute 'alter publication supabase_realtime add table public.shop_orders';
  end if;
end $$;
