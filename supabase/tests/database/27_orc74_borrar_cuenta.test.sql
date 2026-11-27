-- ORC-74: borrar mi cuenta se lleva todo lo mío y no toca lo de los demás.
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000074a', 'ana74@savethemoney.invalid', '{"username":"ana74"}'),
  ('00000000-0000-0000-0000-00000000074b', 'bruno74@savethemoney.invalid', '{"username":"bruno74"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

-- Filas de ese autor en las quince tablas con created_by. Se llama sin sesión: no pasa por el RLS.
create function pg_temp.filas_de(autor uuid) returns int language plpgsql as $$
declare
  t text;
  parcial int;
  total int := 0;
begin
  foreach t in array array[
    'accounts', 'categories', 'transactions', 'budgets', 'extra_budgets', 'recurring_series', 'recurring_charges',
    'goals', 'goal_contributions', 'holdings', 'holding_prices', 'investment_trades', 'investment_plans',
    'credit_cards', 'card_installments'
  ] loop
    execute format('select count(*)::int from public.%I where created_by = $1', t) into parcial using autor;
    total := total + parcial;
  end loop;
  return total;
end;
$$;

create function pg_temp.apuntar(hogar uuid, nombre text) returns void language plpgsql as $$
declare
  cuenta uuid;
begin
  insert into public.accounts (household_id, name) values (hogar, 'Cuenta de ' || nombre) returning id into cuenta;
  insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
  values (hogar, cuenta, '2026-11-02', -4500, 'Compra de ' || nombre);
end;
$$;

-- Ana es propietaria de un hogar con Bruno dentro y de otro en el que está sola. Los dos apuntan.
select pg_temp.login('00000000-0000-0000-0000-00000000074a');
create temp table compartido on commit drop as select * from public.create_household('Casa compartida 74');
create temp table sola on commit drop as select * from public.create_household('Casa de Ana 74');
create temp table invitacion on commit drop as select * from public.create_invite((select id from compartido));
grant select on compartido, sola, invitacion to authenticated;
select pg_temp.apuntar((select id from compartido), 'Ana');
select pg_temp.apuntar((select id from sola), 'Ana');
insert into public.credit_scores (score, max_score, recorded_on) values (700, 850, '2026-11-01');

select pg_temp.login('00000000-0000-0000-0000-00000000074b');
select public.accept_invite((select code from invitacion));
select pg_temp.apuntar((select id from compartido), 'Bruno');

select pg_temp.logout();
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000074a'), 44, 'Ana tiene 44 filas: 20 categorías, una cuenta y un movimiento en cada hogar');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000074b'), 22, 'Bruno tiene 22');

-- Permisos ------------------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.delete_my_account()', 'execute'), 'anon no puede borrar cuentas');
select set_config('role', 'authenticated', true);
select throws_ok($$ select public.delete_my_account() $$, '28000', null, 'sin sesión no se borra nada');
select pg_temp.logout();
select is((select count(*)::int from auth.users where email like '%74@savethemoney.invalid'), 2, 'y siguen los dos usuarios');

-- Ana borra su cuenta ---------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000074a');
select lives_ok($$ select public.delete_my_account() $$, 'Ana borra su cuenta');
select pg_temp.logout();

select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-00000000074a'), 0, 'su usuario ya no existe');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000074a'), 0, 'ni su perfil');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000074a'), 0, 'ni ninguna fila suya');
select is((select count(*)::int from public.credit_scores where user_id = '00000000-0000-0000-0000-00000000074a'), 0, 'ni su historial de crédito');
select is((select count(*)::int from public.household_members where user_id = '00000000-0000-0000-0000-00000000074a'), 0, 'ni sus membresías');
select is((select count(*)::int from public.households where id = (select id from sola)), 0, 'el hogar en el que estaba sola se borra');
select is((select count(*)::int from public.households where id = (select id from compartido)), 1, 'el compartido sigue');
select is(
  (select m.role::text from public.household_members m where m.user_id = '00000000-0000-0000-0000-00000000074b'),
  'owner', 'y pasa a ser de Bruno'
);
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000074b'), 22, 'lo de Bruno no se toca');

-- Bruno sigue usando su hogar.
select pg_temp.login('00000000-0000-0000-0000-00000000074b');
select is((select count(*)::int from public.accounts), 1, 'Bruno sigue viendo su cuenta');

select * from finish();
rollback;
