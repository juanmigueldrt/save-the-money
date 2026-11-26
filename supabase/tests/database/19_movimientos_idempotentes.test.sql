-- Movimientos: apuntar dos veces lo mismo no duplica, y no se cambia sobre una versión antigua. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(35);

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

-- Un movimiento de prueba en una cuenta de `ids`, sin categoría, en el hogar de Ana y Bruno.
create function pg_temp.apuntar(movement uuid, cuenta text, importe bigint, dia date default '2026-11-05',
                                concepto text default 'Café de prueba')
returns setof public.transactions language sql as $$
  select * from public.create_movement(
    movement, (select id from hogar), (select id from ids where name = cuenta), null, dia, importe, concepto);
$$;

-- Cambia el importe de un movimiento, diciendo qué `updated_at` se leyó.
create function pg_temp.cambiar(movement uuid, visto timestamptz, cuenta text, importe bigint,
                                revisado timestamptz default null)
returns setof public.transactions language sql as $$
  select * from public.update_movement(
    movement, visto, (select id from ids where name = cuenta), null, '2026-11-05', importe, 'Café de prueba',
    null, false, revisado, null, '{}');
$$;

with x as (insert into public.accounts (household_id, name, opening_balance_minor)
           select id, 'Cuenta de Ana', 100000 from hogar returning id)
insert into ids select 'cuenta', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Ahorro de Ana' from hogar returning id)
insert into ids select 'ahorro', id from x;

-- Permisos ------------------------------------------------------------------------------
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.create_movement(uuid,uuid,uuid,uuid,date,bigint,text,text,boolean,text,text[])', 'execute'),
     has_function_privilege('authenticated', 'public.create_movement(uuid,uuid,uuid,uuid,date,bigint,text,text,boolean,text,text[])', 'execute'))),
  'f t', 'solo quien ha entrado puede apuntar');
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.update_movement(uuid,timestamptz,uuid,uuid,date,bigint,text,text,boolean,timestamptz,text,text[])', 'execute'),
     has_function_privilege('authenticated', 'public.update_movement(uuid,timestamptz,uuid,uuid,date,bigint,text,text,boolean,timestamptz,text,text[])', 'execute'))),
  'f t', 'y cambiar un movimiento');
select is(
  (select string_agg(prosecdef::text, ' ') from pg_proc
   where oid in ('public.create_movement(uuid,uuid,uuid,uuid,date,bigint,text,text,boolean,text,text[])'::regprocedure,
                 'public.update_movement(uuid,timestamptz,uuid,uuid,date,bigint,text,text,boolean,timestamptz,text,text[])'::regprocedure)),
  'false false', 'las dos funciones corren con los permisos de quien llama');

-- Apuntar ---------------------------------------------------------------------------------
select lives_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -1250) $$,
  'Ana apunta un gasto con el identificador que elige la app');
select is(
  (select format('%s %s %s %s', (select name from ids where id = t.account_id), t.amount_minor, t.description, t.booked_on)
   from public.transactions t where t.id = '20000000-0000-0000-0000-000000000001'),
  'cuenta -1250 Café de prueba 2026-11-05', 'queda guardado con ese identificador');

-- Repetir la misma petición no duplica ---------------------------------------------------
select is(
  (select id from pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -1250)),
  '20000000-0000-0000-0000-000000000001'::uuid, 'repetir la petición devuelve el movimiento guardado');
select is((select count(*)::int from public.transactions), 1, 'y no crea una segunda fila');
select is(
  (select balance_minor::int from public.account_balances where account_id = (select id from ids where name = 'cuenta')),
  98750, 'ni descuenta el dinero dos veces');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -9999) $$,
  'STM01', null, 'repetirla con otro importe falla en vez de darlo por guardado');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -1250, '2026-11-06') $$,
  'STM01', null, 'y con otro día');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'ahorro', -1250) $$,
  'STM01', null, 'y con otra cuenta');
select is(
  (select description from pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -1250, '2026-11-05', 'Otro concepto')),
  'Café de prueba', 'con otro concepto devuelve lo guardado sin cambiarlo');

-- Validaciones ---------------------------------------------------------------------------
select throws_ok(
  $$ select pg_temp.apuntar(null, 'cuenta', -1250) $$,
  '23514', null, 'hace falta el identificador');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000002', 'cuenta', 0) $$,
  '23514', null, 'el importe no puede ser cero');
select is(
  (select count(*)::int from public.transactions where id = '20000000-0000-0000-0000-000000000002'),
  0, 'y no queda nada guardado');
select lives_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000002', 'cuenta', -300) $$,
  'el mismo identificador sirve para reintentar un movimiento que no se guardó');
select throws_ok(
  $$ insert into public.transactions (id, household_id, account_id, booked_on, amount_minor, description)
     select '20000000-0000-0000-0000-000000000001', h.id, i.id, '2026-11-05', -1, 'Pisado'
     from hogar h, ids i where i.name = 'cuenta' $$,
  '23505', null, 'un insert directo con un identificador ya usado tampoco lo pisa');

