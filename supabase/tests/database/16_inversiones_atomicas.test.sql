-- Inversiones atómicas: la operación y su movimiento o ninguno, sin duplicar; la posición nunca
-- en negativo; el precio en una sola llamada. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(52);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

-- Para probar que el precio es atómico: el segundo paso (el precio actual del activo) falla con 999.
create function public.falla_precio_de_prueba() returns trigger language plpgsql as $$
begin
  if new.price = 999 then
    raise exception 'fallo de prueba' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger holdings_falla_de_prueba before update on public.holdings
  for each row execute function public.falla_precio_de_prueba();

-- Ana y Bruno comparten hogar.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
create temp table ids (name text primary key, id uuid) on commit drop;
grant select on hogar, invitacion to authenticated;
grant select, insert on ids to authenticated;

with x as (insert into public.accounts (household_id, name, opening_balance_minor)
           select id, 'Cuenta de Ana', 100000 from hogar returning id)
insert into ids select 'cuenta', id from x;
with x as (insert into public.holdings (household_id, name, price, price_on)
           select id, 'Fondo de prueba', 10, '2026-11-01' from hogar returning id)
insert into ids select 'fondo', id from x;
with x as (insert into public.holdings (household_id, name, price)
           select id, 'Fondo antiguo', 10 from hogar returning id)
insert into ids select 'antiguo', id from x;
insert into ids select 'categoria', id from public.categories where kind = 'transfer';

-- Una operación de prueba sobre un activo de `ids`, a 10 la participación; con cuenta, también su movimiento.
create function pg_temp.operar(trade uuid, lado public.trade_side, participaciones numeric, dia date,
                               cuenta text default null, importe bigint default null,
                               concepto text default 'Operación de prueba', activo text default 'fondo')
returns setof public.investment_trades language sql as $$
  select * from public.create_trade(
    trade, (select id from hogar), (select id from ids where name = activo), dia, lado, participaciones, 10,
    account => (select id from ids where name = cuenta), cash => importe, label => concepto);
$$;

-- Permisos ------------------------------------------------------------------------------
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.create_trade(uuid,uuid,uuid,date,public.trade_side,numeric,numeric,bigint,text,uuid,uuid,bigint,text)', 'execute'),
     has_function_privilege('authenticated', 'public.create_trade(uuid,uuid,uuid,date,public.trade_side,numeric,numeric,bigint,text,uuid,uuid,bigint,text)', 'execute'))),
  'f t', 'solo quien ha entrado puede apuntar operaciones');
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.record_holding_price(uuid,date,numeric)', 'execute'),
     has_function_privilege('authenticated', 'public.record_holding_price(uuid,date,numeric)', 'execute'))),
  'f t', 'y precios');
select is(
  (select string_agg(prosecdef::text, ' ' order by proname) from pg_proc
   where oid in ('public.create_trade(uuid,uuid,uuid,date,public.trade_side,numeric,numeric,bigint,text,uuid,uuid,bigint,text)'::regprocedure,
                 'public.record_holding_price(uuid,date,numeric)'::regprocedure)),
  'false false', 'las dos funciones corren con los permisos de quien llama');
select is(
  (select format('%s %s', has_function_privilege('authenticated', 'private.check_trade_timeline()', 'execute'),
                 (select prosecdef from pg_proc where oid = 'private.check_trade_timeline()'::regprocedure))),
  'f t', 'la comprobación de la posición ve todas las operaciones y nadie la llama a mano');

-- La compra: la operación y su movimiento ------------------------------------------------
select lives_ok(
  $$ select public.create_trade('20000000-0000-0000-0000-000000000001', (select id from hogar),
       (select id from ids where name = 'fondo'), '2026-11-02', 'buy', 10, 10, 0, null,
       (select id from ids where name = 'cuenta'), (select id from ids where name = 'categoria'), -10000, 'Compra de Fondo de prueba') $$,
  'Ana compra 10 participaciones desde su cuenta');
select is(
  (select format('%s %s %s %s', t.side, t.quantity, t.price, t.fee_minor)
   from public.investment_trades t where t.id = '20000000-0000-0000-0000-000000000001'),
  'buy 10.00000000 10.000000 0', 'queda la operación, con el identificador de la app');
select is(
  (select format('%s %s %s %s', (select name from ids where id = m.account_id), m.amount_minor, m.booked_on, m.description)
   from public.transactions m where m.trade_id = '20000000-0000-0000-0000-000000000001'),
  'cuenta -10000 2026-11-02 Compra de Fondo de prueba', 'y su cargo en la cuenta');
