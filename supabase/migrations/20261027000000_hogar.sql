-- Fase 0: perfiles, hogares, miembros e invitaciones.
--
-- Reglas que siguen todas las migraciones:
--   * RLS activado en todas las tablas y denegado por defecto.
--   * El rol anon no tiene ningún permiso sobre tablas ni funciones.
--   * Las funciones que saltan RLS (security definer) viven en el esquema
--     `private`, que la API no expone, o comprueban auth.uid() ellas mismas.

-- Tipos ---------------------------------------------------------------------

create type public.member_role as enum ('owner', 'member');
create type public.invite_status as enum ('pending', 'accepted', 'revoked');
create type public.app_theme as enum ('system', 'light', 'dark');

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- updated_at automático ------------------------------------------------------

create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Tablas --------------------------------------------------------------------

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  base_currency char(3) not null default 'EUR' check (base_currency ~ '^[A-Z]{3}$'),
  month_start_day smallint not null default 1 check (month_start_day between 1 and 28),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9._-]{3,30}$'),
  display_name text check (char_length(display_name) <= 60),
  avatar_url text check (char_length(avatar_url) <= 500),
  theme public.app_theme not null default 'system',
  default_household_id uuid references public.households (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null default 'member',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, user_id)
);

create index household_members_user_id_idx on public.household_members (user_id);

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  -- Mismo alfabeto que InviteCode en STMCore: sin 0, O, 1, I ni L.
  code text not null unique check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$'),
  invited_by uuid references public.profiles (id) on delete set null,
  accepted_by uuid references public.profiles (id) on delete set null,
  status public.invite_status not null default 'pending',
  expires_at timestamptz not null default now() + interval '48 hours',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index household_invites_household_id_idx on public.household_invites (household_id);

create trigger households_touch before update on public.households
  for each row execute function private.touch_updated_at();
create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger household_members_touch before update on public.household_members
  for each row execute function private.touch_updated_at();
create trigger household_invites_touch before update on public.household_invites
  for each row execute function private.touch_updated_at();

-- Ayudantes para las políticas (saltan RLS para no entrar en bucle) -------

create function private.is_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = target_household and m.user_id = (select auth.uid())
  );
$$;

create function private.is_owner(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
  );
$$;

create function private.shares_household(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_members mine
    join public.household_members theirs on theirs.household_id = mine.household_id
    where mine.user_id = (select auth.uid()) and theirs.user_id = other_user
  );
$$;

grant usage on schema private to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on function private.is_member(uuid), private.is_owner(uuid), private.shares_household(uuid)
  to authenticated;

-- Perfil al registrarse --------------------------------------------------------

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1))),
    nullif(new.raw_user_meta_data ->> 'display_name', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- RLS ---------------------------------------------------------------------------

alter table public.households enable row level security;
alter table public.profiles enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;

revoke all on public.households, public.profiles, public.household_members, public.household_invites
  from anon, authenticated;

-- households: lo ven sus miembros; sólo el dueño lo cambia o lo borra.
-- Se crea con create_household() para dar de alta al dueño a la vez.
grant select, update (name, base_currency, month_start_day), delete on public.households to authenticated;

create policy households_select on public.households
  for select to authenticated
  using ((select private.is_member(id)));

create policy households_update on public.households
  for update to authenticated
  using ((select private.is_owner(id)))
  with check ((select private.is_owner(id)));

create policy households_delete on public.households
  for delete to authenticated
  using ((select private.is_owner(id)));

-- profiles: cada uno ve el suyo y el de quien comparte hogar; sólo edita el suyo.
grant select, update (display_name, avatar_url, theme, default_household_id) on public.profiles to authenticated;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.shares_household(id)));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (
    id = (select auth.uid())
    and (default_household_id is null or (select private.is_member(default_household_id)))
  );

-- household_members: se ven los del propio hogar. Se entra con accept_invite();
-- uno puede salir y el dueño puede echar a otros.
grant select, delete on public.household_members to authenticated;

create policy household_members_select on public.household_members
  for select to authenticated
  using ((select private.is_member(household_id)));

create policy household_members_delete on public.household_members
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select private.is_owner(household_id)));

-- household_invites: las ven y las revocan los miembros. Se crean con
-- create_invite() y se aceptan con accept_invite(): quien no es miembro
-- nunca puede listar códigos.
grant select, update (status) on public.household_invites to authenticated;

create policy household_invites_select on public.household_invites
  for select to authenticated
  using ((select private.is_member(household_id)));

create policy household_invites_revoke on public.household_invites
  for update to authenticated
  using ((select private.is_member(household_id)) and status = 'pending')
  with check (status = 'revoked');

-- Funciones de la API ---------------------------------------------------------

create function public.create_household(household_name text)
returns public.households
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  created public.households;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  insert into public.households (name, created_by)
  values (trim(household_name), uid)
  returning * into created;

  insert into public.household_members (household_id, user_id, role)
  values (created.id, uid, 'owner');

  update public.profiles
  set default_household_id = created.id
  where id = uid and default_household_id is null;

  return created;
end;
$$;

create function public.create_invite(target_household uuid)
returns public.household_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
  created public.household_invites;
  attempt int := 0;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_member(target_household) then
    raise exception 'not a member of this household' using errcode = '42501';
  end if;

  loop
    attempt := attempt + 1;
    -- Bytes aleatorios criptográficos, no random().
    select string_agg(substr(alphabet, (get_byte(b, i) % 31) + 1, 1), '' order by i)
    into new_code
    from (select extensions.gen_random_bytes(6) as b) bytes, generate_series(0, 5) as i;

    begin
      insert into public.household_invites (household_id, code, invited_by)
      values (target_household, new_code, uid)
      returning * into created;
      return created;
    exception when unique_violation then
      if attempt >= 5 then
        raise;
      end if;
    end;
  end loop;
end;
$$;

create function public.accept_invite(invite_code text)
returns public.households
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  invite public.household_invites;
  joined public.households;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into invite
  from public.household_invites
  where code = upper(replace(replace(trim(invite_code), ' ', ''), '-', ''))
  for update;

  -- Un único mensaje para código inexistente, usado, revocado o caducado:
  -- así no se puede averiguar qué códigos existen.
  if invite.id is null or invite.status <> 'pending' or invite.expires_at <= now() then
    raise exception 'invalid or expired invite' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.household_members
    where household_id = invite.household_id and user_id = uid
  ) then
    raise exception 'already a member' using errcode = '23505';
  end if;

  insert into public.household_members (household_id, user_id, role)
  values (invite.household_id, uid, 'member');

  update public.household_invites
  set status = 'accepted', accepted_by = uid
  where id = invite.id;

  update public.profiles
  set default_household_id = invite.household_id
  where id = uid and default_household_id is null;

  select * into joined from public.households where id = invite.household_id;
  return joined;
end;
$$;

revoke all on function public.create_household(text), public.create_invite(uuid), public.accept_invite(text)
  from public, anon;
grant execute on function public.create_household(text), public.create_invite(uuid), public.accept_invite(text)
  to authenticated;