-- Lo que Ana ha leído de su primer movimiento, para que otros intenten cambiarlo.
create temp table visto on commit drop as
  select id, updated_at from public.transactions where id = '20000000-0000-0000-0000-000000000001';
grant select on visto to authenticated;

-- Carla, de otro hogar -------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;
with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Carla' from hogar_carla returning id)
insert into ids select 'cuenta_carla', id from x;

select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000003', 'cuenta', -500) $$,
  '42501', null, 'quien no es del hogar no apunta en él');
select throws_ok(
  $$ select public.create_movement('20000000-0000-0000-0000-000000000001', (select id from hogar_carla),
       (select id from ids where name = 'cuenta_carla'), null, '2026-11-05', -1250, 'Café de prueba') $$,
  '23505', null, 'ni reutiliza el identificador de un movimiento de Ana desde su hogar');
select is((select count(*)::int from public.transactions), 0, 'y sigue sin ver ningún movimiento');

-- Bruno, del mismo hogar ------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Bruno' from hogar returning id)
insert into ids select 'cuenta_bruno', id from x;

select is((select count(*)::int from public.transactions), 0, 'Bruno no ve los movimientos de Ana');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta', -1250) $$,
  '42501', null, 'ni repite la petición de Ana con los mismos datos');
select throws_ok(
  $$ select pg_temp.apuntar('20000000-0000-0000-0000-000000000001', 'cuenta_bruno', -1250) $$,
  '23505', null, 'ni reutiliza su identificador con una cuenta propia');
select throws_ok(
  $$ select pg_temp.cambiar(v.id, v.updated_at, 'cuenta_bruno', -1) from visto v $$,
  'STM05', null, 'ni cambia el movimiento de Ana aunque sepa su identificador y su versión');

-- Ana -------------------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s', (select name from ids where id = t.account_id), t.amount_minor, t.description)
   from public.transactions t where t.id = '20000000-0000-0000-0000-000000000001'),
  'cuenta -1250 Café de prueba', 'el movimiento de Ana sigue como lo dejó');

-- Cambiar sobre una versión antigua --------------------------------------------------------
-- Dentro de una transacción now() no avanza, así que el movimiento se siembra con un
-- `updated_at` antiguo, con microsegundos, como superusuario.
reset role;
insert into public.transactions (id, household_id, account_id, booked_on, amount_minor, description, created_by, updated_at)
  select '20000000-0000-0000-0000-000000000004', h.id, i.id, '2026-11-05', -1000, 'Café de prueba',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar h, ids i where i.name = 'cuenta';
select pg_temp.login('00000000-0000-0000-0000-00000000000a');

select throws_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000004', '2026-11-01 10:00:00.123+00', 'cuenta', -2000) $$,
  'STM05', null, 'una versión recortada a milisegundos no es la misma: hay que mandar la fecha tal cual');
select lives_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000004', '2026-11-01T11:00:00.123456+01:00', 'cuenta', -2000) $$,
  'con la versión leída se cambia, venga escrita en la zona horaria que venga');
select is(
  (select format('%s %s', amount_minor, updated_at > '2026-11-01 10:00:00.123456+00')
   from public.transactions where id = '20000000-0000-0000-0000-000000000004'),
  '-2000 true', 'queda el importe nuevo y cambia la versión');
select throws_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000004', '2026-11-01 10:00:00.123456+00', 'cuenta', -3000) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select throws_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000004', null, 'cuenta', -3000) $$,
  'STM05', null, 'ni quien no dice qué versión leyó');
select is(
  (select amount_minor::int from public.transactions where id = '20000000-0000-0000-0000-000000000004'),
  -2000, 'el importe sigue siendo el del primer cambio');
select is(
  (select reviewed_at is not null from pg_temp.cambiar('20000000-0000-0000-0000-000000000004',
     (select updated_at from public.transactions where id = '20000000-0000-0000-0000-000000000004'),
     'cuenta', -2000, '2026-11-06 09:00:00+00')),
  true, 'con la versión nueva se puede volver a cambiar, y devuelve la fila cambiada');
select throws_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000004',
       (select updated_at from public.transactions where id = '20000000-0000-0000-0000-000000000004'),
       'cuenta_bruno', -2000) $$,
  '42501', null, 'no se puede mover a la cuenta de otra persona');

delete from public.transactions where id = '20000000-0000-0000-0000-000000000002';
select throws_ok(
  $$ select pg_temp.cambiar('20000000-0000-0000-0000-000000000002', now(), 'cuenta', -300) $$,
  'STM05', null, 'un movimiento que ya se borró tampoco se cambia');
select is((select count(*)::int from public.transactions), 2, 'Ana tiene sus dos movimientos, sin duplicados');

select * from finish();
rollback;
