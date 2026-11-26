-- ORC-70: la política de lectura de movimientos, precios y operaciones deja ver exactamente lo mismo que
-- private.is_mine, y ya no ejecuta nada por fila. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(32);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}'),
  ('00000000-0000-0000-0000-00000000000d', 'dora@savethemoney.invalid', '{"username":"dora"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

-- Las claims del usuario, pero con el rol dueño de las tablas: se salta el RLS y ve todas las filas.
create function pg_temp.claims_sin_rls(user_id uuid) returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

-- Lo que se ve de las tres tablas, en una línea: descripción de los movimientos, precio (entero) y nota de las operaciones.
create function pg_temp.visibles() returns text language sql as $$
  select 'mov:' || coalesce((select string_agg(description, ',' order by description) from public.transactions), '')
      || ' precios:' || coalesce((select string_agg(price::int::text, ',' order by price) from public.holding_prices), '')
      || ' ops:' || coalesce((select string_agg(note, ',' order by note) from public.investment_trades), '');
$$;

-- Lo mismo, pero eligiendo las filas con la condición de antes: private.is_mine.
create function pg_temp.segun_is_mine() returns text language sql as $$
  select 'mov:' || coalesce((select string_agg(description, ',' order by description) from public.transactions
                             where private.is_mine(household_id, created_by)), '')
      || ' precios:' || coalesce((select string_agg(price::int::text, ',' order by price) from public.holding_prices
                                  where private.is_mine(household_id, created_by)), '')
      || ' ops:' || coalesce((select string_agg(note, ',' order by note) from public.investment_trades
                              where private.is_mine(household_id, created_by)), '');
$$;

create function pg_temp.plan_de(consulta text) returns text language plpgsql as $$
declare
  linea text;
  plan text := '';
begin
  for linea in execute 'explain (costs off) ' || consulta loop
    plan := plan || linea || E'\n';
  end loop;
  return plan;
end;
$$;

-- Ana y Bruno comparten el hogar 1; Carla tiene el hogar 2; Dora no está en ninguno.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar1 on commit drop as select * from public.create_household('Hogar uno');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar1));
grant select on hogar1, invitacion to authenticated, postgres;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar2 on commit drop as select * from public.create_household('Hogar dos');
grant select on hogar2 to authenticated, postgres;
select pg_temp.logout();

-- Las filas se cargan como dueño de las tablas para poder poner cualquier autor: uno por caso.
--   1 hogar 1, de Ana        2 hogar 1, de Bruno      3 hogar 1, sin autor (su usuario se borró)
--   4 hogar 1, de Dora (ya no es miembro)             5 hogar 2, de Ana (no es miembro)      6 hogar 2, de Carla
create temp table casos (n int primary key, hogar uuid, autor uuid, etiqueta text) on commit drop;
insert into casos values
  (1, (select id from hogar1), '00000000-0000-0000-0000-00000000000a', 'h1-ana'),
  (2, (select id from hogar1), '00000000-0000-0000-0000-00000000000b', 'h1-bruno'),
  (3, (select id from hogar1), null, 'h1-nadie'),
  (4, (select id from hogar1), '00000000-0000-0000-0000-00000000000d', 'h1-dora'),
  (5, (select id from hogar2), '00000000-0000-0000-0000-00000000000a', 'h2-ana'),
  (6, (select id from hogar2), '00000000-0000-0000-0000-00000000000c', 'h2-carla');

create temp table padres (hogar uuid primary key, cuenta uuid, activo uuid) on commit drop;
insert into padres select id, gen_random_uuid(), gen_random_uuid() from hogar1 union all
                   select id, gen_random_uuid(), gen_random_uuid() from hogar2;
insert into public.accounts (id, household_id, name, created_by)
  select cuenta, hogar, 'Cuenta', null from padres;
insert into public.holdings (id, household_id, name, created_by)
  select activo, hogar, 'Fondo', null from padres;
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, created_by)
  select c.hogar, p.cuenta, '2026-11-01', -100 * c.n, c.etiqueta, c.autor from casos c join padres p using (hogar);
insert into public.holding_prices (household_id, holding_id, priced_on, price, created_by)
  select c.hogar, p.activo, date '2026-11-01' + c.n, c.n, c.autor from casos c join padres p using (hogar);
insert into public.investment_trades (household_id, holding_id, traded_on, side, quantity, price, note, created_by)
  select c.hogar, p.activo, '2026-11-01', 'buy', 1, 10, c.etiqueta, c.autor from casos c join padres p using (hogar);

-- Lo que dejaría ver private.is_mine a cada uno, calculado sobre todas las filas (sin RLS).
create temp table segun_antes (usuario text primary key, filas text) on commit drop;
grant select on segun_antes to authenticated;
select pg_temp.claims_sin_rls('00000000-0000-0000-0000-00000000000a');
insert into segun_antes select 'ana', pg_temp.segun_is_mine();
select pg_temp.claims_sin_rls('00000000-0000-0000-0000-00000000000b');
insert into segun_antes select 'bruno', pg_temp.segun_is_mine();
select pg_temp.claims_sin_rls('00000000-0000-0000-0000-00000000000c');
insert into segun_antes select 'carla', pg_temp.segun_is_mine();
select pg_temp.claims_sin_rls('00000000-0000-0000-0000-00000000000d');
insert into segun_antes select 'dora', pg_temp.segun_is_mine();
select pg_temp.logout();
insert into segun_antes select 'sin sesión', pg_temp.segun_is_mine();

