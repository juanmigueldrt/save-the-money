-- Fase D: cargos pendientes de los pagos fijos. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

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

with a as (insert into public.accounts (household_id, name) select id, 'Cuenta de prueba' from hogar returning id)
insert into ids select 'cuenta', id from a;
with s as (insert into public.recurring_series (household_id, name, kind, amount_minor, account_id, starts_on)
           select id, 'Plataforma de vídeo', 'subscription', 1299, (select id from ids where name = 'cuenta'), '2026-11-05'
           from hogar returning id)
insert into ids select 'serie', id from s;

select is((select format('%s %s', creates_pending, pending_from = current_date) from public.recurring_series),
  'true true', 'una serie nueva crea pendientes desde hoy');

-- Cargo pendiente -----------------------------------------------------------------------
with c as (insert into public.recurring_charges (household_id, series_id, due_on, amount_minor)
           select id, (select id from ids where name = 'serie'), '2026-11-05', -1299 from hogar returning id)
insert into ids select 'cargo', id from c;
select throws_ok(
  $$ insert into public.recurring_charges (household_id, series_id, due_on, amount_minor)
     select id, (select id from ids where name = 'serie'), '2026-11-05', -1299 from hogar $$,
  '23505', null, 'no se crea dos veces el mismo cargo');
select is((select count(*)::int from public.transactions), 0, 'un pendiente no es un movimiento');
select is((select sum(balance_minor)::int from public.account_balances), 0, 'ni cuenta en el saldo');

-- Confirmar -----------------------------------------------------------------------------
select lives_ok(
  $$ select public.confirm_recurring_charge((select id from ids where name = 'cargo'), (select id from ids where name = 'cuenta'),
       '2026-11-06', -1399, null, 'Plataforma de vídeo') $$,
  'Ana confirma el cargo con otro importe');
select is((select format('%s %s', status, amount_minor) from public.recurring_charges), 'confirmed -1399',
  'el cargo queda confirmado con el importe real');
select is((select format('%s %s', booked_on, amount_minor) from public.transactions
           where id = (select transaction_id from public.recurring_charges)), '2026-11-06 -1399',
  'y el movimiento existe');
select throws_ok(
  $$ select public.confirm_recurring_charge((select id from ids where name = 'cargo'), (select id from ids where name = 'cuenta'),
       '2026-11-06', -1399, null, 'Otra vez') $$,
  '23514', null, 'no se confirma dos veces');

-- Bruno, del mismo hogar --------------------------------------------------------------------
with c as (insert into public.recurring_charges (household_id, series_id, due_on, amount_minor)
           select id, (select id from ids where name = 'serie'), '2026-12-05', -1299 from hogar returning id)
insert into ids select 'diciembre', id from c;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select is((select count(*)::int from public.recurring_charges), 0, 'Bruno no ve los cargos de Ana');
select throws_ok(
  $$ insert into public.recurring_charges (household_id, series_id, due_on, amount_minor)
     select id, (select id from ids where name = 'serie'), '2027-01-05', -1299 from hogar $$,
  '42501', null, 'ni crea cargos en una serie de Ana');
select throws_ok(
  $$ select public.confirm_recurring_charge((select id from ids where name = 'diciembre'), (select id from ids where name = 'cuenta'),
       '2026-12-05', -1299, null, 'Intruso') $$,
  'P0002', null, 'ni confirma un cargo de Ana');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select status from public.recurring_charges where id = (select id from ids where name = 'diciembre')), 'pending',
  'el cargo de diciembre de Ana sigue pendiente');

select * from finish();
rollback;
