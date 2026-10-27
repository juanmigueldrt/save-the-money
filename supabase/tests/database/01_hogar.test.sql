-- Pruebas de RLS del hogar. Se ejecutan con `supabase test db`.
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

-- Usuarios de prueba ------------------------------------------------------------
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

-- Estructura --------------------------------------------------------------------
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'todas las tablas de public tienen RLS'
);
select is(
  (select count(*)::int from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
  0, 'anon no tiene permisos sobre ninguna tabla'
);
select is(
  (select count(*)::int from information_schema.routine_privileges
   where routine_schema = 'public' and grantee = 'anon'),
  0, 'anon no puede ejecutar ninguna función de public'
);
select is(
  (select count(*)::int from public.profiles), 3, 'el registro crea un perfil por usuario'
);
select is(
  (select username from public.profiles where id = '00000000-0000-0000-0000-00000000000b'),
  'bruno', 'el perfil toma el nombre de usuario de los metadatos'
);

-- Ana crea su hogar --------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar_ana on commit drop as select * from public.create_household('Casa de prueba');
grant select on hogar_ana to authenticated;

select is((select count(*)::int from public.households), 1, 'Ana ve su hogar');
select is(
  (select role::text from public.household_members where user_id = auth.uid()),
  'owner', 'Ana es la dueña'
);
select is(
  (select default_household_id from public.profiles where id = auth.uid()),
  (select id from hogar_ana), 'el hogar queda como predeterminado de Ana'
);

create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar_ana));
grant select on invitacion to authenticated;
select matches((select code from invitacion), '^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$', 'el código tiene 6 caracteres sin ambiguos');

-- Bruno, aún fuera del hogar ----------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.households), 0, 'Bruno no ve el hogar de Ana');
select is((select count(*)::int from public.household_invites), 0, 'Bruno no puede listar invitaciones');
select is((select count(*)::int from public.profiles), 1, 'Bruno sólo ve su perfil');
select throws_ok(
  $$ insert into public.household_members (household_id, user_id) select id, auth.uid() from hogar_ana $$,
  '42501', null, 'Bruno no puede meterse en el hogar sin invitación'
);
select throws_ok(
  $$ select public.create_invite((select id from hogar_ana)) $$,
  '42501', null, 'Bruno no puede crear invitaciones de un hogar ajeno'
);
select throws_ok(
  $$ select public.accept_invite('ZZZZZZ') $$,
  'P0002', null, 'un código inexistente da el mismo error que uno caducado'
);
update public.households set name = 'Hackeado' where id = (select id from hogar_ana);
select pg_temp.logout();
select is(
  (select name from public.households where id = (select id from hogar_ana)),
  'Casa de prueba', 'Bruno no puede renombrar un hogar ajeno'
);

-- Bruno acepta la invitación -----------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select lives_ok(
  format('select public.accept_invite(%L)', lower((select code from invitacion))),
  'Bruno se une con el código aunque lo escriba en minúsculas'
);
select is((select count(*)::int from public.households), 1, 'ahora Bruno ve el hogar');
select is((select count(*)::int from public.profiles), 2, 'Bruno ve el perfil de Ana');
select is(
  (select role::text from public.household_members where user_id = auth.uid()),
  'member', 'Bruno entra como miembro, no como dueño'
);
update public.households set name = 'Otro nombre' where id = (select id from hogar_ana);
select pg_temp.logout();
select is(
  (select name from public.households where id = (select id from hogar_ana)),
  'Casa de prueba', 'un miembro que no es dueño no renombra el hogar'
);
select is(
  (select status::text from public.household_invites where id = (select id from invitacion)),
  'accepted', 'la invitación queda aceptada'
);

-- Carla intenta reutilizar el código ---------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  format('select public.accept_invite(%L)', (select code from invitacion)),
  'P0002', null, 'un código ya usado no sirve'
);
select is((select count(*)::int from public.household_members), 0, 'Carla no ve miembros de hogares ajenos');
select is((select count(*)::int from public.profiles), 1, 'Carla sólo ve su perfil');

-- Invitación caducada -------------------------------------------------------------
select pg_temp.logout();
insert into public.household_invites (household_id, code, expires_at)
select id, 'QWERTY', now() - interval '1 minute' from hogar_ana;
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$ select public.accept_invite('QWERTY') $$,
  'P0002', null, 'una invitación caducada no sirve'
);

-- Anon --------------------------------------------------------------------------
select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.households $$, '42501', null, 'anon no lee hogares');
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon no lee perfiles');
select throws_ok($$ select public.create_household('x') $$, '42501', null, 'anon no crea hogares');
reset role;

-- Perfil: sólo se edita el propio --------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
update public.profiles set display_name = 'Cambiado' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.logout();
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  null, 'Bruno no edita el perfil de Ana'
);

select * from finish();
rollback;
