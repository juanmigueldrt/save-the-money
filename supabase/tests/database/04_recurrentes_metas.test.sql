-- Pruebas de RLS de pagos recurrentes y metas. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

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

-- Ana crea una suscripción y una meta -------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
with s as (
  insert into public.recurring_series (household_id, name, kind, amount_minor, starts_on)
  select id, 'Plataforma de vídeo', 'subscription', 1299, '2026-11-05' from hogar_ana
  returning id
)
insert into ids select 'serie', id from s;
with g as (
  insert into public.goals (household_id, name, kind, target_minor, monthly_plan_minor)
  select id, 'Fondo de emergencia', 'savings', 300000, 25000 from hogar_ana
  returning id
)
insert into ids select 'meta', id from g;
select lives_ok(
  $$ insert into public.goal_contributions (household_id, goal_id, amount_minor, made_on)
     select (select id from hogar_ana), (select id from ids where name = 'meta'), 25000, '2026-11-01' $$,
  'Ana aporta a la meta'
);
select is((select created_by from public.goals), '00000000-0000-0000-0000-00000000000a'::uuid, 'created_by se rellena solo');

select throws_ok(
  $$ insert into public.recurring_series (household_id, name, amount_minor, starts_on)
     select id, 'Gratis', 0, '2026-11-01' from hogar_ana $$,
  '23514', null, 'el importe de un pago recurrente tiene que ser positivo'
);
select throws_ok(
  $$ insert into public.recurring_series (household_id, name, amount_minor, starts_on, ends_on)
     select id, 'Al revés', 100, '2026-11-01', '2026-10-01' from hogar_ana $$,
  '23514', null, 'no puede acabar antes de empezar'
);
select throws_ok(
  $$ insert into public.goal_contributions (household_id, goal_id, amount_minor, made_on)
     select (select id from hogar_ana), (select id from ids where name = 'meta'), 0, '2026-11-01' $$,
  '23514', null, 'una aportación de cero no vale'
);
select throws_ok(
  $$ update public.goals set household_id = (select id from hogar_carla) $$,
  '42501', null, 'el hogar de una meta no se puede cambiar'
);

-- Bruno, del mismo hogar, lo ve y lo puede tocar ------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.recurring_series), 1, 'Bruno ve la suscripción del hogar');
select is((select count(*)::int from public.goal_contributions), 1, 'y las aportaciones a la meta');
select lives_ok(
  $$ update public.recurring_series set amount_minor = 1499 $$,
  'Bruno cambia el precio de la suscripción'
);

-- Carla, de otro hogar ----------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.recurring_series), 0, 'Carla no ve pagos recurrentes ajenos');
select is((select count(*)::int from public.goals), 0, 'ni metas ajenas');
select is((select count(*)::int from public.goal_contributions), 0, 'ni sus aportaciones');
select throws_ok(
  $$ insert into public.goals (household_id, name, target_minor)
     select id, 'Intrusa', 100 from hogar_ana $$,
  '42501', null, 'Carla no puede crear metas en un hogar ajeno'
);
select throws_ok(
  $$ insert into public.goal_contributions (household_id, goal_id, amount_minor, made_on)
     select (select id from hogar_carla), (select id from ids where name = 'meta'), 100, '2026-11-01' $$,
  '23503', null, 'ni aportar a una meta ajena desde su hogar'
);
update public.goals set name = 'Cambiada';
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select name from public.goals), 'Fondo de emergencia', 'Carla no puede cambiar metas ajenas');

select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.recurring_series $$, '42501', null, 'anon no lee pagos recurrentes');
select throws_ok($$ select * from public.goals $$, '42501', null, 'anon no lee metas');
reset role;

select * from finish();
rollback;
