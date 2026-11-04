-- Empezar de cero con una tarjeta que tiene cuenta de pago (fallaba antes de 20261109). Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

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

-- Ana crea una tarjeta, una cuenta corriente y una compra --------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
with a as (
  insert into public.accounts (household_id, name, kind) select id, 'Cuenta de prueba', 'checking' from hogar_ana
  returning id
) insert into ids select 'corriente', id from a;
with a as (
  insert into public.accounts (household_id, name, kind) select id, 'Tarjeta de prueba', 'credit_card' from hogar_ana
  returning id
) insert into ids select 'tarjeta', id from a;
with t as (
  insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
  select (select id from hogar_ana), (select id from ids where name = 'tarjeta'), '2026-11-03', -60000, 'Compra de prueba'
  returning id
) insert into ids select 'compra', id from t;

select lives_ok(
  $$ insert into public.credit_cards (account_id, household_id, credit_limit_minor, pay_from_account_id)
     select (select id from ids where name = 'tarjeta'), (select id from hogar_ana), 300000,
            (select id from ids where name = 'corriente') $$,
  'Ana pone las condiciones de su tarjeta'
);
select row_eq(
  $$ select statement_day::int, payment_day::int, payment_delay_months::int, payment_mode::text,
            min_payment_percent, min_payment_minor, revolving_rate, installment_rate
     from public.credit_cards $$,
  row(1, 1, 1, 'full'::text, 3.00::numeric(5,2), 1500::bigint, 20.00::numeric(5,2), 14.00::numeric(5,2)),
  'los valores por defecto son los de un contrato habitual'
);
select throws_ok(
  $$ insert into public.credit_cards (account_id, household_id, credit_limit_minor)
     select (select id from ids where name = 'corriente'), (select id from hogar_ana), 100000 $$,
  '23514', null, 'una cuenta corriente no puede tener condiciones de tarjeta'
);
select throws_ok(
  $$ update public.credit_cards set payment_mode = 'fixed' $$,
  '23514', null, 'la cuota fija necesita un importe'
);
select lives_ok(
  $$ update public.credit_cards set payment_mode = 'fixed', fixed_payment_minor = 20000 $$,
  'con importe sí'
);
select throws_ok(
  $$ update public.credit_cards set pay_from_account_id = account_id $$,
  '23514', null, 'la tarjeta no se paga a sí misma'
);
select throws_ok(
  $$ update public.credit_cards set statement_day = 31 $$,
  '23514', null, 'el día del extracto va del 1 al 28'
);
select lives_ok(
  $$ insert into public.card_installments (household_id, account_id, transaction_id, months)
     select (select id from hogar_ana), (select id from ids where name = 'tarjeta'), (select id from ids where name = 'compra'), 6 $$,
  'Ana aplaza la compra a 6 meses'
);
select throws_ok(
  $$ insert into public.card_installments (household_id, account_id, transaction_id, months)
     select (select id from hogar_ana), (select id from ids where name = 'tarjeta'), (select id from ids where name = 'compra'), 3 $$,
  '23505', null, 'una compra sólo se aplaza una vez'
);

select lives_ok($$ select public.reset_household((select id from hogar_ana)) $$,
  'Ana empieza de cero aunque la tarjeta tenga cuenta de pago y un aplazado');
select is(
  (select count(*)::int from public.accounts) + (select count(*)::int from public.credit_cards)
    + (select count(*)::int from public.card_installments),
  0, 'no quedan cuentas, tarjetas ni aplazados'
);
select is((select count(*)::int from public.categories), 20, 'y vuelven las categorías de partida');
select * from finish();
rollback;
