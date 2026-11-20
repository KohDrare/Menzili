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
