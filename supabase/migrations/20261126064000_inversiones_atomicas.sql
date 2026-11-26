-- Inversiones atómicas (ORC-64).
--
-- 1. Una posición nunca queda en negativo, en ninguna fecha, se escriba como se escriba la
--    operación (función, insert, update o delete directos): lo comprueba un trigger.
-- 2. `create_trade` guarda una compra o venta y su movimiento en la cuenta en una sola
--    transacción. Antes eran dos peticiones: si fallaba la segunda quedaba la operación sin su
--    movimiento, y al reintentar se duplicaba. La app genera el identificador de la operación:
--    repetir la petición devuelve lo guardado y no apunta nada; con otros datos falla (STM01).
-- 3. `record_holding_price` apunta el precio de un día y, si es el más reciente, el precio
--    actual del activo, también en una sola transacción (antes, hasta cuatro peticiones).
--
-- Los datos que ya hay no se tocan. Las apps anteriores siguen funcionando: sus insert y delete
-- directos pasan por el mismo trigger.

-- 1. La posición nunca queda en negativo ----------------------------------------------------

-- SECURITY DEFINER a propósito: desde la migración de privacidad cada persona solo ve las
-- operaciones que creó. Un activo anterior a esa migración puede tener operaciones de otro
-- miembro (o de alguien que ya no existe), que quien llama no ve: con sus permisos la suma
-- saldría mal y la posición real podría quedar en negativo. La función no devuelve datos: solo
-- deja pasar o falla. Vive en `private` y nadie puede llamarla directamente.
create function private.check_trade_timeline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  targets uuid[];
  target uuid;
begin
  if tg_op = 'INSERT' then
    targets := array[new.holding_id];
  elsif tg_op = 'DELETE' then
    targets := array[old.holding_id];
  else
    targets := array[old.holding_id, new.holding_id];
  end if;

  foreach target in array targets loop
    -- Bloquea el activo hasta el final de la transacción: dos ventas a la vez del mismo activo
    -- pasan de una en una, y la segunda ya ve la primera (cada sentencia lee lo confirmado,
    -- READ COMMITTED, que es como llegan las peticiones de las apps). NO KEY UPDATE y no
    -- UPDATE: no choca con el bloqueo de la clave foránea que ya tiene cada insert.
    perform 1 from public.holdings h where h.id = target for no key update;
    -- Sin activo no hay nada que comprobar: se está borrando con todas sus operaciones.
    if found and exists (
      -- Participaciones al final de cada día (las compras de un día cuentan antes que sus ventas).
      select 1
      from (
        select sum(case when t.side = 'buy' then t.quantity else -t.quantity end)
                 over (order by t.traded_on) as held
        from public.investment_trades t
        where t.holding_id = target
      ) days
      where days.held < 0
    ) then
      -- Códigos propios para que las apps den el aviso exacto.
      if tg_op = 'DELETE' then
        raise exception 'Sin esa compra, una venta posterior se queda sin participaciones' using errcode = 'STM03';
      end if;
      raise exception 'No hay tantas participaciones para vender' using errcode = 'STM02';
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function private.check_trade_timeline() from public, anon, authenticated;

-- AFTER: la comprobación ve el resultado de toda la sentencia. Una compra nueva o una venta
-- borrada solo suben la posición, así que no se comprueban: tampoco estorban a quien tenga ya
-- un activo en negativo de antes y lo esté arreglando.
create trigger investment_trades_timeline_insert
  after insert on public.investment_trades
  for each row when (new.side = 'sell')
  execute function private.check_trade_timeline();
create trigger investment_trades_timeline_update
  after update of holding_id, traded_on, side, quantity on public.investment_trades
  for each row
  execute function private.check_trade_timeline();
create trigger investment_trades_timeline_delete
  after delete on public.investment_trades
  for each row when (old.side = 'buy')
  execute function private.check_trade_timeline();

-- 2. Compra o venta con su movimiento ------------------------------------------------------------

alter table public.transactions
  -- La operación de inversión que apuntó este movimiento; null en el resto.
  add column trade_id uuid;

-- Parcial: los movimientos que no son de una operación no ocupan sitio en el índice.
create unique index transactions_trade_id_key
  on public.transactions (trade_id)
  where trade_id is not null;

-- Solo al crear la fila, como household_id: no se cambian después.
grant insert (trade_id) on public.transactions to authenticated;
-- La app elige el identificador de la operación para poder repetir la petición sin duplicar.
grant insert (id) on public.investment_trades to authenticated;

