-- ORC-56: qué pasa con los datos de quien deja de ser miembro de un hogar.
--
-- Hasta ahora sus filas se quedaban en la base sin que nadie pudiera verlas, exportarlas ni borrarlas
-- (private.is_mine exige ser el autor Y seguir siendo miembro). Regla decidida por el dueño el 2026-11-27:
--
--   * Sale por su cuenta      -> se borra todo lo suyo en ese hogar, en la misma operación.
--   * Lo quita otro (el dueño) -> sus datos se guardan 30 días para que pueda exportarlos; después se borran.
--                                 Durante esos días no es miembro: no ve ni cambia nada por las tablas, sólo
--                                 puede pedir la exportación (removed_household_export).
--   * Se borra el usuario      -> se borran todas sus filas (created_by pasa a on delete cascade).
--
-- Va en un trigger de household_members y no en una función nueva que las apps tengan que llamar: así
-- las versiones ya publicadas, que borran la fila de household_members directamente, siguen la misma regla
-- y no queda ningún camino que la salte.

-- 1. Borrar un usuario borra sus filas ------------------------------------------------------------

-- Antes: on delete set null. La fila se quedaba sin autor y private.is_mine era falso para todos.
-- households.created_by no se toca: el hogar no es de quien lo creó, es de sus miembros.
do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'categories', 'transactions', 'budgets', 'extra_budgets', 'recurring_series', 'recurring_charges',
    'goals', 'goal_contributions', 'holdings', 'holding_prices', 'investment_trades', 'investment_plans',
    'credit_cards', 'card_installments'
  ] loop
    execute format(
      'alter table public.%I drop constraint %I, add constraint %I foreign key (created_by) references auth.users (id) on delete cascade',
      t, t || '_created_by_fkey', t || '_created_by_fkey');
  end loop;
end;
$$;

-- 2. Quién ha sido quitado y cuándo -----------------------------------------------------------------

create table private.removed_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  removed_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

-- Para la purga diaria y para «mis hogares anteriores».
create index removed_members_removed_at_idx on private.removed_members (removed_at);
create index removed_members_user_id_idx on private.removed_members (user_id);

-- Sin políticas ni permisos: sólo la usan las funciones security definer de esta migración.
alter table private.removed_members enable row level security;
revoke all on table private.removed_members from public, anon, authenticated;

