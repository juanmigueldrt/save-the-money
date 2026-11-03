-- Pruebas de RLS de inversiones. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(19);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

-- Ana y Bruno comparten hogar; Carla tiene el suyo.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar_ana on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar_ana));
grant select on hogar_ana, invitacion to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;
select pg_temp.logout();

create temp table ids (name text primary key, id uuid) on commit drop;
grant select, insert on ids to authenticated;

select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'todas las tablas de public siguen con RLS'
);

-- Ana apunta un fondo, una compra y un plan mensual ---------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
with h as (
  insert into public.holdings (household_id, name, symbol, kind, price, price_on, owner_id)
  select id, 'Fondo indexado mundial', 'IE00TEST0001', 'fund', 12.345678, '2026-11-01',
         '00000000-0000-0000-0000-00000000000a'
  from hogar_ana
  returning id
)
insert into ids select 'fondo', id from h;
select lives_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price, fee_minor)
     select (select id from hogar_ana), (select id from ids where name = 'fondo'), '2026-10-01', 'buy', 10.5, 11.2, 150 $$,
  'Ana apunta una compra con participaciones fraccionarias'
);
select lives_ok(
  $$ insert into public.investment_plans (household_id, holding_id, amount_minor, starts_on, expected_annual_return)
     select (select id from hogar_ana), (select id from ids where name = 'fondo'), 10000, '2026-11-05', 6.5 $$,
  'Ana crea un plan de 100 € al mes'
);
select lives_ok(
  $$ insert into public.holding_prices (household_id, holding_id, priced_on, price)
     select (select id from hogar_ana), (select id from ids where name = 'fondo'), '2026-11-01', 12.345678 $$,
  'Ana guarda el precio en el histórico'
);
select throws_ok(
  $$ insert into public.holding_prices (household_id, holding_id, priced_on, price)
     select (select id from hogar_ana), (select id from ids where name = 'fondo'), '2026-11-01', 12.5 $$,
  '23505', null, 'sólo un precio por día y activo'
);
select throws_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, quantity, price)
     select (select id from hogar_ana), (select id from ids where name = 'fondo'), '2026-10-02', 0, 11 $$,
  '23514', null, 'una operación con 0 participaciones no vale'
);
select throws_ok(
  $$ insert into public.holdings (household_id, name, owner_id)
     select id, 'Acciones de otra persona', '00000000-0000-0000-0000-00000000000c' from hogar_ana $$,
  '42501', null, 'el dueño de un activo tiene que ser del hogar'
);

-- Bruno, del mismo hogar, lo ve y puede actualizar el precio --------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.holdings), 1, 'Bruno ve el activo del hogar');
select is((select count(*)::int from public.investment_trades), 1, 'Bruno ve la compra');
select is((select count(*)::int from public.investment_plans), 1, 'Bruno ve el plan');
update public.holdings set price = 13.1, price_on = '2026-11-03' where id = (select id from ids where name = 'fondo');
select is((select price from public.holdings where id = (select id from ids where name = 'fondo')), 13.1::numeric,
  'Bruno apunta el precio nuevo a mano');
select throws_ok(
  $$ update public.holdings set household_id = (select id from hogar_carla) $$,
  '42501', null, 'el hogar de un activo no se puede cambiar'
);

-- Carla, de otro hogar, no ve ni toca nada ----------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.holdings), 0, 'Carla no ve activos de otro hogar');
select is((select count(*)::int from public.investment_trades), 0, 'Carla no ve operaciones de otro hogar');
select is((select count(*)::int from public.holding_prices), 0, 'Carla no ve precios de otro hogar');
select throws_ok(
  $$ insert into public.holdings (household_id, name) select id, 'Intruso' from hogar_ana $$,
  '42501', null, 'Carla no puede crear activos en otro hogar'
);
-- Aunque ponga su propio hogar, no puede colgar una operación de un activo ajeno.
select throws_ok(
  $$ insert into public.investment_trades (household_id, holding_id, traded_on, quantity, price)
     select (select id from hogar_carla), (select id from ids where name = 'fondo'), '2026-10-01', 1, 1 $$,
  '23503', null, 'una operación no puede apuntar a un activo de otro hogar'
);
update public.holdings set price = 0 where id = (select id from ids where name = 'fondo');
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select price from public.holdings where id = (select id from ids where name = 'fondo')), 13.1::numeric,
  'Carla no puede cambiar el precio de un activo ajeno');

-- Empezar de cero también borra las inversiones -------------------------------------------
select public.reset_household((select id from hogar_ana));
select is((select count(*)::int from public.holdings), 0, 'reset_household borra activos, operaciones y planes');

select * from finish();
rollback;
