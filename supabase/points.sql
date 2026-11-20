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