-- El único sitio donde está el plazo.
create function private.removed_until(removed_at timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select removed_at + interval '30 days';
$$;

revoke all on function private.removed_until(timestamptz) from public, anon, authenticated;

-- 3. Borrar todo lo de un usuario en un hogar -------------------------------------------------------

-- security definer: quien ya no es miembro no pasa el RLS de sus propias filas.
-- Nadie la llama desde la API: sólo los triggers y la purga de abajo.
create function private.purge_member_data(target_household uuid, target_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Primero lo que arrastra a sus hijos en cascada, en el orden de reset_household.
  delete from public.holdings where household_id = target_household and created_by = target_user;          -- precios, operaciones y planes
  delete from public.goals where household_id = target_household and created_by = target_user;             -- aportaciones
  delete from public.recurring_series where household_id = target_household and created_by = target_user;  -- cargos pendientes
  delete from public.extra_budgets where household_id = target_household and created_by = target_user;
  delete from public.budgets where household_id = target_household and created_by = target_user;           -- líneas
  delete from public.transactions where household_id = target_household and created_by = target_user;      -- plazos
  delete from public.accounts where household_id = target_household and created_by = target_user;          -- tarjetas
  delete from public.categories where household_id = target_household and created_by = target_user;

  -- Después, filas suyas que colgaran de algo de otro miembro. Desde la privacidad por usuario no se
  -- pueden crear, y el diagnóstico de ORC-63 no encontró ninguna en producción; se borran por si acaso.
  delete from public.goal_contributions where household_id = target_household and created_by = target_user;
  delete from public.holding_prices where household_id = target_household and created_by = target_user;
  delete from public.investment_plans where household_id = target_household and created_by = target_user;
  delete from public.recurring_charges where household_id = target_household and created_by = target_user;
  delete from public.card_installments where household_id = target_household and created_by = target_user;
  delete from public.credit_cards where household_id = target_household and created_by = target_user;
  begin
    delete from public.investment_trades where household_id = target_household and created_by = target_user;
  exception when sqlstate 'STM03' then
    -- Una compra suya en el activo de otro que dejaría una venta de ese otro sin participaciones:
    -- se queda, para no impedir la salida ni romper la cartera ajena.
    null;
  end;
end;
$$;

revoke all on function private.purge_member_data(uuid, uuid) from public, anon, authenticated;

-- 4. Al dejar de ser miembro --------------------------------------------------------------------------

create function private.on_member_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Se está borrando el hogar entero o el usuario: sus filas caen por las claves foráneas.
  if not exists (select 1 from public.households h where h.id = old.household_id)
     or not exists (select 1 from auth.users u where u.id = old.user_id) then
    return null;
  end if;

  if old.user_id = (select auth.uid()) then
    -- Sale por su cuenta.
    perform private.purge_member_data(old.household_id, old.user_id);
    delete from private.removed_members where household_id = old.household_id and user_id = old.user_id;
  else
    -- Lo quita otro: el dueño desde la app, o alguien desde el panel (sin sesión). Empieza el plazo.
    insert into private.removed_members (household_id, user_id)
    values (old.household_id, old.user_id)
    on conflict (household_id, user_id) do update set removed_at = now();
  end if;
  return null;
end;
$$;

revoke all on function private.on_member_deleted() from public, anon, authenticated;

create trigger household_members_deleted
  after delete on public.household_members
  for each row execute function private.on_member_deleted();

-- Si vuelve a entrar dentro del plazo, sus datos vuelven a ser visibles: ya no hay nada que purgar.
create function private.on_member_added()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.removed_members where household_id = new.household_id and user_id = new.user_id;
  return null;
end;
$$;

revoke all on function private.on_member_added() from public, anon, authenticated;

create trigger household_members_added
  after insert on public.household_members
  for each row execute function private.on_member_added();

-- 5. Purga al acabar el plazo ---------------------------------------------------------------------------

create function private.purge_removed_members()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired record;
  purged integer := 0;
begin
  for expired in
    delete from private.removed_members r
    where private.removed_until(r.removed_at) <= now()
    returning r.household_id, r.user_id
  loop
    -- No debería haber fila si volvió a entrar (on_member_added la quita); se comprueba igualmente
    -- porque borrar los datos de un miembro activo no tiene arreglo.
    if not exists (
      select 1 from public.household_members m
      where m.household_id = expired.household_id and m.user_id = expired.user_id
    ) then
      perform private.purge_member_data(expired.household_id, expired.user_id);
      purged := purged + 1;
    end if;
  end loop;
  return purged;
end;
$$;

revoke all on function private.purge_removed_members() from public, anon, authenticated;

-- Una vez al día. La hora da igual: el acceso se corta por fecha en las funciones de abajo, no por la purga.
create extension if not exists pg_cron;
select cron.schedule('orc56-purga-de-miembros-quitados', '17 3 * * *', 'select private.purge_removed_members()');

-- 6. Lo que puede hacer quien ha sido quitado -----------------------------------------------------------

-- Los hogares de los que le han quitado y hasta cuándo puede exportar.
create function public.removed_households()
returns table (household_id uuid, name text, removed_at timestamptz, export_until timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.household_id, h.name, r.removed_at, private.removed_until(r.removed_at)
  from private.removed_members r
  join public.households h on h.id = r.household_id
  where r.user_id = (select auth.uid())
    and private.removed_until(r.removed_at) > now()
  order by r.removed_at desc;
$$;

-- Sus cuentas, categorías y movimientos de ese hogar, con las mismas columnas que leen las apps, para
-- montar el CSV. Sólo lo suyo (created_by), sólo lectura y sólo dentro del plazo.
create function public.removed_household_export(target_household uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1 from private.removed_members r
    where r.household_id = target_household and r.user_id = uid
      and private.removed_until(r.removed_at) > now()
  ) then
    raise exception 'no hay datos que exportar de ese hogar' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'accounts', (
      select coalesce(jsonb_agg(to_jsonb(a) - 'created_by' order by a.name, a.id), '[]'::jsonb)
      from public.accounts a where a.household_id = target_household and a.created_by = uid),
    'categories', (
      select coalesce(jsonb_agg(to_jsonb(c) - 'created_by' order by c.name, c.id), '[]'::jsonb)
      from public.categories c where c.household_id = target_household and c.created_by = uid),
    'movements', (
      select coalesce(jsonb_agg(to_jsonb(t) - 'created_by' order by t.booked_on, t.id), '[]'::jsonb)
      from public.transactions t where t.household_id = target_household and t.created_by = uid)
  );
end;
$$;

revoke all on function public.removed_households(), public.removed_household_export(uuid) from public, anon;
grant execute on function public.removed_households(), public.removed_household_export(uuid) to authenticated;
