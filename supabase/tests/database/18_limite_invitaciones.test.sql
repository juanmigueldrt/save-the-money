-- Límite de intentos de accept_invite y códigos sin sesgo (ORC-58).
-- Usuarios y hogares inventados; nunca datos reales.
begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000005a', 'ana58@savethemoney.invalid', '{"username":"ana58"}'),
  ('00000000-0000-0000-0000-00000000005b', 'bruno58@savethemoney.invalid', '{"username":"bruno58"}'),
  ('00000000-0000-0000-0000-00000000005c', 'carla58@savethemoney.invalid', '{"username":"carla58"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

create function pg_temp.intentos(user_id uuid) returns int language sql as $$
  select count(*)::int from private.invite_attempts a where a.user_id = $1;
$$;

-- Tabla de intentos ----------------------------------------------------------------
select ok(
  (select relrowsecurity from pg_class where oid = 'private.invite_attempts'::regclass),
  'la tabla de intentos tiene RLS'
);
select table_privs_are('private', 'invite_attempts', 'anon', array[]::text[], 'anon no tiene ningún permiso sobre los intentos');
select table_privs_are('private', 'invite_attempts', 'authenticated', array[]::text[], 'authenticated tampoco');
select columns_are('private', 'invite_attempts', array['id', 'user_id', 'attempted_at'], 'no se guarda el código probado');

-- Códigos sin sesgo de módulo ------------------------------------------------------
select is(
  private.invite_code_from_bytes('\xf8f9fafbfcfdfeff000102030405'::bytea), 'ABCDEF',
  'los bytes 248 a 255 se descartan'
);
select is(
  private.invite_code_from_bytes('\x1f3e5d7c9bf7'::bytea), 'AAAAA9',
  '31, 62, 93, 124 y 155 dan la primera letra y 247 la última'
);
select is(
  private.invite_code_from_bytes('\x0001020304f8f9fafbfcfdfeff'::bytea), null,
  'con menos de 6 bytes válidos no hay código'
);
select ok(
  pg_get_functiondef('public.create_invite(uuid)'::regprocedure) like '%private.invite_code_from_bytes%',
  'create_invite usa el muestreo por rechazo'
);

-- Ana crea un hogar y una invitación -------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000005a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba 58');
grant select on hogar to authenticated;
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
grant select on invitacion to authenticated;
select matches((select code from invitacion), '^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$', 'el código sigue teniendo 6 caracteres');

select pg_temp.logout();
insert into public.household_invites (household_id, code, expires_at)
select id, 'CADUC8', now() - interval '1 minute' from hogar;

-- Bruno prueba códigos -----------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000005b');
select is(public.accept_invite('ZZZZZZ'), null, 'un código inexistente devuelve null');
select throws_ok(
  $$ select * from private.invite_attempts $$,
  '42501', null, 'Bruno no puede leer los intentos'
);
select pg_temp.logout();
select is(pg_temp.intentos('00000000-0000-0000-0000-00000000005b'), 1, 'el intento fallido queda guardado aunque la llamada falle');

select pg_temp.login('00000000-0000-0000-0000-00000000005b');
select is(public.accept_invite('CADUC8'), null, 'uno caducado devuelve lo mismo que uno inexistente');
select is(public.accept_invite('ZZZZZY'), null, 'tercer fallo');
select is(public.accept_invite('ZZZZZX'), null, 'cuarto fallo');
select is(public.accept_invite('ZZZZZW'), null, 'el quinto fallo todavía se responde');
select throws_ok(
  format('select public.accept_invite(%L)', (select code from invitacion)),
  'STM04', 'too many invite attempts; retry in 15 min',
  'tras 5 fallos se rechaza incluso el código bueno, con los minutos de espera'
);
select pg_temp.logout();
select is(
  (select count(*)::int from public.household_members
   where user_id = '00000000-0000-0000-0000-00000000005b'),
  0, 'Bruno no ha entrado en el hogar'
);

-- Otro usuario no queda bloqueado ------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000005c');
select is(public.accept_invite('ZZZZZZ'), null, 'Carla puede probar aunque Bruno esté bloqueado');

-- Pasa la ventana --------------------------------------------------------------------
select pg_temp.logout();
update private.invite_attempts
set attempted_at = attempted_at - interval '15 minutes'
where user_id = '00000000-0000-0000-0000-00000000005b';

select pg_temp.login('00000000-0000-0000-0000-00000000005c');
select is(public.accept_invite('ZZZZZY'), null, 'otro fallo de Carla');
select pg_temp.logout();
select is(pg_temp.intentos('00000000-0000-0000-0000-00000000005b'), 0, 'al fallar se borran los intentos que ya no cuentan');

select pg_temp.login('00000000-0000-0000-0000-00000000005b');
select is(
  (public.accept_invite((select code from invitacion)) ->> 'id')::uuid,
  (select id from hogar),
  'pasada la ventana, Bruno entra con el código bueno y recibe el hogar'
);

select * from finish();
rollback;
