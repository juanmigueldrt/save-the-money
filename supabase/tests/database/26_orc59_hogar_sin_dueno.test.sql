-- ORC-59: el dueño no deja el hogar sin dueño, un hogar sin miembros se borra y borrarlo no arrasa lo de otros.
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(28);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000059a', 'ana59@savethemoney.invalid', '{"username":"ana59"}'),
  ('00000000-0000-0000-0000-00000000059b', 'bruno59@savethemoney.invalid', '{"username":"bruno59"}'),
  ('00000000-0000-0000-0000-00000000059c', 'carla59@savethemoney.invalid', '{"username":"carla59"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

create function pg_temp.papel(usuario uuid) returns text language sql as $$
  select m.role::text from public.household_members m where m.user_id = usuario;
$$;

-- Ana crea el hogar; entran Bruno y Carla. Bruno apunta una cuenta.
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba 59');
create temp table invitaciones (para text primary key, code text) on commit drop;
grant select on hogar to authenticated;
grant select, insert on invitaciones to authenticated;
insert into invitaciones select 'bruno', code from public.create_invite((select id from hogar));
insert into invitaciones select 'carla', code from public.create_invite((select id from hogar));
insert into invitaciones select 'sobrante', code from public.create_invite((select id from hogar));

select pg_temp.login('00000000-0000-0000-0000-00000000059b');
select public.accept_invite((select code from invitaciones where para = 'bruno'));
insert into public.accounts (household_id, name) select id, 'Cuenta de Bruno' from hogar;
select pg_temp.login('00000000-0000-0000-0000-00000000059c');
select public.accept_invite((select code from invitaciones where para = 'carla'));

-- Permisos ------------------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.transfer_household(uuid, uuid)', 'execute'), 'anon no puede traspasar hogares');
select ok(
  not has_function_privilege('authenticated', 'private.delete_household_if_empty(uuid)', 'execute'),
  'nadie puede llamar a la función que borra hogares'
);

-- El dueño no sale ni borra el hogar con otros dentro ---------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
select throws_ok(
  $$ delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000059a' $$,
  'STM08', null, 'la dueña no puede salir mientras haya otros miembros'
);
with borrados as (delete from public.households returning 1)
select is((select count(*)::int from borrados), 0, 'ni borrar el hogar con otros miembros dentro');

-- Traspaso --------------------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000059b');
select throws_ok(
  $$ select public.transfer_household((select id from hogar), '00000000-0000-0000-0000-00000000059b') $$,
  '42501', null, 'un miembro no puede hacerse dueño'
);
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
select throws_ok(
  $$ select public.transfer_household((select id from hogar), '00000000-0000-0000-0000-0000000000ff') $$,
  '42501', null, 'no se traspasa a quien no es miembro'
);
select is(pg_temp.papel('00000000-0000-0000-0000-00000000059a'), 'owner', 'tras un traspaso fallido Ana sigue de dueña');
select lives_ok(
  $$ select public.transfer_household((select id from hogar), '00000000-0000-0000-0000-00000000059a') $$,
  'traspasárselo a una misma no hace nada'
);
select lives_ok(
  $$ select public.transfer_household((select id from hogar), '00000000-0000-0000-0000-00000000059b') $$,
  'Ana traspasa el hogar a Bruno'
);
select pg_temp.logout();
select is(pg_temp.papel('00000000-0000-0000-0000-00000000059b'), 'owner', 'Bruno es el dueño');
select is(pg_temp.papel('00000000-0000-0000-0000-00000000059a'), 'member', 'y Ana pasa a miembro');
select is(
  (select count(*)::int from public.household_members m where m.household_id = (select id from hogar) and m.role = 'owner'),
  1, 'hay un solo dueño'
);

-- Ana, ya miembro, sale. Bruno quita a Carla y se queda solo.
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
select lives_ok(
  $$ delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000059a' $$,
  'Ana, que ya no es dueña, puede salir'
);
select throws_ok(
  $$ select public.transfer_household((select id from hogar), '00000000-0000-0000-0000-00000000059a') $$,
  '42501', null, 'y ya no puede traspasar nada'
);
select pg_temp.login('00000000-0000-0000-0000-00000000059b');
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000059c';

-- Carla tiene 30 días para exportar: el hogar no se puede borrar ni se borra solo ---------------------
with borrados as (delete from public.households returning 1)
select is((select count(*)::int from borrados), 0, 'Bruno no puede borrar el hogar mientras Carla pueda exportar');
select lives_ok(
  $$ delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000059b' $$,
  'Bruno, dueño y único miembro, puede salir'
);
select pg_temp.logout();
select is((select count(*)::int from public.households where id = (select id from hogar)), 1, 'el hogar sigue mientras dure el plazo de Carla');
select is((select count(*)::int from public.accounts where household_id = (select id from hogar)), 0, 'aunque lo de Bruno ya se borró al salir');
select is(
  (select count(*)::int from public.household_invites where household_id = (select id from hogar) and status = 'pending'),
  0, 'y sus invitaciones pendientes dejan de valer'
);
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
-- accept_invite no lanza con un código que ya no vale: devuelve null (ORC-58).
select is(
  public.accept_invite((select code from invitaciones where para = 'sobrante')), null,
  'nadie puede entrar en un hogar sin miembros'
);
select pg_temp.logout();

update private.removed_members set removed_at = now() - interval '30 days';
select is(private.purge_removed_members(), 1, 'al acabar el plazo la purga borra lo de Carla');
select is((select count(*)::int from public.households where id = (select id from hogar)), 0, 'y el hogar, que ya no es de nadie');
select is((select count(*)::int from public.categories where household_id = (select id from hogar)), 0, 'sin dejar ninguna fila');

-- El último miembro sale: el hogar se borra en el momento --------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000059c');
create temp table otro on commit drop as select * from public.create_household('Casa de Carla 59');
grant select on otro to authenticated;
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000059c';
select pg_temp.logout();
select is((select count(*)::int from public.households where id = (select id from otro)), 0, 'al salir el último miembro el hogar se borra');

-- El dueño, solo, puede borrar su hogar; y borrar su usuario no deja el hogar huérfano ---------------
select pg_temp.login('00000000-0000-0000-0000-00000000059c');
create temp table tercero on commit drop as select * from public.create_household('Otra casa de Carla 59');
create temp table cuarto on commit drop as select * from public.create_household('La última casa de Carla 59');
create temp table quinto on commit drop as select * from public.create_household('Casa de Carla y Ana 59');
grant select on tercero, cuarto, quinto to authenticated;
insert into invitaciones select 'ana', code from public.create_invite((select id from quinto));
with borrados as (delete from public.households where id = (select id from tercero) returning 1)
select is((select count(*)::int from borrados), 1, 'la dueña, sola, puede borrar su hogar');
select pg_temp.login('00000000-0000-0000-0000-00000000059a');
select public.accept_invite((select code from invitaciones where para = 'ana'));
select pg_temp.logout();
delete from auth.users where id = '00000000-0000-0000-0000-00000000059c';
select is((select count(*)::int from public.households where id = (select id from cuarto)), 0, 'al borrar el usuario su hogar sin más miembros se borra');

select is((select count(*)::int from public.households where id = (select id from quinto)), 1, 'el que tenía otro miembro sigue');
select is(pg_temp.papel('00000000-0000-0000-0000-00000000059a'), 'owner', 'y pasa a ser de ese miembro');

select * from finish();
rollback;
