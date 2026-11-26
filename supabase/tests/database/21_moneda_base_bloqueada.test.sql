-- La moneda del hogar no se cambia con importes guardados (ORC-71).
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000071a', 'ana71@savethemoney.invalid', '{"username":"ana71"}'),
  ('00000000-0000-0000-0000-00000000071b', 'bruno71@savethemoney.invalid', '{"username":"bruno71"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

create function pg_temp.moneda() returns text language sql as $$
  select base_currency::text from public.households where name = 'Casa de prueba 71';
$$;

select function_privs_are('private', 'keep_base_currency', array[]::text[], 'authenticated', array[]::text[],
  'nadie llama a la función del trigger directamente');
select function_privs_are('private', 'keep_base_currency', array[]::text[], 'anon', array[]::text[], 'anon tampoco');

-- Hogar vacío: el dueño elige moneda ------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000071a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba 71');
grant select on hogar to authenticated;

select lives_ok(
  $$ update public.households set base_currency = 'USD' where id = (select id from hogar) $$,
  'un hogar sin importes puede cambiar de moneda'
);
select is(pg_temp.moneda(), 'USD', 'y el cambio queda guardado');
select lives_ok(
  $$ update public.households set base_currency = 'EUR' where id = (select id from hogar) $$,
  'y volver a la anterior'
);

-- Bruno entra y crea una cuenta que Ana no ve -----------------------------------------
select pg_temp.logout();
insert into public.household_members (household_id, user_id)
select id, '00000000-0000-0000-0000-00000000071b' from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000071b');
insert into public.accounts (household_id, name) select id, 'Cuenta de Bruno' from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000071a');
select is((select count(*)::int from public.accounts), 0, 'Ana no ve la cuenta de Bruno');
select throws_ok(
  $$ update public.households set base_currency = 'USD' where id = (select id from hogar) $$,
  'STM06', null, 'con una cuenta de cualquier miembro, la moneda ya no se cambia'
);
select is(pg_temp.moneda(), 'EUR', 'y sigue siendo la de antes');
select lives_ok(
  $$ update public.households set base_currency = 'EUR' where id = (select id from hogar) $$,
  'guardar la misma moneda no falla'
);
select lives_ok(
  $$ update public.households set name = 'Casa de prueba 71', month_start_day = 5 where id = (select id from hogar) $$,
  'el nombre y el día de inicio se siguen pudiendo cambiar'
);
select throws_ok(
  $$ update public.households set name = 'Casa de prueba 71', base_currency = 'GBP' where id = (select id from hogar) $$,
  'STM06', null, 'tampoco junto con otro cambio'
);

-- Sin la cuenta, pero con una meta: sigue bloqueada -----------------------------------
select pg_temp.logout();
delete from public.accounts where household_id = (select id from hogar);
insert into public.goals (household_id, name, target_minor) select id, 'Meta de prueba', 100000 from hogar;
select throws_ok(
  $$ update public.households set base_currency = 'USD' where id = (select id from hogar) $$,
  'STM06', null, 'una meta también es un importe guardado (y tampoco se salta desde postgres)'
);
delete from public.goals where household_id = (select id from hogar);
insert into public.holdings (household_id, name, kind) select id, 'Activo de prueba', 'fund' from hogar;
select throws_ok(
  $$ update public.households set base_currency = 'USD' where id = (select id from hogar) $$,
  'STM06', null, 'y un activo'
);

-- Vacío otra vez: se puede ------------------------------------------------------------
delete from public.holdings where household_id = (select id from hogar);
select pg_temp.login('00000000-0000-0000-0000-00000000071a');
select lives_ok(
  $$ update public.households set base_currency = 'USD' where id = (select id from hogar) $$,
  'al quedar vacío, el hogar puede cambiar de moneda otra vez'
);
select is(pg_temp.moneda(), 'USD', 'y el cambio queda guardado');

-- Quien no es el dueño sigue sin poder (RLS, como antes) -------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000071b');
update public.households set base_currency = 'GBP' where id = (select id from hogar);
select is(pg_temp.moneda(), 'USD', 'Bruno, que no es el dueño, no cambia la moneda');

select * from finish();
rollback;
