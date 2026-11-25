-- Transferencias atómicas (pago de la tarjeta): las dos patas o ninguna, y sin duplicar. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

-- Ana y Bruno comparten hogar; Carla tiene el suyo.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
create temp table ids (name text primary key, id uuid) on commit drop;
grant select on hogar, invitacion to authenticated;
grant select, insert on ids to authenticated;

-- Una transferencia de prueba entre dos cuentas de `ids`, sin categoría.
create function pg_temp.pagar(transfer uuid, origen text, destino text, importe bigint, concepto_destino text default 'Pago de la tarjeta',
                              dia date default '2026-11-04')
returns setof public.transactions language sql as $$
  select * from public.create_transfer(
    transfer, (select id from hogar), (select id from ids where name = origen), (select id from ids where name = destino),
    dia, importe, null, 'Pago de Tarjeta de prueba', concepto_destino);
$$;

with x as (insert into public.accounts (household_id, name, opening_balance_minor)
           select id, 'Cuenta de Ana', 100000 from hogar returning id)
insert into ids select 'cuenta', id from x;
with x as (insert into public.accounts (household_id, name, kind)
           select id, 'Tarjeta de prueba', 'credit_card' from hogar returning id)
insert into ids select 'tarjeta', id from x;
insert into ids select 'transferencia', id from public.categories where kind = 'transfer';
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
  select h.id, i.id, '2026-10-10', -30000, 'Compra de prueba' from hogar h, ids i where i.name = 'tarjeta';

-- Permisos ------------------------------------------------------------------------------
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.create_transfer(uuid,uuid,uuid,uuid,date,bigint,uuid,text,text,text,boolean,text,text[])', 'execute'),
     has_function_privilege('authenticated', 'public.create_transfer(uuid,uuid,uuid,uuid,date,bigint,uuid,text,text,text,boolean,text,text[])', 'execute'))),
  'f t', 'solo quien ha entrado puede transferir');
select is(
  (select prosecdef from pg_proc where oid = 'public.create_transfer(uuid,uuid,uuid,uuid,date,bigint,uuid,text,text,text,boolean,text,text[])'::regprocedure),
  false, 'la función corre con los permisos de quien llama');

-- El pago: las dos patas ----------------------------------------------------------------
select lives_ok(
  $$ select public.create_transfer('10000000-0000-0000-0000-000000000001', (select id from hogar),
       (select id from ids where name = 'cuenta'), (select id from ids where name = 'tarjeta'),
       '2026-11-04', 30000, (select id from ids where name = 'transferencia'), 'Pago de Tarjeta de prueba', 'Pago de la tarjeta') $$,
  'Ana paga la tarjeta desde su cuenta');
select is(
  (select string_agg(format('%s %s %s', (select name from ids where id = t.account_id), t.amount_minor, t.description), ' | '
                     order by t.transfer_out desc)
   from public.transactions t where t.transfer_id = '10000000-0000-0000-0000-000000000001'),
  'cuenta -30000 Pago de Tarjeta de prueba | tarjeta 30000 Pago de la tarjeta',
  'quedan la salida de la cuenta y la entrada en la tarjeta');
select is(
  (select string_agg(format('%s %s', (select name from ids where id = b.account_id), b.balance_minor), ' | '
                     order by b.balance_minor desc)
   from public.account_balances b),
  'cuenta 70000 | tarjeta 0', 'y los saldos cuadran');

-- Repetir la misma petición no duplica ---------------------------------------------------
select is(
  (select string_agg(amount_minor::text, ' ' order by amount_minor)
   from pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'cuenta', 'tarjeta', 30000)),
  '-30000 30000', 'repetir la petición devuelve las dos patas guardadas');
select is((select count(*)::int from public.transactions), 3, 'y no apunta nada nuevo');
select is(
  (select string_agg(description, ' | ' order by amount_minor)
   from pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'cuenta', 'tarjeta', 30000, 'Otro concepto')),
  'Pago de Tarjeta de prueba | Pago de la tarjeta', 'el concepto no cuenta: manda lo que ya estaba guardado');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'cuenta', 'tarjeta', 99900) $$,
  'STM01', null, 'repetirla con otro importe falla en vez de darlo por guardado');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'cuenta', 'tarjeta', 30000, 'Pago de la tarjeta', '2026-11-05') $$,
  'STM01', null, 'y con otro día');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'tarjeta', 'cuenta', 30000) $$,
  'STM01', null, 'y con las cuentas cambiadas');
