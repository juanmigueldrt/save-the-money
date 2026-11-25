-- Transferencias atómicas: las dos patas de una transferencia (por ejemplo el pago de una
-- tarjeta: salida de la cuenta y entrada en la tarjeta) se guardan en una sola transacción.
--
-- Antes las apps guardaban cada pata con una petición distinta: si fallaba la segunda, la
-- primera se quedaba guardada, y al reintentar se duplicaba la salida.
--
-- Cada pata lleva el identificador de la transferencia, que genera la app, y un índice único
-- impide guardar dos veces la misma pata: repetir la petición devuelve las dos filas que ya
-- había y no apunta nada nuevo. Si se repite con otra cuenta, otro importe u otro día, falla
-- (STM01) para que nadie crea que se guardó lo nuevo.
--
-- No cambia quién ve qué: la función corre con los permisos de quien llama (RLS).
-- Los movimientos que ya existen y las apps anteriores siguen igual: las dos columnas son
-- opcionales y nadie más las rellena.

alter table public.transactions
  -- El mismo valor en las dos patas de una transferencia; null en el resto de movimientos.
  add column transfer_id uuid,
  -- true en la salida, false en la entrada. No se puede cambiar después, así que editar el
  -- importe o la cuenta de una pata nunca choca con el índice.
  add column transfer_out boolean,
  add constraint transactions_transfer_leg_check check ((transfer_id is null) = (transfer_out is null));

-- Parcial: los movimientos que no son de una transferencia no ocupan sitio en el índice.
create unique index transactions_transfer_leg_key
  on public.transactions (transfer_id, transfer_out)
  where transfer_id is not null;

-- Solo al crear la fila: como household_id, no se cambian después.
grant insert (transfer_id, transfer_out) on public.transactions to authenticated;

create function public.create_transfer(
  transfer uuid,
  household uuid,
  from_account uuid,
  to_account uuid,
  booked date,
  amount bigint,
  category uuid,
  from_label text,
  to_label text,
  note text default null,
  is_excluded boolean default false,
  payee_name text default null,
  tag_list text[] default '{}'
) returns setof public.transactions
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if transfer is null then
    raise exception 'Falta el identificador de la transferencia' using errcode = '23514';
  end if;
  if amount is null or amount <= 0 then
    raise exception 'El importe tiene que ser mayor que cero' using errcode = '23514';
  end if;
  if from_account is null or to_account is null or from_account = to_account then
    raise exception 'Hacen falta dos cuentas distintas' using errcode = '23514';
  end if;
  -- El RLS solo deja ver las cuentas propias: una cuenta ajena o de otro hogar no cuenta.
  if (select count(*) from public.accounts a
      where a.household_id = household and a.id in (from_account, to_account)) <> 2 then
    raise exception 'Las dos cuentas tienen que ser de ese hogar' using errcode = '23503';
  end if;

  -- Una sola sentencia: o entran las dos patas o ninguna. Si la transferencia ya estaba
  -- guardada, el índice único hace que no se apunte nada.
  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor,
                                   description, notes, excluded, payee, tags, transfer_id, transfer_out)
  values
    (household, from_account, category, booked, -amount, from_label, note, is_excluded, payee_name, tag_list, transfer, true),
    (household, to_account, category, booked, amount, to_label, note, is_excluded, payee_name, tag_list, transfer, false)
  on conflict (transfer_id, transfer_out) where transfer_id is not null do nothing;

  -- Si no se ven las dos patas, ese identificador ya lo usó otra persona: se deshace todo.
  if (select count(*) from public.transactions t where t.transfer_id = transfer) <> 2 then
    raise exception 'Ese identificador de transferencia ya está usado' using errcode = '23505';
  end if;

  -- Repetir la petición solo vale con los mismos datos. Si la transferencia ya estaba guardada
  -- con otra cuenta, otro importe u otro día, se avisa en vez de dar por buena la nueva versión.
  -- STM01 es un código propio: las apps lo distinguen de los datos no válidos (23514, 23503).
  if exists (
    select 1 from public.transactions t
    where t.transfer_id = transfer
      and not (t.booked_on = booked
               and ((t.transfer_out and t.account_id = from_account and t.amount_minor = -amount)
                 or (not t.transfer_out and t.account_id = to_account and t.amount_minor = amount)))
  ) then
    raise exception 'Esa transferencia ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  return query
    select t.* from public.transactions t where t.transfer_id = transfer order by t.transfer_out desc;
end;
$$;

revoke all on function public.create_transfer(uuid, uuid, uuid, uuid, date, bigint, uuid, text, text, text, boolean, text, text[])
  from public, anon;
grant execute on function public.create_transfer(uuid, uuid, uuid, uuid, date, bigint, uuid, text, text, text, boolean, text, text[])
  to authenticated;