select is(
  (select balance_minor::int from public.account_balances where account_id = (select id from ids where name = 'cuenta')),
  90000, 'el saldo de la cuenta baja');

-- Repetir la misma petición no duplica ---------------------------------------------------
select is(
  (select string_agg(quantity::text, ' ')
   from pg_temp.operar('20000000-0000-0000-0000-000000000001', 'buy', 10, '2026-11-02', 'cuenta', -10000)),
  '10.00000000', 'repetir la petición devuelve la operación guardada');
select is(
  (select format('%s %s', (select count(*) from public.investment_trades), (select count(*) from public.transactions))),
  '1 1', 'y no apunta nada nuevo');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000001', 'buy', 11, '2026-11-02', 'cuenta', -10000) $$,
  'STM01', null, 'repetirla con otras participaciones falla en vez de darla por guardada');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000001', 'buy', 10, '2026-11-03', 'cuenta', -10000) $$,
  'STM01', null, 'y con otro día');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000001', 'buy', 10, '2026-11-02', 'cuenta', -99900) $$,
  'STM01', null, 'y con otro importe en la cuenta');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000001', 'buy', 10, '2026-11-02') $$,
  'STM01', null, 'y sin cuenta');
select is(
  (select format('%s %s', (select count(*) from public.investment_trades), (select count(*) from public.transactions))),
  '1 1', 'ninguno de esos intentos apunta nada');

-- La operación y su movimiento, o ninguno ------------------------------------------------
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000002', 'buy', 5, '2026-11-10', 'cuenta', -5000, '   ') $$,
  '23514', null, 'si el movimiento no vale, la compra falla');
select is(
  (select count(*)::int from public.investment_trades where id = '20000000-0000-0000-0000-000000000002'),
  0, 'y no queda la operación');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000002', 'buy', 5, '2026-11-10', 'cuenta', null) $$,
  '23514', null, 'con cuenta hace falta el importe');
select lives_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000002', 'buy', 5, '2026-11-10') $$,
  'el mismo identificador sirve para reintentar; sin cuenta solo se apunta la operación');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000002', 'buy', 5, '2026-11-10', 'cuenta', -5000) $$,
  'STM01', null, 'a una operación guardada sin movimiento no se le añade uno al repetirla');
select is((select count(*)::int from public.transactions), 1, 'solo hay un movimiento');

-- La posición nunca queda en negativo ----------------------------------------------------
-- Compras: 10 el día 2 y 5 el día 10.
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000003', 'sell', 16, '2026-11-12', 'cuenta', 16000) $$,
  'STM02', null, 'no se venden más participaciones de las que hay');
select is(
  (select format('%s %s', (select count(*) from public.investment_trades), (select count(*) from public.transactions))),
  '2 1', 'ni queda la venta ni su ingreso');
select lives_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000003', 'sell', 12, '2026-11-12', 'cuenta', 12000) $$,
  'Ana vende 12 de sus 15 participaciones');
select is(
  (select balance_minor::int from public.account_balances where account_id = (select id from ids where name = 'cuenta')),
  102000, 'y el ingreso llega a la cuenta');
select lives_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000004', 'sell', 2, '2026-11-05') $$,
  'una venta con fecha anterior vale si después siguen quedando participaciones');
-- El día 5 había 10 − 2 = 8, pero el día 12 quedarían 15 − 2 − 4 − 12 = −3.
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000005', 'sell', 4, '2026-11-05') $$,
  'STM02', null, 'una venta con fecha anterior no puede dejar sin participaciones a una venta posterior');
select throws_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price)
     select (select id from hogar), (select id from ids where name = 'fondo'), '2026-11-05', 'sell', 4, 10 $$,
  'STM02', null, 'tampoco con un insert directo, sin pasar por la función');
select throws_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price)
     select (select id from hogar), (select id from ids where name = 'fondo'), '2026-11-01', 'sell', 1, 10 $$,
  'STM02', null, 'ni vender antes de la primera compra');
select throws_ok(
  $$ update public.investment_trades set quantity = 1 where id = '20000000-0000-0000-0000-000000000002' $$,
  'STM02', null, 'ni rebajar una compra de la que depende una venta');
select throws_ok(
  $$ update public.investment_trades set traded_on = '2026-11-13' where id = '20000000-0000-0000-0000-000000000002' $$,
  'STM02', null, 'ni retrasarla');
select throws_ok(
  $$ delete from public.investment_trades where id = '20000000-0000-0000-0000-000000000002' $$,
  'STM03', null, 'ni borrarla');
