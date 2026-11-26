-- Transferencias como una sola operación (ORC-75).
--
-- Desde create_transfer (ORC-62) las dos patas de una transferencia llevan el mismo
-- transfer_id, pero se cambiaban y se borraban cada una por su lado: cambiar el importe de la
-- salida dejaba la entrada con el importe viejo, y borrar una pata dejaba la otra suelta.
--
-- 1. Cambiar: al cambiar el importe o el día de una pata, la otra cambia igual en la misma
--    transacción (un trigger, para que valga también para update_movement y para las apps
--    anteriores, que cambian la fila directamente). La salida sigue siendo negativa y la
--    entrada positiva, y las dos patas no pueden quedar en la misma cuenta.
-- 2. Borrar: delete_transfer borra las dos patas en una sola llamada, o ninguna.
--
-- Las dos funciones corren con los permisos de quien llama: el RLS sigue decidiendo qué se ve
-- y qué se cambia. Las dos patas las crea siempre la misma persona (create_transfer las
-- inserta en una sola sentencia y created_by no se puede cambiar), así que quien ve una ve la
-- otra mientras exista. Si la otra pata ya no existe (por ejemplo se borró su cuenta, o la
-- borró una versión anterior de la app), la que queda se comporta como un movimiento normal.
--
-- Los movimientos sin transfer_id (las transferencias apuntadas antes de ORC-62 y todo lo
-- demás) no cambian: el trigger no hace nada con ellos y delete_transfer no los encuentra.

create function private.keep_transfer_legs_together()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  other public.transactions;
begin
  if (new.transfer_out and new.amount_minor > 0) or (not new.transfer_out and new.amount_minor < 0) then
    raise exception 'En una transferencia la salida es negativa y la entrada positiva' using errcode = '23514';
  end if;

  -- Se bloquea la otra pata para que dos cambios a la vez no la dejen descuadrada.
  select t.* into other from public.transactions t
  where t.transfer_id = new.transfer_id and t.id <> new.id
  for update;
  if not found then
    return null;
  end if;

  if other.account_id = new.account_id then
    raise exception 'Hacen falta dos cuentas distintas' using errcode = '23514';
  end if;
  -- Ya cuadran: es la vuelta de este mismo trigger, o el cambio no tocaba importe ni día.
  if other.amount_minor = -new.amount_minor and other.booked_on = new.booked_on then
    return null;
  end if;

  update public.transactions t
  set amount_minor = -new.amount_minor, booked_on = new.booked_on
  where t.id = other.id;
  -- Nunca debería pasar (se acaba de bloquear la fila): mejor fallar que dejarla descuadrada.
  if not found then
    raise exception 'No se puede cambiar la otra parte de la transferencia' using errcode = 'STM07';
  end if;
  return null;
end;
$$;

revoke all on function private.keep_transfer_legs_together() from public, anon, authenticated;

create trigger transactions_transfer_legs
  after update of amount_minor, booked_on, account_id on public.transactions
  for each row
  when (new.transfer_id is not null)
  execute function private.keep_transfer_legs_together();

-- Borra las patas de la transferencia que ve quien llama: las dos, o la única que queda si la
-- otra ya no existe. Si alguna no se puede borrar no se borra ninguna (STM07). Una
-- transferencia que ya no está (por ejemplo al repetir la petición) no hace nada.
create function public.delete_transfer(transfer uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  seen int;
  deleted int;
begin
  if transfer is null then
    raise exception 'Falta el identificador de la transferencia' using errcode = '23514';
  end if;

  select count(*) into seen from public.transactions t where t.transfer_id = transfer;
  delete from public.transactions t where t.transfer_id = transfer;
  get diagnostics deleted = row_count;

  if deleted <> seen then
    raise exception 'No se puede borrar la otra parte de la transferencia' using errcode = 'STM07';
  end if;
end;
$$;

revoke all on function public.delete_transfer(uuid) from public, anon;
grant execute on function public.delete_transfer(uuid) to authenticated;
