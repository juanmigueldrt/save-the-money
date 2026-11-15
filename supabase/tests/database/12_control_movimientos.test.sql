-- Fase B: excluido, revisado, beneficiario, etiquetas y cuenta predeterminada. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

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

with x as (insert into public.accounts (household_id, name, is_default) select id, 'Cuenta 1', true from hogar returning id)
insert into ids select 'cuenta1', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Cuenta 2' from hogar returning id)
insert into ids select 'cuenta2', id from x;
with x as (
  insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, payee, tags)
  select h.id, i.id, '2026-11-02', -4500, 'COMPRA', 'Tienda de prueba', '{viaje,casa}'
  from hogar h, ids i where i.name = 'cuenta1' returning id)
insert into ids select 'mov', id from x;

select is((select excluded from public.transactions where id = (select id from ids where name = 'mov')),
  false, 'un movimiento nuevo cuenta en el presupuesto');
select is((select tags from public.transactions where id = (select id from ids where name = 'mov')),
  '{viaje,casa}'::text[], 'guarda las etiquetas');

select lives_ok(
  $$ update public.transactions set excluded = true, reviewed_at = now(), tags = '{viaje}'
     where id = (select id from ids where name = 'mov') $$,
  'Ana excluye, revisa y cambia etiquetas de lo suyo');
select throws_ok(
  $$ update public.transactions set tags = '{"Con Espacio"}' where id = (select id from ids where name = 'mov') $$,
  '23514', null, 'una etiqueta con espacios o mayúsculas no vale');
select throws_ok(
  $$ update public.transactions set tags = '{a,b,c,d,e,f,g,h,i,j,k}' where id = (select id from ids where name = 'mov') $$,
  '23514', null, 'como mucho 10 etiquetas');
select throws_ok(
  $$ update public.transactions set payee = '   ' where id = (select id from ids where name = 'mov') $$,
  '23514', null, 'el beneficiario no puede estar en blanco');

-- Cuenta predeterminada: sólo una por persona.
select lives_ok(
  $$ update public.accounts set is_default = true where id = (select id from ids where name = 'cuenta2') $$,
  'Ana cambia de cuenta predeterminada');
select is((select count(*)::int from public.accounts where is_default), 1, 'y sólo queda una marcada');
select is((select id from public.accounts where is_default), (select id from ids where name = 'cuenta2'),
  'la nueva');
select lives_ok(
  $$ update public.accounts set include_in_net_worth = false where id = (select id from ids where name = 'cuenta1') $$,
  'Ana saca una cuenta del patrimonio');

-- Bruno, en el mismo hogar, no toca nada de Ana.
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
update public.transactions set excluded = false where id = (select id from ids where name = 'mov');
with x as (insert into public.accounts (household_id, name, is_default) select id, 'Cuenta de Bruno', true from hogar returning id)
insert into ids select 'bruno', id from x;

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select excluded from public.transactions where id = (select id from ids where name = 'mov')),
  true, 'Bruno no puede volver a incluir un movimiento de Ana');
select is((select count(*)::int from public.accounts where is_default), 1,
  'la predeterminada de Bruno no quita la de Ana');

-- Las columnas nuevas no se cuelan en el saldo: excluido sigue contando en la cuenta.
select is((select balance_minor from public.account_balances where account_id = (select id from ids where name = 'cuenta1')),
  -4500::bigint, 'excluido sigue moviendo el saldo de la cuenta');

select * from finish();
rollback;
