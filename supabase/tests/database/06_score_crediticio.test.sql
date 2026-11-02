-- Pruebas del score crediticio: es personal, ni el hogar lo ve. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true),
         set_config('request.jwt.claims', '', true);
$$;

-- Ana y Bruno comparten hogar.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
grant select on hogar, invitacion to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok(
  $$ insert into public.credit_scores (score, provider, recorded_on) values (720, 'Proveedor de prueba', '2026-11-01') $$,
  'Ana apunta su score'
);
select is((select user_id from public.credit_scores), '00000000-0000-0000-0000-00000000000a'::uuid, 'el dueño lo pone el servidor');
select throws_ok(
  $$ insert into public.credit_scores (user_id, score) values ('00000000-0000-0000-0000-00000000000b', 500) $$,
  '42501', null, 'no se puede apuntar un score a nombre de otra persona'
);
select throws_ok(
  $$ insert into public.credit_scores (score, max_score) values (900, 850) $$,
  '23514', null, 'el score no puede pasar de la escala'
);
select throws_ok(
  $$ update public.credit_scores set user_id = '00000000-0000-0000-0000-00000000000b' $$,
  '42501', null, 'ni pasárselo a otra persona'
);
select lives_ok($$ update public.credit_scores set score = 735 $$, 'Ana corrige su score');

-- Bruno, aunque es del mismo hogar, no lo ve ni lo toca.
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.credit_scores), 0, 'Bruno no ve el score de Ana');
update public.credit_scores set score = 300;
delete from public.credit_scores;
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select score::int from public.credit_scores), 735, 'Bruno no puede cambiarlo ni borrarlo');
select lives_ok($$ delete from public.credit_scores $$, 'Ana sí puede borrarlo');
select is((select count(*)::int from public.credit_scores), 0, 'y ya no está');

select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.credit_scores $$, '42501', null, 'anon no lee scores');
reset role;

select * from finish();
rollback;