select is((select count(*)::int from public.investment_trades), 4, 'siguen las cuatro operaciones');
select lives_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price)
     select (select id from hogar), (select id from ids where name = 'fondo'), '2026-11-12', 'sell', 1, 10 $$,
  'se puede vender justo lo que queda');
select lives_ok(
  $$ delete from public.investment_trades where id = '20000000-0000-0000-0000-000000000003' $$,
  'borrar una venta siempre vale');
select lives_ok(
  $$ delete from public.investment_trades where id = '20000000-0000-0000-0000-000000000002' $$,
  'y entonces la compra ya se puede borrar');
select is(
  (select count(*)::int from public.transactions where trade_id = '20000000-0000-0000-0000-000000000003'),
  1, 'borrar la operación no borra su movimiento');

-- Operaciones de otro miembro en un activo anterior a la privacidad ----------------------------
-- Ana compró 10; Bruno vendió 8 cuando todo el hogar veía todo. Ana ya no ve esa venta.
select pg_temp.operar('20000000-0000-0000-0000-000000000006', 'buy', 10, '2026-10-01', activo => 'antiguo');
select pg_temp.logout();
insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price, created_by)
  select (select id from hogar), (select id from ids where name = 'antiguo'), '2026-10-05', 'sell', 8, 10,
         '00000000-0000-0000-0000-00000000000b';
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select count(*)::int from public.investment_trades where holding_id = (select id from ids where name = 'antiguo')),
  1, 'Ana solo ve su compra en el activo antiguo');
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000007', 'sell', 5, '2026-10-10', activo => 'antiguo') $$,
  'STM02', null, 'pero no vende lo que ya vendió Bruno: la comprobación cuenta todas las operaciones');
select lives_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000007', 'sell', 2, '2026-10-10', activo => 'antiguo') $$,
  'sí vende lo que queda de verdad');

-- Borrar el activo se lleva sus operaciones aunque haya ventas -------------------------------
select lives_ok(
  $$ delete from public.holdings where id = (select id from ids where name = 'antiguo') $$,
  'borrar un activo con compras y ventas no choca con la comprobación');
select pg_temp.logout();
select is(
  (select count(*)::int from public.investment_trades where holding_id = (select id from ids where name = 'antiguo')),
  0, 'y no queda ninguna operación suya, tampoco la de Bruno');

-- El precio, en una sola llamada -------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s', price, price_on)
   from public.record_holding_price((select id from ids where name = 'fondo'), '2026-11-03', 12.5)),
  '12.500000 2026-11-03', 'apuntar un precio más reciente lo pone como precio actual');
select is(
  (select format('%s %s', price, price_on)
   from public.record_holding_price((select id from ids where name = 'fondo'), '2026-11-03', 13)),
  '13.000000 2026-11-03', 'otro precio el mismo día lo sustituye');
select is(
  (select format('%s %s', price, price_on)
   from public.record_holding_price((select id from ids where name = 'fondo'), '2026-10-20', 9)),
  '13.000000 2026-11-03', 'un precio de un día anterior no cambia el precio actual');
select is(
  (select string_agg(format('%s %s', priced_on, price), ' | ' order by priced_on) from public.holding_prices),
  '2026-10-20 9.000000 | 2026-11-03 13.000000', 'el histórico tiene un precio por día');
select throws_ok(
  $$ select public.record_holding_price((select id from ids where name = 'fondo'), '2026-11-04', -1) $$,
  '23514', null, 'el precio no puede ser negativo');
select throws_ok(
  $$ select public.record_holding_price((select id from ids where name = 'fondo'), '2026-11-04', 999) $$,
  'P0001', null, 'si falla el precio actual del activo, la llamada falla');
select is(
  (select count(*)::int from public.holding_prices where priced_on = '2026-11-04'),
  0, 'y tampoco queda el precio en el histórico');

-- Bruno, del mismo hogar ------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select throws_ok(
  $$ select pg_temp.operar('20000000-0000-0000-0000-000000000008', 'buy', 1, '2026-11-04') $$,
  '42501', null, 'Bruno no apunta operaciones en el activo de Ana');
select throws_ok(
  $$ select public.record_holding_price((select id from ids where name = 'fondo'), '2026-11-04', 1) $$,
  '23503', null, 'ni le cambia el precio');

-- Ana -------------------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s', h.price, (select count(*) from public.investment_trades t where t.holding_id = h.id))
   from public.holdings h where h.id = (select id from ids where name = 'fondo')),
  '13.000000 3', 'el activo de Ana sigue como lo dejó');

select * from finish();
rollback;