select is((select count(*)::int from public.transactions), 3, 'ninguno de esos intentos apunta nada');
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, transfer_id, transfer_out)
     select h.id, i.id, '2026-11-04', -30000, 'Otra salida', '10000000-0000-0000-0000-000000000001', true
     from hogar h, ids i where i.name = 'cuenta' $$,
  '23505', null, 'el índice único impide una segunda salida de la misma transferencia');
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, transfer_id)
     select h.id, i.id, '2026-11-04', -100, 'A medias', '10000000-0000-0000-0000-000000000009'
     from hogar h, ids i where i.name = 'cuenta' $$,
  '23514', null, 'una pata dice si es la salida o la entrada');

-- Las dos patas o ninguna ----------------------------------------------------------------
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000002', 'cuenta', 'tarjeta', 5000, '   ') $$,
  '23514', null, 'si la segunda pata no vale, la transferencia falla');
select is(
  (select count(*)::int from public.transactions where transfer_id = '10000000-0000-0000-0000-000000000002'),
  0, 'y no queda la primera');
select is(
  (select balance_minor::int from public.account_balances where account_id = (select id from ids where name = 'cuenta')),
  70000, 'ni sale dinero de la cuenta');
select lives_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000002', 'cuenta', 'tarjeta', 5000) $$,
  'el mismo identificador sirve para reintentar una transferencia que no se guardó');

-- Validaciones ---------------------------------------------------------------------------
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000003', 'cuenta', 'tarjeta', 0) $$,
  '23514', null, 'el importe no puede ser cero');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000003', 'cuenta', 'tarjeta', -5000) $$,
  '23514', null, 'ni negativo');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000003', 'cuenta', 'cuenta', 5000) $$,
  '23514', null, 'las dos cuentas tienen que ser distintas');

-- Carla, de otro hogar -------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;
with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Carla' from hogar_carla returning id)
insert into ids select 'cuenta_carla', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Ahorro de Carla' from hogar_carla returning id)
insert into ids select 'ahorro_carla', id from x;

select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000004', 'cuenta', 'tarjeta', 5000) $$,
  '23503', null, 'quien no es del hogar no transfiere entre sus cuentas');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000004', 'cuenta_carla', 'ahorro_carla', 5000) $$,
  '23503', null, 'ni apunta en ese hogar con cuentas del suyo');

-- Bruno, del mismo hogar ------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Bruno' from hogar returning id)
insert into ids select 'cuenta_bruno', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Ahorro de Bruno' from hogar returning id)
insert into ids select 'ahorro_bruno', id from x;

select is((select count(*)::int from public.transactions), 0, 'Bruno no ve el pago de Ana');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000005', 'cuenta', 'cuenta_bruno', 5000) $$,
  '23503', null, 'ni saca dinero de la cuenta de Ana');
select throws_ok(
  $$ select public.create_transfer('10000000-0000-0000-0000-000000000005', (select id from hogar),
       (select id from ids where name = 'cuenta_bruno'), (select id from ids where name = 'ahorro_bruno'),
       '2026-11-04', 5000, (select id from ids where name = 'transferencia'), 'Con categoría ajena', 'Con categoría ajena') $$,
  '42501', null, 'ni usa una categoría de Ana');
select throws_ok(
  $$ select pg_temp.pagar('10000000-0000-0000-0000-000000000001', 'cuenta_bruno', 'ahorro_bruno', 5000) $$,
  '23505', null, 'ni reutiliza el identificador de una transferencia de Ana');
select is(
  (select string_agg(amount_minor::text, ' ' order by amount_minor)
   from pg_temp.pagar('10000000-0000-0000-0000-000000000005', 'cuenta_bruno', 'ahorro_bruno', 5000)),
  '-5000 5000', 'Bruno transfiere entre sus cuentas');
select is((select count(*)::int from public.transactions), 2, 'y solo ve sus dos movimientos');

-- Ana -------------------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.transactions), 5, 'Ana sigue con su compra y sus dos pagos');
select is(
  (select string_agg(format('%s %s', (select name from ids where id = b.account_id), b.balance_minor), ' | '
                     order by b.balance_minor desc)
   from public.account_balances b),
  'cuenta 65000 | tarjeta 5000', 'y sus saldos no los ha tocado nadie');

select * from finish();
rollback;
