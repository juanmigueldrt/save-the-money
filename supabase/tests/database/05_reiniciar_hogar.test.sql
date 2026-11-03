-- Pruebas de "Borrar datos y empezar de cero" y de las categorías propias. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar_ana on commit drop as select * from public.create_household('Casa de prueba');
grant select on hogar_ana to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;

-- Carla apunta algo en su hogar.
insert into public.accounts (household_id, name) select id, 'Cuenta de Carla' from hogar_carla;

-- Ana apunta de todo y crea una categoría propia ---------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok(
  $$ insert into public.categories (household_id, name, kind, budget_group, icon)
     select id, 'Mascotas', 'expense', 'needs', 'pawprint' from hogar_ana $$,
  'Ana crea una categoría propia'
);
select throws_ok(
  $$ insert into public.categories (household_id, name, kind) select id, 'mascotas', 'expense' from hogar_ana $$,
  '23505', null, 'no se repite el nombre de una categoría (sin mirar mayúsculas)'
);
select lives_ok(
  $$ update public.categories set name = 'Animales', icon = 'hare' where name = 'Mascotas' $$,
  'y la renombra'
);
insert into public.accounts (household_id, name) select id, 'Cuenta común' from hogar_ana;
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
select a.household_id, a.id, '2026-11-01', -1500, 'Pienso' from public.accounts a where a.name = 'Cuenta común';
insert into public.recurring_series (household_id, name, amount_minor, starts_on)
select id, 'Plataforma de vídeo', 1299, '2026-11-05' from hogar_ana;
insert into public.goals (household_id, name, target_minor) select id, 'Vacaciones', 100000 from hogar_ana;
insert into public.budgets (household_id, month) select id, '2026-11-01' from hogar_ana;

select is((select count(*)::int from public.categories), 21, 'Ana tiene las 20 de partida más la suya');

-- Carla no puede vaciar el hogar de Ana -----------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$ select public.reset_household((select id from hogar_ana)) $$,
  '42501', null, 'Carla no puede borrar los datos de un hogar ajeno'
);
select throws_ok(
  $$ select public.reset_household(null) $$,
  '42501', null, 'ni pasando un hogar vacío'
);

-- Ana empieza de cero -----------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok($$ select public.reset_household((select id from hogar_ana)) $$, 'Ana borra los datos de su hogar');
select is((select count(*)::int from public.accounts), 0, 'ya no hay cuentas');
select is((select count(*)::int from public.transactions), 0, 'ni movimientos');
select is((select count(*)::int from public.recurring_series) + (select count(*)::int from public.goals)
          + (select count(*)::int from public.budgets), 0, 'ni pagos fijos, metas o presupuestos');
select is((select count(*)::int from public.categories), 20, 'vuelven las 20 categorías de partida');
select is((select count(*)::int from public.household_members), 1, 'Ana sigue en su hogar');

-- Lo de Carla sigue ahí.
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.accounts), 1, 'la cuenta de Carla no se ha tocado');

select pg_temp.logout();
set local role anon;
select throws_ok(
  $$ select public.reset_household('00000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'anon no puede llamar a reset_household'
);
reset role;

select * from finish();
rollback;
