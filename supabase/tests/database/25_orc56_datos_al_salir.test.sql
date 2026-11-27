-- ORC-56: qué pasa con los datos de quien sale del hogar, es quitado o borra su usuario.
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(34);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000056a', 'ana56@savethemoney.invalid', '{"username":"ana56"}'),
  ('00000000-0000-0000-0000-00000000056b', 'bruno56@savethemoney.invalid', '{"username":"bruno56"}'),
  ('00000000-0000-0000-0000-00000000056c', 'carla56@savethemoney.invalid', '{"username":"carla56"}');

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

-- Una cuenta, un movimiento y un presupuesto de quien tiene la sesión. Las 20 categorías de partida ya las tiene.
create function pg_temp.apuntar(hogar uuid, nombre text) returns void language plpgsql as $$
declare
  cuenta uuid;
begin
  insert into public.accounts (household_id, name) values (hogar, 'Cuenta de ' || nombre) returning id into cuenta;
  insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
  values (hogar, cuenta, '2026-11-02', -4500, 'Compra de ' || nombre);
  perform public.save_budget(hogar, '2026-11-01', 200000, 50::smallint, 30::smallint, 20::smallint);
end;
$$;

-- Ana crea el hogar; entran Bruno y Carla. Cada uno apunta lo suyo.
select pg_temp.login('00000000-0000-0000-0000-00000000056a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba 56');
create temp table invitaciones (para text primary key, code text) on commit drop;
grant select on hogar to authenticated;
grant select, insert on invitaciones to authenticated;
insert into invitaciones select 'bruno', code from public.create_invite((select id from hogar));
insert into invitaciones select 'carla', code from public.create_invite((select id from hogar));
insert into invitaciones select 'carla otra vez', code from public.create_invite((select id from hogar));
select pg_temp.apuntar((select id from hogar), 'Ana');

select pg_temp.login('00000000-0000-0000-0000-00000000056b');
select public.accept_invite((select code from invitaciones where para = 'bruno'));
select pg_temp.apuntar((select id from hogar), 'Bruno');

select pg_temp.login('00000000-0000-0000-0000-00000000056c');
select public.accept_invite((select code from invitaciones where para = 'carla'));
select pg_temp.apuntar((select id from hogar), 'Carla');

select pg_temp.logout();
-- 20 categorías + 1 cuenta + 1 movimiento + 1 presupuesto.
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056a'), 23, 'Ana tiene sus 23 filas');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056b'), 23, 'Bruno tiene sus 23 filas');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056c'), 23, 'Carla tiene sus 23 filas');

-- Permisos ----------------------------------------------------------------------------------
select ok(
  (select relrowsecurity from pg_class where oid = 'private.removed_members'::regclass),
  'la tabla de miembros quitados tiene RLS'
);
select table_privs_are('private', 'removed_members', 'anon', array[]::text[], 'anon no tiene ningún permiso sobre ella');
select table_privs_are('private', 'removed_members', 'authenticated', array[]::text[], 'authenticated tampoco');
select ok(not has_function_privilege('anon', 'public.removed_households()', 'execute'), 'anon no puede listar hogares anteriores');
select ok(not has_function_privilege('anon', 'public.removed_household_export(uuid)', 'execute'), 'ni exportar');
select ok(
  not has_function_privilege('authenticated', 'private.purge_member_data(uuid, uuid)', 'execute'),
  'nadie puede llamar a la función que borra los datos de otro'
);
select ok(
  not has_function_privilege('authenticated', 'private.purge_removed_members()', 'execute'),
  'ni a la purga'
);

-- Bruno sale por su cuenta -----------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000056b');
select throws_ok(
  $$ select public.removed_household_export((select id from hogar)) $$,
  '42501', null, 'un miembro actual no tiene nada que exportar por esta vía'
);
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000056b';
select is((select count(*)::int from public.removed_households()), 0, 'quien sale por su cuenta no queda como quitado');

