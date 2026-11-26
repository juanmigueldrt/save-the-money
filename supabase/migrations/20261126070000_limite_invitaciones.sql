-- ORC-58: accept_invite limita los intentos fallidos y create_invite genera
-- códigos sin sesgo de módulo.
--
-- Un código de 6 caracteres de un alfabeto de 31 se puede probar por fuerza
-- bruta si nada lo limita. El formato no cambia, así que los códigos ya
-- emitidos y las apps siguen valiendo; lo nuevo es que cada usuario tiene un
-- número máximo de intentos fallidos por ventana de tiempo.
--
-- Un intento fallido tiene que quedar guardado, y un insert dentro de una
-- función que después lanza un error se deshace con ella. Por eso
-- accept_invite ya no lanza error con un código que no sirve: guarda el
-- intento y devuelve null. Si el código sirve, devuelve el hogar con el mismo
-- JSON que antes. Las versiones antiguas de la app no saben leer ese null y
-- enseñan su mensaje genérico («Algo ha fallado»).

-- Intentos fallidos ---------------------------------------------------------------

-- Sólo quién y cuándo: nunca el código que se probó.
create table private.invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index invite_attempts_user_id_attempted_at_idx on private.invite_attempts (user_id, attempted_at);
-- Para borrar los intentos viejos de todos los usuarios sin recorrer la tabla.
create index invite_attempts_attempted_at_idx on private.invite_attempts (attempted_at);

-- Sin políticas ni permisos: sólo accept_invite (security definer) la usa.
alter table private.invite_attempts enable row level security;
revoke all on table private.invite_attempts from public, anon, authenticated;
revoke all on sequence private.invite_attempts_id_seq from public, anon, authenticated;

-- Códigos sin sesgo ---------------------------------------------------------------

-- Convierte bytes aleatorios en un código de 6 caracteres. 256 no es múltiplo
-- de 31: con `byte % 31` las primeras letras salían más a menudo. Se descartan
-- los bytes >= 248 (31 * 8) y así cada letra tiene la misma probabilidad.
-- Devuelve null si no hay 6 bytes válidos.
create function private.invite_code_from_bytes(random_bytes bytea)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  -- Mayor múltiplo de 31 que cabe en un byte.
  usable_limit constant int := 248;
  code text := '';
  byte_value int;
begin
  for i in 0 .. length(random_bytes) - 1 loop
    byte_value := get_byte(random_bytes, i);
    if byte_value < usable_limit then
      code := code || substr(alphabet, byte_value % 31 + 1, 1);
      if length(code) = 6 then
        return code;
      end if;
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function private.invite_code_from_bytes(bytea) from public, anon, authenticated;

create or replace function public.create_invite(target_household uuid)
returns public.household_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
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
    -- Bytes aleatorios criptográficos, no random(). 16 bytes casi siempre
    -- dan 6 válidos; si no, se piden otros.
    loop
      new_code := private.invite_code_from_bytes(extensions.gen_random_bytes(16));
      exit when new_code is not null;
    end loop;

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

-- accept_invite con límite de intentos ------------------------------------------

-- Cambia lo que devuelve (jsonb en vez de households), así que hay que borrarla.
drop function public.accept_invite(text);

create function public.accept_invite(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Límite: como mucho max_failures códigos que no sirven dentro de
  -- failure_window por usuario. Al llegar, se rechaza cualquier llamada de ese
  -- usuario, también con un código bueno, hasta que el más antiguo de esos
  -- fallos sale de la ventana. Un acierto no pone el contador a cero.
  max_failures constant int := 5;
  failure_window constant interval := interval '15 minutes';
  uid uuid := auth.uid();
  blocked_until timestamptz;
  invite public.household_invites;
  joined public.households;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Una llamada a la vez por usuario: si no, varias en paralelo leerían el
  -- mismo recuento y pasarían todas.
  perform pg_advisory_xact_lock(hashtext('accept_invite'), hashtext(uid::text));

  select a.attempted_at + failure_window into blocked_until
  from private.invite_attempts a
  where a.user_id = uid and a.attempted_at > now() - failure_window
  order by a.attempted_at desc
  offset max_failures - 1
  limit 1;

  -- Las apps leen los minutos del mensaje: mantener «retry in N min».
  if blocked_until is not null then
    raise exception 'too many invite attempts; retry in % min',
      greatest(1, ceil(extract(epoch from blocked_until - now()) / 60))::int
      using errcode = 'STM04';
  end if;

  select * into invite
  from public.household_invites
  where code = upper(replace(replace(trim(invite_code), ' ', ''), '-', ''))
  for update;

  -- Un único resultado (null) para código inexistente, usado, revocado o
  -- caducado: así no se puede averiguar qué códigos existen. Todos cuentan
  -- como intento fallido. No se lanza error para que el intento quede
  -- guardado; de paso se borran los intentos que ya no cuentan para nadie.
  if invite.id is null or invite.status <> 'pending' or invite.expires_at <= now() then
    delete from private.invite_attempts where attempted_at <= now() - failure_window;
    insert into private.invite_attempts (user_id) values (uid);
    return null;
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
  return to_jsonb(joined);
end;
$$;

revoke all on function public.accept_invite(text) from public, anon;
grant execute on function public.accept_invite(text) to authenticated;
