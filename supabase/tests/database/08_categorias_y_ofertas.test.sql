-- Categorías de impuestos, multas y tasas, y precios de oferta en los pagos fijos. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar_ana on commit drop as select * from public.create_household('Casa de prueba');
grant select on hogar_ana to authenticated;

select is(
  (select count(*)::int from public.categories
   where name in ('Impuestos', 'Multas y sanciones', 'Tasas y trámites') and budget_group = 'needs'),
  3, 'un hogar nuevo trae impuestos, multas y tasas en Necesidades'
);
select is((select count(*)::int from public.categories), 20, 'y las 20 categorías de serie');

select lives_ok(
  $$ insert into public.recurring_series (household_id, name, amount_minor, starts_on, intro_amount_minor, intro_charges)
     select id, 'Plataforma de vídeo', 1199, '2026-11-05', 699, 3 from hogar_ana $$,
  'un pago fijo con 3 cargos de oferta'
);
select is(
  (select intro_amount_minor from public.recurring_series where name = 'Plataforma de vídeo'),
  699::bigint, 'guarda el precio de oferta'
);
select throws_ok(
  $$ insert into public.recurring_series (household_id, name, amount_minor, starts_on, intro_amount_minor)
     select id, 'Sin duración', 1199, '2026-11-05', 699 from hogar_ana $$,
  '23514', null, 'la oferta necesita precio y número de cargos'
);
select throws_ok(
  $$ insert into public.recurring_series (household_id, name, amount_minor, starts_on, intro_amount_minor, intro_charges)
     select id, 'Demasiado larga', 1199, '2026-11-05', 699, 40 from hogar_ana $$,
  '23514', null, 'la oferta dura como mucho 36 cargos'
);
select lives_ok(
  $$ update public.recurring_series set intro_amount_minor = null, intro_charges = null
     where name = 'Plataforma de vídeo' $$,
  'se puede quitar la oferta'
);

select lives_ok($$ select public.reset_household((select id from hogar_ana)) $$, 'empezar de cero sigue funcionando');
select is((select count(*)::int from public.categories), 20, 'y vuelve a dejar las 20 categorías de serie');

select * from finish();
rollback;
