-- Fase C: día de cobro privado, presupuesto por periodo y presupuestos extra. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
create temp table ids (name text primary key, id uuid) on commit drop;
grant select on hogar, invitacion to authenticated;
grant select, insert on ids to authenticated;

-- Día de cobro --------------------------------------------------------------------------
select lives_ok(
  $$ insert into public.pay_schedules (frequency, day1, day2) values ('twice_monthly', 1, 15) $$,
  'Ana guarda que cobra el 1 y el 15');
select throws_ok(
  $$ update public.pay_schedules set day2 = 1 $$,
  '23514', null, 'el segundo día tiene que ir después del primero');
select throws_ok(
  $$ update public.pay_schedules set frequency = 'weekly', anchor_on = null $$,
  '23514', null, 'semanal necesita una fecha de cobro de referencia');

-- Presupuesto por periodo ---------------------------------------------------------------
select lives_ok(
  $$ select public.save_period_budget((select id from hogar), '2026-11-15', '2026-11-30', 150000, 50::smallint,
       30::smallint, 20::smallint, true, 90::smallint, '[]'::jsonb) $$,
  'Ana guarda un presupuesto de quincena');
select is((select format('%s %s %s %s', month, ends_on, carry_over, warn_pct) from public.budgets),
  '2026-11-15 2026-11-30 t 90', 'con sus fechas, arrastre y aviso');
select throws_ok(
  $$ select public.save_period_budget((select id from hogar), '2026-11-15', '2026-11-01', 0, 50::smallint,
       30::smallint, 20::smallint, false, 80::smallint, '[]'::jsonb) $$,
  '23514', null, 'el periodo no puede acabar antes de empezar');
select lives_ok(
  $$ select public.save_budget((select id from hogar), '2026-12-10', 1000, 50::smallint, 30::smallint, 20::smallint) $$,
  'la función por meses de las apps antiguas sigue funcionando');
select is((select ends_on from public.budgets where month = '2026-12-01'), '2026-12-31'::date,
  'y guarda el mes natural');

-- Presupuestos extra --------------------------------------------------------------------
with x as (insert into public.extra_budgets (household_id, name, limit_minor, starts_on, is_favorite)
           select id, 'Vacaciones', 80000, '2026-12-01', true from hogar returning id)
insert into ids select 'vacaciones', id from x;
with x as (insert into public.extra_budgets (household_id, name, limit_minor, starts_on, ends_on, is_favorite)
           select id, 'Regalos', 20000, '2026-12-01', '2026-12-31', true from hogar returning id)
insert into ids select 'regalos', id from x;
select is((select array_agg(name order by name) from public.extra_budgets where is_favorite), '{Regalos}'::text[],
  'sólo queda un favorito');
select throws_ok(
  $$ insert into public.extra_budgets (household_id, name, limit_minor, starts_on)
     select id, 'Mal', 0, '2026-12-01' from hogar $$,
  '23514', null, 'el límite tiene que ser mayor que cero');

-- Bruno, del mismo hogar, no ve nada de Ana -----------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select is((select count(*)::int from public.pay_schedules), 0, 'Bruno no ve el día de cobro de Ana');
select is((select count(*)::int from public.extra_budgets), 0, 'ni sus presupuestos extra');
update public.extra_budgets set limit_minor = 1 where id = (select id from ids where name = 'vacaciones');
insert into public.pay_schedules (frequency, day1) values ('monthly', 25);

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select limit_minor from public.extra_budgets where id = (select id from ids where name = 'vacaciones')),
  80000::bigint, 'y no puede cambiarlos');
select is((select format('%s %s', frequency, day1) from public.pay_schedules), 'twice_monthly 1',
  'cada uno tiene su propio día de cobro');

select * from finish();
rollback;