create function public.create_trade(
  trade uuid,
  household uuid,
  holding uuid,
  traded date,
  trade_side public.trade_side,
  shares numeric,
  unit_price numeric,
  fee bigint default 0,
  trade_note text default null,
  -- Cuenta en la que se apunta el dinero; null = solo la operación, sin movimiento.
  account uuid default null,
  category uuid default null,
  -- Céntimos que entran (venta) o salen (compra, en negativo) de la cuenta.
  cash bigint default null,
  label text default null
) returns setof public.investment_trades
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.investment_trades;
  movement public.transactions;
  created boolean;
begin
  if trade is null then
    raise exception 'Falta el identificador de la operación' using errcode = '23514';
  end if;
  if account is not null and (cash is null or label is null) then
    raise exception 'Faltan el importe o el concepto del movimiento' using errcode = '23514';
  end if;

  -- Si la operación ya estaba guardada no se apunta nada. Si es una venta nueva, el trigger
  -- comprueba aquí mismo que hay participaciones.
  insert into public.investment_trades (id, household_id, holding_id, traded_on, side, quantity, price, fee_minor, note)
  values (trade, household, holding, traded, trade_side, shares, unit_price, fee, trade_note)
  on conflict (id) do nothing;
  created := found;

  -- El RLS solo deja ver las operaciones propias: si no se ve, ese identificador es de otra persona.
  select t.* into saved from public.investment_trades t where t.id = trade;
  if not found then
    raise exception 'Ese identificador de operación ya está usado' using errcode = '23505';
  end if;

  -- Repetir la petición solo vale con los mismos datos (STM01, como create_transfer).
  if (saved.holding_id = holding and saved.traded_on = traded and saved.side = trade_side
      and saved.quantity = round(shares, 8) and saved.price = round(unit_price, 6)
      and saved.fee_minor = fee) is not true then
    raise exception 'Esa operación ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  select m.* into movement from public.transactions m where m.trade_id = trade;
  if account is null then
    if found then
      raise exception 'Esa operación ya está guardada con otros datos' using errcode = 'STM01';
    end if;
  elsif found then
    if (movement.account_id = account and movement.amount_minor = cash) is not true then
      raise exception 'Esa operación ya está guardada con otros datos' using errcode = 'STM01';
    end if;
  elsif not created then
    -- La operación ya estaba guardada sin movimiento: no se le añade uno ahora.
    raise exception 'Esa operación ya está guardada con otros datos' using errcode = 'STM01';
  else
    -- Misma transacción que la operación: si el movimiento no vale, no queda ninguna de las dos.
    insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description, trade_id)
    values (household, account, category, traded, cash, label, trade);
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_trade(uuid, uuid, uuid, date, public.trade_side, numeric, numeric, bigint, text, uuid, uuid, bigint, text)
  from public, anon;
grant execute on function public.create_trade(uuid, uuid, uuid, date, public.trade_side, numeric, numeric, bigint, text, uuid, uuid, bigint, text)
  to authenticated;

-- 3. Precio de un día ----------------------------------------------------------------------------

create function public.record_holding_price(
  holding uuid,
  priced date,
  new_price numeric
) returns setof public.holdings
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.holdings;
begin
  if priced is null or new_price is null or new_price < 0 then
    raise exception 'El precio no puede ser negativo' using errcode = '23514';
  end if;

  -- El RLS solo deja ver los activos propios. El bloqueo hace que dos precios a la vez del
  -- mismo activo no se pisen al decidir cuál es el más reciente.
  select h.* into target from public.holdings h where h.id = holding for no key update;
  if not found then
    raise exception 'Ese activo no existe' using errcode = '23503';
  end if;

  -- Un precio por día: apuntar otro el mismo día lo sustituye.
  insert into public.holding_prices (household_id, holding_id, priced_on, price)
  values (target.household_id, holding, priced, new_price)
  on conflict (holding_id, priced_on) do update set price = excluded.price;

  -- Un precio de un día anterior al último apuntado solo va al histórico.
  if target.price_on is null or priced >= target.price_on then
    update public.holdings h set price = new_price, price_on = priced
    where h.id = holding
    returning h.* into target;
  end if;

  return next target;
end;
$$;

revoke all on function public.record_holding_price(uuid, date, numeric) from public, anon;
grant execute on function public.record_holding_price(uuid, date, numeric) to authenticated;