select is(pg_temp.visibles(),
  'mov:h1-ana,h1-bruno,h1-dora,h1-nadie,h2-ana,h2-carla precios:1,2,3,4,5,6 ops:h1-ana,h1-bruno,h1-dora,h1-nadie,h2-ana,h2-carla',
  'las seis filas de cada tabla están cargadas');

-- Cada usuario: lo que ve es lo escrito a mano aquí, y es lo mismo que daba private.is_mine.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(pg_temp.visibles(), 'mov:h1-ana precios:1 ops:h1-ana',
  'Ana ve sólo lo suyo de su hogar: ni lo de Bruno, ni lo que no tiene autor, ni lo que lleva su nombre en un hogar ajeno');
select is(pg_temp.visibles(), (select filas from segun_antes where usuario = 'ana'), 'Ana: lo mismo que con is_mine');

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is(pg_temp.visibles(), 'mov:h1-bruno precios:2 ops:h1-bruno', 'Bruno ve sólo lo suyo');
select is(pg_temp.visibles(), (select filas from segun_antes where usuario = 'bruno'), 'Bruno: lo mismo que con is_mine');

select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is(pg_temp.visibles(), 'mov:h2-carla precios:6 ops:h2-carla', 'Carla ve sólo lo suyo de su hogar');
select is(pg_temp.visibles(), (select filas from segun_antes where usuario = 'carla'), 'Carla: lo mismo que con is_mine');

select pg_temp.login('00000000-0000-0000-0000-00000000000d');
select is(pg_temp.visibles(), 'mov: precios: ops:', 'Dora no ve nada: sus filas siguen en un hogar del que no es miembro');
select is(pg_temp.visibles(), (select filas from segun_antes where usuario = 'dora'), 'Dora: lo mismo que con is_mine');

-- Rol authenticated sin usuario en las claims: auth.uid() es nulo.
select set_config('role', 'authenticated', true), set_config('request.jwt.claims', '', true);
select is(pg_temp.visibles(), 'mov: precios: ops:', 'sin usuario en la sesión no se ve nada, tampoco las filas sin autor');
select is(pg_temp.visibles(), (select filas from segun_antes where usuario = 'sin sesión'), 'sin usuario: lo mismo que con is_mine');
select is((select count(*)::int from private.my_household_ids()), 0, 'y la lista de hogares sale vacía');

-- Los hogares de cada uno.
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select results_eq('select * from private.my_household_ids()', 'select id from hogar1', 'my_household_ids da a Bruno su hogar y no el de Carla');
select pg_temp.login('00000000-0000-0000-0000-00000000000d');
select is_empty('select * from private.my_household_ids()', 'y a Dora, ninguno');

-- Borrar sigue igual: sólo lo propio.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
with borrados as (delete from public.transactions returning 1)
select is((select count(*)::int from borrados), 1, 'Ana sólo borra su movimiento');
with borrados as (delete from public.holding_prices returning 1)
select is((select count(*)::int from borrados), 1, 'y su precio');
with borrados as (delete from public.investment_trades returning 1)
select is((select count(*)::int from borrados), 1, 'y su operación');
select pg_temp.logout();
select is((select count(*)::int from public.transactions), 5, 'los movimientos de los demás siguen');
select is((select count(*)::int from public.holding_prices), 5, 'los precios de los demás siguen');
select is((select count(*)::int from public.investment_trades), 5, 'y sus operaciones');

-- Ya no hay nada que se ejecute por fila: el usuario y sus hogares se calculan una vez (InitPlan), sin SubPlan.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select unalike(pg_temp.plan_de('select * from public.transactions'), '%SubPlan%', 'leer movimientos no ejecuta nada por fila');
select unalike(pg_temp.plan_de('select * from public.holding_prices'), '%SubPlan%', 'ni leer precios');
select unalike(pg_temp.plan_de('select * from public.investment_trades'), '%SubPlan%', 'ni leer operaciones');
select alike(pg_temp.plan_de('select * from public.transactions'), '%InitPlan%', 'y la condición sigue en el plan, calculada una vez');
select pg_temp.logout();

-- Las políticas: mismas órdenes y mismo rol, y sólo la de lectura de estas tres tablas ha cambiado.
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename in ('transactions', 'holding_prices', 'investment_trades')
     and policyname = tablename || '_select' and cmd = 'SELECT' and permissive = 'PERMISSIVE' and roles = '{authenticated}'
     and qual like '%my_household_ids%' and qual like '%created_by%' and qual not like '%is_mine%'),
  3, 'las tres políticas de lectura son para authenticated y usan la condición nueva');
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename in ('transactions', 'holding_prices', 'investment_trades')),
  12, 'siguen siendo cuatro políticas por tabla');
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename in ('transactions', 'holding_prices', 'investment_trades')
     and cmd in ('UPDATE', 'DELETE') and qual like '%is_mine%'),
  6, 'las de cambio y borrado siguen con is_mine');

-- La función nueva y los índices.
select ok(has_function_privilege('authenticated', 'private.my_household_ids()', 'execute'), 'authenticated puede usar my_household_ids');
select ok(not has_function_privilege('anon', 'private.my_household_ids()', 'execute'), 'anon no');
select has_index('public', 'holding_prices', 'holding_prices_household_priced_idx',
  array['household_id', 'priced_on', 'id'], 'los precios tienen índice por hogar, fecha e id');
select has_index('public', 'investment_trades', 'investment_trades_household_traded_idx',
  array['household_id', 'traded_on', 'id'], 'y las operaciones');

-- Anon ---------------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select * from public.holding_prices $$, '42501', null, 'anon sigue sin leer precios');
reset role;

select * from finish();
rollback;
