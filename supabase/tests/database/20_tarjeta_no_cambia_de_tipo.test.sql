-- Una cuenta con condiciones de tarjeta no puede cambiar de tipo (20261126090000). Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}');

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

create temp table ids (name text primary key, id uuid) on commit drop;
grant select, insert on ids to authenticated;

with a as (
  insert into public.accounts (household_id, name, kind) select id, 'Tarjeta de prueba', 'credit_card' from hogar_ana
  returning id
) insert into ids select 'tarjeta', id from a;
with a as (
  insert into public.accounts (household_id, name, kind) select id, 'Tarjeta sin condiciones', 'credit_card' from hogar_ana
  returning id
) insert into ids select 'sin_condiciones', id from a;
with a as (
  insert into public.accounts (household_id, name, kind) select id, 'Cuenta heredada', 'credit_card' from hogar_ana
  returning id
) insert into ids select 'heredada', id from a;

select lives_ok(
  $$ insert into public.credit_cards (account_id, household_id, credit_limit_minor)
     select (select id from ids where name = 'tarjeta'), (select id from hogar_ana), 300000 $$,
  'Ana pone condiciones a su tarjeta'
);
select throws_ok(
  $$ update public.accounts set kind = 'checking' where id = (select id from ids where name = 'tarjeta') $$,
  '23514', null, 'una tarjeta con condiciones no puede pasar a cuenta corriente'
);
select is(
  (select kind::text from public.accounts where id = (select id from ids where name = 'tarjeta')),
  'credit_card', 'el rechazo deja el tipo como estaba'
);
select is(
  (select count(*)::int from public.credit_cards where account_id = (select id from ids where name = 'tarjeta')),
  1, 'el rechazo no borra las condiciones'
);
select lives_ok(
  $$ update public.accounts set name = 'Tarjeta renombrada' where id = (select id from ids where name = 'tarjeta') $$,
  'renombrar una tarjeta con condiciones sigue permitido'
);
select lives_ok(
  $$ update public.accounts set kind = 'credit_card' where id = (select id from ids where name = 'tarjeta') $$,
  'guardar el mismo tipo sigue permitido'
);
select lives_ok(
  $$ update public.accounts set kind = 'checking' where id = (select id from ids where name = 'sin_condiciones') $$,
  'una tarjeta sin condiciones sí puede cambiar de tipo'
);
select is(
  (select kind::text from public.accounts where id = (select id from ids where name = 'sin_condiciones')),
  'checking', 'la tarjeta sin condiciones ya es cuenta corriente'
);

-- Fila ya inconsistente (creada antes de esta regla): se puede seguir editando, sólo no se
-- puede dejar de ser tarjeta. Se monta con el disparador apagado, como lo dejaría un dato antiguo.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok(
  $$ insert into public.credit_cards (account_id, household_id, credit_limit_minor)
     select (select id from ids where name = 'heredada'), (select id from hogar_ana), 100000 $$,
  'la cuenta heredada tiene condiciones de tarjeta'
);
select pg_temp.logout();
alter table public.accounts disable trigger accounts_card_kind;
update public.accounts set kind = 'checking' where id = (select id from ids where name = 'heredada');
alter table public.accounts enable trigger accounts_card_kind;
select pg_temp.login('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$ update public.accounts set name = 'Cuenta heredada renombrada' where id = (select id from ids where name = 'heredada') $$,
  'una fila inconsistente antigua sigue pudiendo renombrarse'
);
select lives_ok(
  $$ update public.accounts set kind = 'credit_card' where id = (select id from ids where name = 'heredada') $$,
  'una fila inconsistente antigua puede volver a ser tarjeta'
);
select is(
  (select kind::text from public.accounts where id = (select id from ids where name = 'heredada')),
  'credit_card', 'tras volver a tarjeta, la cuenta heredada es tarjeta'
);

select * from finish();
rollback;
