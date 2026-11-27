-- ORC-59: un hogar no se queda sin dueño, ni sin miembros, y borrarlo no arrasa los datos de otros.
--
-- Antes:
--   * el dueño podía borrar su fila de household_members con otros miembros dentro: el hogar se quedaba sin
--     nadie que pudiera cambiarlo, quitar miembros ni borrarlo;
--   * cuando salía el último miembro, el hogar seguía en la base sin que nadie pudiera verlo;
--   * el dueño podía borrar el hogar entero, y la cascada se llevaba los datos privados de los demás.
--
-- Ahora:
--   * el dueño no puede salir mientras haya otros miembros: antes traspasa el hogar (transfer_household)
--     o los quita;
--   * si se borra el usuario del dueño, el hogar pasa al miembro más antiguo;
--   * un hogar sin miembros se borra solo, cuando ya no queda nadie con plazo para exportar (ORC-56);
--   * el hogar sólo se puede borrar cuando su dueño es el único miembro y nadie tiene plazo para exportar.

-- 1. El dueño no sale con otros miembros dentro ------------------------------------------------------

create function private.before_member_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'owner'
     -- Si se está borrando el hogar o el usuario, la fila cae por las claves foráneas: no se impide.
     and exists (select 1 from public.households h where h.id = old.household_id)
     and exists (select 1 from auth.users u where u.id = old.user_id)
     and exists (
       select 1 from public.household_members m
       where m.household_id = old.household_id and m.user_id <> old.user_id)
  then
    -- Código propio para que las apps den el aviso exacto.
    raise exception 'el dueño no puede salir mientras haya otros miembros' using errcode = 'STM08';
  end if;
  return old;
end;
$$;

revoke all on function private.before_member_deleted() from public, anon, authenticated;

create trigger household_members_owner_stays
  before delete on public.household_members
  for each row execute function private.before_member_deleted();

-- 2. Traspasar el hogar ----------------------------------------------------------------------------------

-- Sólo el dueño, y sólo a alguien que ya es miembro. Los dos cambios van en la misma transacción:
-- no hay ningún momento con dos dueños ni con ninguno.
create function public.transfer_household(target_household uuid, new_owner uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- Bloquea al dueño actual: dos traspasos a la vez pasan de uno en uno.
  perform 1 from public.household_members m
  where m.household_id = target_household and m.user_id = uid and m.role = 'owner'
  for update;
  if not found then
    raise exception 'sólo el dueño puede traspasar el hogar' using errcode = '42501';
  end if;
  if new_owner = uid then
    return;
  end if;

  update public.household_members m set role = 'owner'
  where m.household_id = target_household and m.user_id = new_owner;
  if not found then
    raise exception 'esa persona no es miembro del hogar' using errcode = '42501';
  end if;
  update public.household_members m set role = 'member'
  where m.household_id = target_household and m.user_id = uid;
end;
$$;

revoke all on function public.transfer_household(uuid, uuid) from public, anon;
grant execute on function public.transfer_household(uuid, uuid) to authenticated;

-- 3. Un hogar sin miembros se borra ---------------------------------------------------------------------

-- Sin miembros y sin nadie con plazo para exportar (private.removed_members, ORC-56): ya no es de nadie.
create function private.delete_household_if_empty(target_household uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.households h
  where h.id = target_household
    and not exists (select 1 from public.household_members m where m.household_id = h.id)
    and not exists (select 1 from private.removed_members r where r.household_id = h.id);
$$;

revoke all on function private.delete_household_if_empty(uuid) from public, anon, authenticated;

-- Lo mismo que en ORC-56, más el borrado del hogar vacío al final.
create or replace function private.on_member_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Se está borrando el hogar entero: sus filas caen por las claves foráneas.
  if not exists (select 1 from public.households h where h.id = old.household_id) then
    return null;
  end if;

  if not exists (select 1 from auth.users u where u.id = old.user_id) then
    -- Se está borrando el usuario: sus filas caen por created_by. Si era el dueño, el hogar pasa al miembro
    -- más antiguo, para que no se quede sin nadie que pueda gestionarlo.
    if old.role = 'owner' then
      update public.household_members m set role = 'owner'
      where m.id = (
        select o.id from public.household_members o
        where o.household_id = old.household_id
        order by o.created_at, o.id
        limit 1);
    end if;
  elsif old.user_id = (select auth.uid()) then
    -- Sale por su cuenta.
    perform private.purge_member_data(old.household_id, old.user_id);
    delete from private.removed_members where household_id = old.household_id and user_id = old.user_id;
  else
    -- Lo quita otro: el dueño desde la app, o alguien desde el panel (sin sesión). Empieza el plazo.
    insert into private.removed_members (household_id, user_id)
    values (old.household_id, old.user_id)
    on conflict (household_id, user_id) do update set removed_at = now();
  end if;

  -- Sin miembros no queda nadie que pueda invitar, y quien entrara lo haría en un hogar sin dueño
  -- (puede seguir existiendo unos días por el plazo de alguien): sus invitaciones dejan de valer.
  if not exists (select 1 from public.household_members m where m.household_id = old.household_id) then
    update public.household_invites i set status = 'revoked'
    where i.household_id = old.household_id and i.status = 'pending';
  end if;

  perform private.delete_household_if_empty(old.household_id);
  return null;
end;
$$;

-- La purga de ORC-56, que además borra el hogar si con ella se queda sin nadie.
create or replace function private.purge_removed_members()
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
    perform private.delete_household_if_empty(expired.household_id);
  end loop;
  return purged;
end;
$$;

-- 4. Borrar el hogar: sólo cuando el dueño está solo -------------------------------------------------

create function private.is_alone(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
           select 1 from public.household_members m
           where m.household_id = target_household and m.user_id <> (select auth.uid()))
     and not exists (select 1 from private.removed_members r where r.household_id = target_household);
$$;

revoke all on function private.is_alone(uuid) from public, anon;
grant execute on function private.is_alone(uuid) to authenticated;

-- Con otros miembros, o con alguien que aún puede exportar, el borrado no afecta a ninguna fila.
alter policy households_delete on public.households
  using ((select private.is_owner(id)) and (select private.is_alone(id)));
