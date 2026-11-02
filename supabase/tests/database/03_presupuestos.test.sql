-- Pruebas de RLS del presupuesto mensual. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

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
create temp table super on commit drop as
  select id from public.categories where household_id = (select id from hogar_ana) and name = 'Supermercado';
grant select on super to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;

-- Ana guarda su presupuesto ------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok(
  format($$ select public.save_budget(%L, '2026-11-15', 200000, 50::smallint, 30::smallint, 20::smallint,
            jsonb_build_array(jsonb_build_object('category_id', %L, 'limit_minor', 40000))) $$,
         (select id from hogar_ana), (select id from super)),
  'Ana guarda el presupuesto de noviembre'
);
select is((select month from public.budgets), '2026-11-01'::date, 'el mes se guarda como su primer día');
select is((select count(*)::int from public.budget_lines), 1, 'con un límite de categoría');

select lives_ok(
  format($$ select public.save_budget(%L, '2026-11-01', 250000, 60::smallint, 20::smallint, 20::smallint, '[]'::jsonb) $$,
         (select id from hogar_ana)),
  'guardar otra vez el mismo mes lo actualiza'
);
select is((select count(*)::int from public.budgets), 1, 'sigue habiendo un solo presupuesto para el mes');
select is((select expected_income_minor from public.budgets), 250000::bigint, 'con los ingresos nuevos');
select is((select count(*)::int from public.budget_lines), 0, 'y los límites que ya no están se quitan');

select throws_ok(
  format($$ select public.save_budget(%L, '2026-12-01', 1000, 50::smallint, 30::smallint, 30::smallint, '[]'::jsonb) $$,
         (select id from hogar_ana)),
  '23514', null, 'los porcentajes tienen que sumar 100'
);

-- Carla, de otro hogar ----------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.budgets), 0, 'Carla no ve presupuestos ajenos');
select throws_ok(
  format($$ select public.save_budget(%L, '2026-11-01', 1, 50::smallint, 30::smallint, 20::smallint, '[]'::jsonb) $$,
         (select id from hogar_ana)),
  '42501', null, 'Carla no puede guardar un presupuesto en un hogar ajeno'
);
select throws_ok(
  format($$ select public.save_budget(%L, '2026-11-01', 1, 50::smallint, 30::smallint, 20::smallint,
            jsonb_build_array(jsonb_build_object('category_id', %L, 'limit_minor', 1))) $$,
         (select id from hogar_carla), (select id from super)),
  '23503', null, 'ni usar una categoría de otro hogar en el suyo'
);

select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.budgets $$, '42501', null, 'anon no lee presupuestos');
reset role;

select * from finish();
rollback;