select pg_temp.logout();
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056b'), 0, 'al salir Bruno se borra todo lo suyo');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056a'), 23, 'lo de Ana sigue');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056c'), 23, 'lo de Carla sigue');
select is((select count(*)::int from private.removed_members), 0, 'y no se guarda ningún plazo');

-- Ana quita a Carla ------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000056a');
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000056c';
select throws_ok(
  $$ select public.removed_household_export((select id from hogar)) $$,
  '42501', null, 'la dueña no puede exportar los datos de la persona que ha quitado'
);

select pg_temp.logout();
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056c'), 23, 'al quitar a Carla sus datos no se borran todavía');

select pg_temp.login('00000000-0000-0000-0000-00000000056c');
select is((select count(*)::int from public.accounts), 0, 'Carla ya no ve sus cuentas por la tabla');
select is((select count(*)::int from public.transactions), 0, 'ni sus movimientos');
select throws_ok(
  $$ insert into public.accounts (household_id, name) select id, 'Otra' from hogar $$,
  '42501', null, 'ni puede apuntar nada'
);
select results_eq(
  $$ select name, export_until - removed_at from public.removed_households() $$,
  $$ values ('Casa de prueba 56'::text, interval '30 days') $$,
  'Carla ve el hogar del que la han quitado y que tiene 30 días'
);
select is(
  (select jsonb_build_array(
     jsonb_array_length(e -> 'accounts'), jsonb_array_length(e -> 'categories'), jsonb_array_length(e -> 'movements'),
     e -> 'accounts' -> 0 ->> 'name', e -> 'movements' -> 0 ->> 'description', e -> 'movements' -> 0 -> 'amount_minor',
     e -> 'movements' -> 0 ? 'created_by')
   from public.removed_household_export((select id from hogar)) e),
  '[1, 20, 1, "Cuenta de Carla", "Compra de Carla", -4500, false]'::jsonb,
  'y puede exportar sus cuentas, categorías y movimientos, y sólo los suyos'
);

-- Carla vuelve a entrar dentro del plazo: no hay nada que purgar.
select public.accept_invite((select code from invitaciones where para = 'carla otra vez'));
select is((select count(*)::int from public.accounts), 1, 'si vuelve a entrar, vuelve a ver lo suyo');
select pg_temp.logout();
select is((select count(*)::int from private.removed_members), 0, 'y el plazo desaparece');
select is(private.purge_removed_members(), 0, 'la purga no toca a quien ha vuelto');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056c'), 23, 'sus datos siguen');

-- Ana la quita otra vez y pasa el plazo.
select pg_temp.login('00000000-0000-0000-0000-00000000056a');
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000056c';
select pg_temp.logout();
select is(private.purge_removed_members(), 0, 'dentro del plazo la purga no borra nada');
update private.removed_members set removed_at = now() - interval '30 days';

select pg_temp.login('00000000-0000-0000-0000-00000000056c');
select is((select count(*)::int from public.removed_households()), 0, 'pasados 30 días el hogar ya no aparece');
select throws_ok(
  $$ select public.removed_household_export((select id from hogar)) $$,
  '42501', null, 'ni se puede exportar, aunque la purga no haya pasado aún'
);

select pg_temp.logout();
select is(private.purge_removed_members(), 1, 'la purga borra a quien se le acabó el plazo');
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056c'), 0, 'y con él todo lo suyo');

-- Se borra el usuario de Ana ------------------------------------------------------------------
delete from auth.users where id = '00000000-0000-0000-0000-00000000056a';
select is(pg_temp.filas_de('00000000-0000-0000-0000-00000000056a'), 0, 'al borrar el usuario no queda ninguna fila suya');
select is(
  (select count(*)::int from public.accounts a where a.household_id = (select id from hogar))
    + (select count(*)::int from public.transactions t where t.household_id = (select id from hogar))
    + (select count(*)::int from public.categories c where c.household_id = (select id from hogar)),
  0, 'ni queda ninguna fila sin autor en el hogar'
);

select * from finish();
rollback;
