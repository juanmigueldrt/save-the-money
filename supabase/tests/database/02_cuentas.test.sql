-- Pruebas de RLS de cuentas, categorías y movimientos. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

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

-- Estructura -----------------------------------------------------------------------
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'todas las tablas de public siguen con RLS'
);
select is(
  (select count(*)::int from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
  0, 'anon no tiene permisos sobre tablas ni vistas'
);
select is(
  (select count(*)::int from public.categories where household_id = (select id from hogar_ana)),
  17, 'cada hogar nuevo recibe sus categorías'
);

-- Ana crea una cuenta y un movimiento ------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
with a as (
  insert into public.accounts (household_id, name, opening_balance_minor)
  select id, 'Cuenta corriente', 100000 from hogar_ana
  returning id
)
insert into ids select 'cuenta', id from a;
insert into ids select 'super', id from public.categories
where household_id = (select id from hogar_ana) and name = 'Supermercado';
select lives_ok(
  $$ insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description)
     select h.id, (select id from ids where name = 'cuenta'), (select id from ids where name = 'super'),
            '2026-10-01', -4250, 'Compra semanal'
     from hogar_ana h $$,
  'Ana apunta un gasto en su cuenta'
);
select is(
  (select balance_minor from public.account_balances where account_id = (select id from ids where name = 'cuenta')),
  95750::bigint, 'el saldo es el inicial más los movimientos'
);
select is(
  (select created_by from public.transactions limit 1),
  '00000000-0000-0000-0000-00000000000a'::uuid, 'el movimiento queda a nombre de Ana'
);

-- Huella del CSV: la misma fila no entra dos veces --------------------------------
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, import_hash)
select id, (select id from ids where name = 'cuenta'), '2026-10-02', -1200, 'Cafetería', repeat('a', 64) from hogar_ana;
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, import_hash)
     select id, (select id from ids where name = 'cuenta'), '2026-10-02', -1200, 'Cafetería', repeat('a', 64) from hogar_ana $$,
  '23505', null, 'una fila importada repetida se rechaza'
);
select lives_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, import_hash)
     select id, (select id from ids where name = 'cuenta'), '2026-10-02', -1200, 'Cafetería', repeat('a', 64) from hogar_ana
     on conflict (account_id, import_hash) do nothing $$,
  'con on conflict do nothing la repetida se ignora sin error'
);
select is((select count(*)::int from public.transactions), 2, 'sólo hay dos movimientos');
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
     select id, (select id from ids where name = 'cuenta'), '2026-10-03', 0, 'Nada' from hogar_ana $$,
  '23514', null, 'un importe de cero no vale'
);

-- Bruno, del mismo hogar, lo ve todo y puede editar --------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.accounts), 1, 'Bruno ve la cuenta del hogar');
select is((select count(*)::int from public.transactions), 2, 'Bruno ve los movimientos del hogar');
update public.transactions set notes = 'Revisado' where description = 'Compra semanal';
select is(
  (select notes from public.transactions where description = 'Compra semanal'),
  'Revisado', 'Bruno puede anotar un movimiento del hogar'
);
select throws_ok(
  $$ update public.transactions set household_id = (select id from hogar_carla) $$,
  '42501', null, 'nadie puede mover un movimiento a otro hogar'
);

-- Carla, de otro hogar, no ve ni toca nada ------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.accounts), 0, 'Carla no ve cuentas ajenas');
select is((select count(*)::int from public.transactions), 0, 'Carla no ve movimientos ajenos');
select is((select count(*)::int from public.account_balances), 0, 'Carla no ve saldos ajenos');
select is(
  (select count(*)::int from public.categories),
  17, 'Carla sólo ve las categorías de su hogar'
);
select throws_ok(
  $$ insert into public.accounts (household_id, name) select id, 'Intrusa' from hogar_ana $$,
  '42501', null, 'Carla no crea cuentas en un hogar ajeno'
);
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
     select id, (select id from ids where name = 'cuenta'), '2026-10-05', -100, 'Truco' from hogar_carla $$,
  '23503', null, 'Carla no apunta en una cuenta ajena aunque ponga su hogar'
);
delete from public.transactions;
update public.accounts set name = 'Hackeada';
select pg_temp.logout();
select is((select count(*)::int from public.transactions), 2, 'Carla no borra movimientos ajenos');
select is(
  (select name from public.accounts where id = (select id from ids where name = 'cuenta')),
  'Cuenta corriente', 'Carla no renombra cuentas ajenas'
);

-- Cuenta personal: sólo puede ser de alguien del hogar -----------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$ insert into public.accounts (household_id, name, owner_id)
     select id, 'De Carla', '00000000-0000-0000-0000-00000000000c' from hogar_ana $$,
  '42501', null, 'una cuenta no puede ser de alguien de fuera del hogar'
);

-- Anon ---------------------------------------------------------------------------------
select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.transactions $$, '42501', null, 'anon no lee movimientos');
reset role;

select * from finish();
rollback;
