-- Movimientos: apuntar sin duplicar y cambiar sin pisar (ORC-69).
--
-- 1. Apuntar: la app elige el identificador del movimiento, uno por formulario. Repetir la
--    petición (por ejemplo tras un corte de red) devuelve lo guardado y no apunta nada; con otra
--    cuenta, otro importe u otro día falla (STM01), igual que create_transfer y create_trade.
-- 2. Cambiar: la app manda el `updated_at` que leyó. Si la fila ha cambiado desde entonces, o ya
--    no existe, no se cambia nada y falla con STM05: la app recarga y avisa.
--
-- Son funciones y no un upsert directo porque un `on conflict do nothing` desde la app no
-- devuelve la fila guardada, no distingue «ya estaba» de «ese identificador es de otra persona»
-- y no puede avisar de que se repite con otros datos. Las dos corren con los permisos de quien
-- llama: el RLS sigue decidiendo quién apunta y quién cambia qué.
--
-- No cambia quién ve qué ni toca filas existentes. Las apps anteriores siguen funcionando: sus
-- insert y update directos conservan los permisos que tenían (sin estas dos protecciones).

-- Solo al crear la fila, como en investment_trades. Un identificador repetido choca con la
-- clave primaria: nunca sobrescribe ni deja leer la fila de otra persona.
grant insert (id) on public.transactions to authenticated;

create function public.create_movement(
  movement uuid,
  household uuid,
  account uuid,
  category uuid,
  booked date,
  amount bigint,
  label text,
  note text default null,
  is_excluded boolean default false,
  payee_name text default null,
  tag_list text[] default '{}'
) returns setof public.transactions
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.transactions;
begin
  if movement is null then
    raise exception 'Falta el identificador del movimiento' using errcode = '23514';
  end if;

  -- Si el movimiento ya estaba guardado no se apunta nada.
  insert into public.transactions (id, household_id, account_id, category_id, booked_on, amount_minor,
                                   description, notes, excluded, payee, tags)
  values (movement, household, account, category, booked, amount, label, note, is_excluded, payee_name, tag_list)
  on conflict (id) do nothing;

  -- El RLS solo deja ver los movimientos propios: si no se ve, ese identificador es de otra persona.
  select t.* into saved from public.transactions t where t.id = movement;
  if not found then
    raise exception 'Ese identificador de movimiento ya está usado' using errcode = '23505';
  end if;

  -- Repetir la petición solo vale con los mismos datos (STM01, como create_transfer).
  if (saved.account_id = account and saved.amount_minor = amount and saved.booked_on = booked) is not true then
    raise exception 'Ese movimiento ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_movement(uuid, uuid, uuid, uuid, date, bigint, text, text, boolean, text, text[])
  from public, anon;
grant execute on function public.create_movement(uuid, uuid, uuid, uuid, date, bigint, text, text, boolean, text, text[])
  to authenticated;

-- `seen` es el `updated_at` tal cual lo devolvió el servidor (con microsegundos y zona). La
-- comparación va en el mismo update: entre dos cambios a la vez solo entra el primero.
create function public.update_movement(
  movement uuid,
  seen timestamptz,
  account uuid,
  category uuid,
  booked date,
  amount bigint,
  label text,
  note text,
  is_excluded boolean,
  reviewed timestamptz,
  payee_name text,
  tag_list text[]
) returns setof public.transactions
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.transactions t
    set account_id = account, category_id = category, booked_on = booked, amount_minor = amount,
        description = label, notes = note, excluded = is_excluded, reviewed_at = reviewed,
        payee = payee_name, tags = tag_list
    where t.id = movement and t.updated_at = seen
    returning t.*;

  -- Sin fila: ha cambiado desde que se leyó, se ha borrado o no es de quien llama (el RLS no la
  -- deja ver). STM05 es un código propio: las apps recargan y avisan.
  if not found then
    raise exception 'El movimiento ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_movement(uuid, timestamptz, uuid, uuid, date, bigint, text, text, boolean, timestamptz, text, text[])
  from public, anon;
grant execute on function public.update_movement(uuid, timestamptz, uuid, uuid, date, bigint, text, text, boolean, timestamptz, text, text[])
  to authenticated;
