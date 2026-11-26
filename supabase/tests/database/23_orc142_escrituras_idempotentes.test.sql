-- El resto de tablas (ORC-142): dar de alta dos veces lo mismo no duplica, y no se cambia sobre una
-- versión antigua. Mismo modelo que 19_movimientos_idempotentes. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(111);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

-- Ana y Bruno comparten hogar; Carla tiene el suyo.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
grant select on hogar, invitacion to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
create temp table hogar_carla on commit drop as select * from public.create_household('Piso de Carla');
grant select on hogar_carla to authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));
select pg_temp.login('00000000-0000-0000-0000-00000000000a');

-- Las funciones nuevas, para comprobar sus permisos de una vez.
create temp table funciones on commit drop as
  select p.oid, p.proname, p.prosecdef
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('create_account', 'update_account', 'create_goal', 'update_goal', 'create_goal_contribution',
                      'create_recurring_series', 'update_recurring_series', 'create_credit_card', 'update_credit_card',
                      'create_card_installment', 'update_card_installment', 'create_holding', 'update_holding',
                      'create_investment_plan', 'update_investment_plan', 'create_category', 'update_category',
                      'create_extra_budget', 'update_extra_budget', 'update_recurring_charge');
grant select on funciones to authenticated;

-- Permisos ------------------------------------------------------------------------------
select is((select count(*)::int from funciones), 20, 'están todas las funciones de alta y de cambio');
select is(
  (select coalesce(string_agg(proname, ' ' order by proname), '') from funciones
   where has_function_privilege('anon', oid, 'execute')),
  '', 'quien no ha entrado no puede llamar a ninguna');
select is(
  (select coalesce(string_agg(proname, ' ' order by proname), '') from funciones
   where not has_function_privilege('authenticated', oid, 'execute')),
  '', 'quien ha entrado puede llamarlas todas');
select is(
  (select coalesce(string_agg(proname, ' ' order by proname), '') from funciones where prosecdef),
  '', 'todas corren con los permisos de quien llama');

-- Cuentas -------------------------------------------------------------------------------
select lives_ok(
  $$ select public.create_account('30000000-0000-0000-0000-000000000001', (select id from hogar),
       'Cuenta de prueba', 'checking', 100000) $$,
  'Ana da de alta una cuenta con el identificador que elige la app');
select is(
  (select format('%s %s %s', a.name, a.kind, a.opening_balance_minor)
   from public.create_account('30000000-0000-0000-0000-000000000001', (select id from hogar),
     'Cuenta de prueba', 'checking', 100000) a),
  'Cuenta de prueba checking 100000', 'repetir la petición devuelve la cuenta guardada');
select is((select count(*)::int from public.accounts), 1, 'y no crea una segunda');
select throws_ok(
  $$ select public.create_account('30000000-0000-0000-0000-000000000001', (select id from hogar),
       'Cuenta de prueba', 'checking', 5) $$,
  'STM01', null, 'repetirla con otro saldo inicial falla en vez de darla por guardada');
select throws_ok(
  $$ select public.create_account(null, (select id from hogar), 'Sin identificador', 'checking', 0) $$,
  '23514', null, 'hace falta el identificador');

-- Una cuenta con una versión antigua, con microsegundos: dentro de una transacción now() no
-- avanza, así que se siembra como superusuario.
reset role;
insert into public.accounts (id, household_id, name, created_by, updated_at)
  select '30000000-0000-0000-0000-000000000002', id, 'Ahorro de prueba',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select public.create_account('30000000-0000-0000-0000-000000000001', (select id from hogar),
       'Cuenta de prueba', 'checking', 100000) $$,
  '23505', null, 'Bruno no reutiliza el identificador de una cuenta de Ana');
select throws_ok(
  $$ select public.update_account('30000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'De Bruno', 'savings', 0, null, null, false, true) $$,
  'STM05', null, 'ni la cambia aunque sepa su identificador y su versión');

-- Carla, de otro hogar.
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$ select public.create_account('30000000-0000-0000-0000-000000000009', (select id from hogar),
       'Cuenta de Carla', 'checking', 0) $$,
  '42501', null, 'quien no es del hogar no crea cuentas en él');
select throws_ok(
  $$ select public.create_account('30000000-0000-0000-0000-000000000001', (select id from hogar_carla),
       'Cuenta de prueba', 'checking', 100000) $$,
  '23505', null, 'ni reutiliza el identificador de una cuenta de Ana desde su hogar');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$ select public.update_account('30000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123+00',
       'Ahorro', 'savings', 0, null, null, false, true) $$,
  'STM05', null, 'una versión recortada a milisegundos no es la misma');
select is(
  (select format('%s %s %s', a.name, a.kind, a.updated_at > '2026-11-01 10:00:00.123456+00')
   from public.update_account('30000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00',
     'Ahorro', 'savings', 2500, null, null, false, true) a),
  'Ahorro savings t', 'con la versión leída se cambia, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select public.update_account('30000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'Pisada', 'savings', 1, null, null, false, true) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select throws_ok(
  $$ select public.update_account('30000000-0000-0000-0000-000000000002', null,
       'Pisada', 'savings', 1, null, null, false, true) $$,
  'STM05', null, 'ni quien no dice qué versión leyó');
select is(
  (select format('%s %s', name, opening_balance_minor) from public.accounts
   where id = '30000000-0000-0000-0000-000000000002'),
  'Ahorro 2500', 'queda lo del primer cambio');

-- Metas y aportaciones --------------------------------------------------------------------
select lives_ok(
  $$ select public.create_goal('31000000-0000-0000-0000-000000000001', (select id from hogar), 'Vacaciones',
       'savings', 200000, 0, null, null, null, null, null, null) $$,
  'Ana da de alta una meta con el identificador que elige la app');
select is(
  (select format('%s %s %s', g.name, g.kind, g.target_minor)
   from public.create_goal('31000000-0000-0000-0000-000000000001', (select id from hogar), 'Vacaciones',
     'savings', 200000, 0, null, null, null, null, null, null) g),
  'Vacaciones savings 200000', 'repetir la petición devuelve la meta guardada');
select is((select count(*)::int from public.goals), 1, 'y no crea una segunda');
select throws_ok(
  $$ select public.create_goal('31000000-0000-0000-0000-000000000001', (select id from hogar), 'Vacaciones',
       'savings', 5, 0, null, null, null, null, null, null) $$,
  'STM01', null, 'repetirla con otro objetivo falla en vez de darla por guardada');
select throws_ok(
  $$ select public.create_goal(null, (select id from hogar), 'Sin identificador', 'savings', 1, 0,
       null, null, null, null, null, null) $$,
  '23514', null, 'hace falta el identificador');

select lives_ok(
  $$ select public.create_goal_contribution('31000000-0000-0000-0000-0000000000c1', (select id from hogar),
       '31000000-0000-0000-0000-000000000001', 10000, '2026-11-05') $$,
  'Ana aporta a su meta');
select is(
  (select c.amount_minor::int
   from public.create_goal_contribution('31000000-0000-0000-0000-0000000000c1', (select id from hogar),
     '31000000-0000-0000-0000-000000000001', 10000, '2026-11-05', 'Otra nota') c),
  10000, 'repetir la aportación devuelve la guardada');
select is(
  (select format('%s %s', count(*), sum(amount_minor)) from public.goal_contributions),
  '1 10000', 'y el dinero se aporta una sola vez');
select throws_ok(
  $$ select public.create_goal_contribution('31000000-0000-0000-0000-0000000000c1', (select id from hogar),
       '31000000-0000-0000-0000-000000000001', 20000, '2026-11-05') $$,
  'STM01', null, 'repetirla con otro importe falla');
select throws_ok(
  $$ select public.create_goal_contribution(null, (select id from hogar),
       '31000000-0000-0000-0000-000000000001', 10000, '2026-11-05') $$,
  '23514', null, 'la aportación también necesita identificador');

reset role;
insert into public.goals (id, household_id, name, target_minor, created_by, updated_at)
  select '31000000-0000-0000-0000-000000000002', id, 'Coche de prueba', 500000,
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select public.create_goal('31000000-0000-0000-0000-000000000001', (select id from hogar), 'Vacaciones',
       'savings', 200000, 0, null, null, null, null, null, null) $$,
  '23505', null, 'Bruno no reutiliza el identificador de una meta de Ana');
select throws_ok(
  $$ select public.create_goal_contribution('31000000-0000-0000-0000-0000000000c2', (select id from hogar),
       '31000000-0000-0000-0000-000000000001', 10000, '2026-11-05') $$,
  '42501', null, 'ni aporta a una meta de Ana');
select throws_ok(
  $$ select public.update_goal('31000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'De Bruno', 'savings', 1, 0, null, null, null, null, null, null) $$,
  'STM05', null, 'ni la cambia aunque sepa su identificador y su versión');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s', g.name, g.target_minor, g.updated_at > '2026-11-01 10:00:00.123456+00')
   from public.update_goal('31000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00',
     'Coche', 'savings', 600000, 0, null, null, null, null, null, null) g),
  'Coche 600000 t', 'con la versión leída la meta se cambia, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select public.update_goal('31000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'Pisada', 'savings', 1, 0, null, null, null, null, null, null) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select format('%s %s', name, target_minor) from public.goals where id = '31000000-0000-0000-0000-000000000002'),
  'Coche 600000', 'queda lo del primer cambio');

-- Pagos fijos -----------------------------------------------------------------------------
-- Alquiler de 800 € al mes desde el 5 de noviembre, con aviso un día antes.
create function pg_temp.pago_fijo(series uuid, importe bigint, nombre text default 'Alquiler de prueba')
returns setof public.recurring_series language sql as $$
  select * from public.create_recurring_series(series, (select id from hogar), nombre, 'essential', importe, null, null,
    1, 'month', '2026-11-05', null, 1, null, null, null, true, null);
$$;
create function pg_temp.cambiar_pago_fijo(series uuid, visto timestamptz, importe bigint)
returns setof public.recurring_series language sql as $$
  select * from public.update_recurring_series(series, visto, 'Alquiler', 'essential', importe, null, null,
    1, 'month', '2026-11-05', null, 1, null, null, null, true, null);
$$;

select lives_ok(
  $$ select pg_temp.pago_fijo('32000000-0000-0000-0000-000000000001', 80000) $$,
  'Ana da de alta un pago fijo con el identificador que elige la app');
select is(
  (select format('%s %s %s %s %s', r.name, r.kind, r.amount_minor, r.starts_on, r.pending_from = current_date)
   from pg_temp.pago_fijo('32000000-0000-0000-0000-000000000001', 80000) r),
  'Alquiler de prueba essential 80000 2026-11-05 t',
  'repetir la petición devuelve el pago fijo guardado; sin día de pendientes, empiezan hoy');
select is((select count(*)::int from public.recurring_series), 1, 'y no crea un segundo');
select throws_ok(
  $$ select pg_temp.pago_fijo('32000000-0000-0000-0000-000000000001', 90000) $$,
  'STM01', null, 'repetirlo con otro importe falla en vez de darlo por guardado');
select throws_ok(
  $$ select pg_temp.pago_fijo(null, 80000) $$,
  '23514', null, 'hace falta el identificador');

reset role;
insert into public.recurring_series (id, household_id, name, kind, amount_minor, starts_on, pending_from, created_by, updated_at)
  select '32000000-0000-0000-0000-000000000002', id, 'Luz de prueba', 'essential', 6000, '2026-11-05', '2026-11-06',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select pg_temp.pago_fijo('32000000-0000-0000-0000-000000000001', 80000) $$,
  '23505', null, 'Bruno no reutiliza el identificador de un pago fijo de Ana');
select throws_ok(
  $$ select pg_temp.cambiar_pago_fijo('32000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'ni lo cambia aunque sepa su identificador y su versión');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s %s', r.name, r.amount_minor, r.pending_from, r.updated_at > '2026-11-01 10:00:00.123456+00')
   from pg_temp.cambiar_pago_fijo('32000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00', 7000) r),
  'Alquiler 7000 2026-11-06 t',
  'con la versión leída el pago fijo se cambia; sin día de pendientes se queda el que tenía');
select throws_ok(
  $$ select pg_temp.cambiar_pago_fijo('32000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select amount_minor::int from public.recurring_series where id = '32000000-0000-0000-0000-000000000002'),
  7000, 'queda el importe del primer cambio');

-- Tarjetas de crédito y compras aplazadas ----------------------------------------------------
-- Una tarjeta de Ana con una compra de 600 €, y otra con sus condiciones en una versión antigua.
select public.create_account('33000000-0000-0000-0000-000000000001', (select id from hogar), 'Tarjeta de prueba', 'credit_card', 0);
select public.create_account('33000000-0000-0000-0000-000000000002', (select id from hogar), 'Otra tarjeta', 'credit_card', 0);
select public.create_movement('33000000-0000-0000-0000-0000000000a1', (select id from hogar),
  '33000000-0000-0000-0000-000000000001', null, '2026-11-05', -60000, 'Portátil de prueba');
select public.create_movement('33000000-0000-0000-0000-0000000000a2', (select id from hogar),
  '33000000-0000-0000-0000-000000000002', null, '2026-11-05', -50000, 'Sofá de prueba');

create function pg_temp.condiciones(tarjeta uuid, limite bigint)
returns setof public.credit_cards language sql as $$
  select * from public.create_credit_card(tarjeta, (select id from hogar), limite, 1, 5, 1, 'full', null, 3, 1500, 20, 14,
    null, 2, 80);
$$;
create function pg_temp.cambiar_condiciones(tarjeta uuid, visto timestamptz, limite bigint)
returns setof public.credit_cards language sql as $$
  select * from public.update_credit_card(tarjeta, visto, limite, 10, 5, 1, 'full', null, 3, 1500, 20, 14, null, 2, 80);
$$;

select lives_ok(
  $$ select pg_temp.condiciones('33000000-0000-0000-0000-000000000001', 300000) $$,
  'Ana guarda las condiciones de su tarjeta');
select is(
  (select format('%s %s %s', c.credit_limit_minor, c.statement_day, c.payment_day)
   from pg_temp.condiciones('33000000-0000-0000-0000-000000000001', 300000) c),
  '300000 1 5', 'repetir la petición devuelve las condiciones guardadas');
select is((select count(*)::int from public.credit_cards), 1, 'y no crea otras');
select throws_ok(
  $$ select pg_temp.condiciones('33000000-0000-0000-0000-000000000001', 5) $$,
  'STM01', null, 'un alta con otro límite no pisa las condiciones que ya había');
select throws_ok(
  $$ select pg_temp.condiciones(null, 300000) $$,
  '23514', null, 'hace falta la cuenta de la tarjeta');

select lives_ok(
  $$ select public.create_card_installment('33000000-0000-0000-0000-0000000000a1', (select id from hogar),
       '33000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-0000000000a1', 6, 14) $$,
  'Ana aplaza una compra con el identificador que elige la app');
select is(
  (select format('%s %s', i.months, i.rate)
   from public.create_card_installment('33000000-0000-0000-0000-0000000000a1', (select id from hogar),
     '33000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-0000000000a1', 6, 14) i),
  '6 14.00', 'repetir la petición devuelve el aplazado guardado');
select is((select count(*)::int from public.card_installments), 1, 'y no crea un segundo');
select throws_ok(
  $$ select public.create_card_installment('33000000-0000-0000-0000-0000000000a1', (select id from hogar),
       '33000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-0000000000a1', 12, 14) $$,
  'STM01', null, 'repetirlo con otro plazo falla en vez de darlo por guardado');
select throws_ok(
  $$ select public.create_card_installment('33000000-0000-0000-0000-0000000000a9', (select id from hogar),
       '33000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-0000000000a1', 6, 14) $$,
  '23505', null, 'y otro aplazado para la misma compra, con otro identificador, tampoco entra');
select throws_ok(
  $$ select public.create_card_installment(null, (select id from hogar),
       '33000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-0000000000a1', 6, 14) $$,
  '23514', null, 'el aplazado también necesita identificador');

reset role;
insert into public.credit_cards (account_id, household_id, credit_limit_minor, created_by, updated_at)
  select '33000000-0000-0000-0000-000000000002', id, 200000,
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;
insert into public.card_installments (id, household_id, account_id, transaction_id, months, created_by, updated_at)
  select '33000000-0000-0000-0000-0000000000a2', id, '33000000-0000-0000-0000-000000000002',
         '33000000-0000-0000-0000-0000000000a2', 6,
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
-- Falla antes de llegar al RLS: el disparador de credit_cards no ve la cuenta de Ana. Vale cualquier error.
select throws_ok(
  $$ select pg_temp.condiciones('33000000-0000-0000-0000-000000000001', 300000) $$,
  null::char(5), null, 'Bruno no pone condiciones a una tarjeta de Ana');
select throws_ok(
  $$ select pg_temp.cambiar_condiciones('33000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'ni las cambia aunque sepa su versión');
select throws_ok(
  $$ select public.update_card_installment('33000000-0000-0000-0000-0000000000a2', '2026-11-01 10:00:00.123456+00', 3, 14) $$,
  'STM05', null, 'ni cambia un aplazado de Ana');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s', c.credit_limit_minor, c.statement_day, c.updated_at > '2026-11-01 10:00:00.123456+00')
   from pg_temp.cambiar_condiciones('33000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00', 250000) c),
  '250000 10 t', 'con la versión leída las condiciones se cambian, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select pg_temp.cambiar_condiciones('33000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select format('%s %s', i.months, i.updated_at > '2026-11-01 10:00:00.123456+00')
   from public.update_card_installment('33000000-0000-0000-0000-0000000000a2', '2026-11-01T11:00:00.123456+01:00', 9, 14) i),
  '9 t', 'con la versión leída el aplazado se cambia');
select throws_ok(
  $$ select public.update_card_installment('33000000-0000-0000-0000-0000000000a2', '2026-11-01 10:00:00.123456+00', 3, 14) $$,
  'STM05', null, 'y la versión antigua ya no vale');
select is(
  (select format('%s %s', (select credit_limit_minor from public.credit_cards where account_id = '33000000-0000-0000-0000-000000000002'),
                 (select months from public.card_installments where id = '33000000-0000-0000-0000-0000000000a2'))),
  '250000 9', 'quedan los primeros cambios');

-- Activos y planes de aportación ----------------------------------------------------------------
create function pg_temp.activo(holding uuid, tipo public.investment_kind, nombre text default 'Fondo de prueba')
returns setof public.holdings language sql as $$
  select * from public.create_holding(holding, (select id from hogar), nombre, null, tipo, 'equity', null, null,
    10.5, '2026-11-05', 0.2, null, null);
$$;
create function pg_temp.cambiar_activo(holding uuid, visto timestamptz, nombre text)
returns setof public.holdings language sql as $$
  select * from public.update_holding(holding, visto, nombre, 'FDP', 'fund', 'equity', null, null,
    12.25, '2026-11-06', 0.2, null, null);
$$;
create function pg_temp.plan(plan uuid, activo uuid, importe bigint)
returns setof public.investment_plans language sql as $$
  select * from public.create_investment_plan(plan, (select id from hogar), activo, null, importe, 1, 'month',
    '2026-12-05', null, 5, 1, null, null);
$$;
create function pg_temp.cambiar_plan(plan uuid, visto timestamptz, importe bigint)
returns setof public.investment_plans language sql as $$
  select * from public.update_investment_plan(plan, visto, null, importe, 1, 'month', '2026-12-05', null, 5, 1, null, null);
$$;

select lives_ok(
  $$ select pg_temp.activo('34000000-0000-0000-0000-000000000001', 'fund') $$,
  'Ana da de alta un activo con el identificador que elige la app');
select is(
  (select format('%s %s %s %s', h.name, h.kind, h.price, h.currency)
   from pg_temp.activo('34000000-0000-0000-0000-000000000001', 'fund') h),
  'Fondo de prueba fund 10.500000 EUR', 'repetir la petición devuelve el activo guardado, con la moneda por defecto');
select is((select count(*)::int from public.holdings), 1, 'y no crea un segundo');
select throws_ok(
  $$ select pg_temp.activo('34000000-0000-0000-0000-000000000001', 'stock') $$,
  'STM01', null, 'repetirlo con otro tipo falla en vez de darlo por guardado');
select throws_ok(
  $$ select pg_temp.activo(null, 'fund') $$,
  '23514', null, 'hace falta el identificador');

select lives_ok(
  $$ select pg_temp.plan('34000000-0000-0000-0000-0000000000b1', '34000000-0000-0000-0000-000000000001', 10000) $$,
  'Ana crea un plan de aportación para su activo');
select is(
  (select format('%s %s', p.amount_minor, p.starts_on)
   from pg_temp.plan('34000000-0000-0000-0000-0000000000b1', '34000000-0000-0000-0000-000000000001', 10000) p),
  '10000 2026-12-05', 'repetir la petición devuelve el plan guardado');
select is((select count(*)::int from public.investment_plans), 1, 'y no crea un segundo');
select throws_ok(
  $$ select pg_temp.plan('34000000-0000-0000-0000-0000000000b1', '34000000-0000-0000-0000-000000000001', 20000) $$,
  'STM01', null, 'repetirlo con otro importe falla');
select throws_ok(
  $$ select pg_temp.plan(null, '34000000-0000-0000-0000-000000000001', 10000) $$,
  '23514', null, 'el plan también necesita identificador');

reset role;
insert into public.holdings (id, household_id, name, created_by, updated_at)
  select '34000000-0000-0000-0000-000000000002', id, 'Acciones de prueba',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;
insert into public.investment_plans (id, household_id, holding_id, amount_minor, starts_on, created_by, updated_at)
  select '34000000-0000-0000-0000-0000000000b2', id, '34000000-0000-0000-0000-000000000002', 5000, '2026-12-05',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select pg_temp.activo('34000000-0000-0000-0000-000000000001', 'fund') $$,
  '23505', null, 'Bruno no reutiliza el identificador de un activo de Ana');
select throws_ok(
  $$ select pg_temp.plan('34000000-0000-0000-0000-0000000000b3', '34000000-0000-0000-0000-000000000001', 10000) $$,
  null::char(5), null, 'ni crea un plan para un activo de Ana');
select throws_ok(
  $$ select pg_temp.cambiar_activo('34000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 'De Bruno') $$,
  'STM05', null, 'ni cambia un activo de Ana aunque sepa su versión');
select throws_ok(
  $$ select pg_temp.cambiar_plan('34000000-0000-0000-0000-0000000000b2', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'ni un plan de Ana');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s %s', h.name, h.symbol, h.price, h.updated_at > '2026-11-01 10:00:00.123456+00')
   from pg_temp.cambiar_activo('34000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00', 'Acciones') h),
  'Acciones FDP 12.250000 t', 'con la versión leída el activo se cambia, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select pg_temp.cambiar_activo('34000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 'Pisado') $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select format('%s %s', p.amount_minor, p.updated_at > '2026-11-01 10:00:00.123456+00')
   from pg_temp.cambiar_plan('34000000-0000-0000-0000-0000000000b2', '2026-11-01T11:00:00.123456+01:00', 7500) p),
  '7500 t', 'con la versión leída el plan se cambia');
select throws_ok(
  $$ select pg_temp.cambiar_plan('34000000-0000-0000-0000-0000000000b2', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'y la versión antigua ya no vale');
select is(
  (select format('%s %s', (select name from public.holdings where id = '34000000-0000-0000-0000-000000000002'),
                 (select amount_minor from public.investment_plans where id = '34000000-0000-0000-0000-0000000000b2'))),
  'Acciones 7500', 'quedan los primeros cambios');

-- Categorías ------------------------------------------------------------------------------
-- Ana ya tiene sus categorías de partida: se cuentan solo las de esta prueba.
select lives_ok(
  $$ select public.create_category('35000000-0000-0000-0000-000000000001', (select id from hogar),
       'Mascotas de prueba', 'expense', 'wants', 'pawprint') $$,
  'Ana da de alta una categoría con el identificador que elige la app');
select is(
  (select format('%s %s %s %s', c.name, c.kind, c.budget_group, c.icon)
   from public.create_category('35000000-0000-0000-0000-000000000001', (select id from hogar),
     'Mascotas de prueba', 'expense', 'needs', 'star') c),
  'Mascotas de prueba expense wants pawprint', 'repetir la petición devuelve la categoría guardada, sin cambiarla');
select is(
  (select count(*)::int from public.categories where name = 'Mascotas de prueba'), 1, 'y no crea una segunda');
select throws_ok(
  $$ select public.create_category('35000000-0000-0000-0000-000000000001', (select id from hogar),
       'Otro nombre de prueba', 'expense', 'wants', 'pawprint') $$,
  'STM01', null, 'repetirla con otro nombre falla en vez de darla por guardada');
select throws_ok(
  $$ select public.create_category('35000000-0000-0000-0000-000000000009', (select id from hogar),
       'MASCOTAS DE PRUEBA', 'expense', 'wants', null) $$,
  '23505', null, 'otra categoría propia con el mismo nombre sigue sin poder crearse');
select throws_ok(
  $$ select public.create_category(null, (select id from hogar), 'Sin identificador', 'expense', null, null) $$,
  '23514', null, 'hace falta el identificador');

reset role;
insert into public.categories (id, household_id, name, kind, budget_group, created_by, updated_at)
  select '35000000-0000-0000-0000-000000000002', id, 'Regalos de prueba', 'expense', 'wants',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select public.create_category('35000000-0000-0000-0000-000000000001', (select id from hogar),
       'Mascotas de prueba', 'expense', 'wants', 'pawprint') $$,
  '23505', null, 'Bruno no reutiliza el identificador de una categoría de Ana');
select throws_ok(
  $$ select public.update_category('35000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'De Bruno', 'wants', null) $$,
  'STM05', null, 'ni la cambia aunque sepa su identificador y su versión');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s %s', c.name, c.kind, c.budget_group, c.updated_at > '2026-11-01 10:00:00.123456+00')
   from public.update_category('35000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00',
     'Regalos', 'needs', 'gift') c),
  'Regalos expense needs t', 'con la versión leída la categoría se cambia, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select public.update_category('35000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00',
       'Pisada', 'wants', null) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select format('%s %s', name, icon) from public.categories where id = '35000000-0000-0000-0000-000000000002'),
  'Regalos gift', 'queda lo del primer cambio');

-- Presupuestos extra ------------------------------------------------------------------------
create function pg_temp.extra(budget uuid, limite bigint, favorito boolean default false, nombre text default 'Vacaciones de prueba')
returns setof public.extra_budgets language sql as $$
  select * from public.create_extra_budget(budget, (select id from hogar), nombre, limite, '2026-12-01', null, '{}', '{}', favorito);
$$;
create function pg_temp.cambiar_extra(budget uuid, visto timestamptz, limite bigint)
returns setof public.extra_budgets language sql as $$
  select * from public.update_extra_budget(budget, visto, 'Reforma', limite, '2026-12-01', '2026-12-31', '{}', '{}', false);
$$;

select lives_ok(
  $$ select pg_temp.extra('36000000-0000-0000-0000-000000000001', 80000, true) $$,
  'Ana da de alta un presupuesto extra favorito con el identificador que elige la app');
select lives_ok(
  $$ select pg_temp.extra('36000000-0000-0000-0000-000000000003', 20000, true, 'Navidad de prueba') $$,
  'y después otro, que pasa a ser el favorito');
select is(
  (select format('%s %s %s', e.name, e.limit_minor, e.is_favorite)
   from pg_temp.extra('36000000-0000-0000-0000-000000000001', 80000, true) e),
  'Vacaciones de prueba 80000 f', 'repetir la primera petición devuelve el guardado, tal como está ahora');
select is(
  (select string_agg(name, ', ' order by name) from public.extra_budgets where is_favorite),
  'Navidad de prueba', 'sin quitarle la marca al favorito de ahora');
select is((select count(*)::int from public.extra_budgets), 2, 'y sin crear otro');
select throws_ok(
  $$ select pg_temp.extra('36000000-0000-0000-0000-000000000001', 5) $$,
  'STM01', null, 'repetirlo con otro límite falla en vez de darlo por guardado');
select throws_ok(
  $$ select pg_temp.extra(null, 80000) $$,
  '23514', null, 'hace falta el identificador');

reset role;
insert into public.extra_budgets (id, household_id, name, limit_minor, starts_on, created_by, updated_at)
  select '36000000-0000-0000-0000-000000000002', id, 'Reforma de prueba', 500000, '2026-12-01',
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select pg_temp.extra('36000000-0000-0000-0000-000000000001', 80000) $$,
  '23505', null, 'Bruno no reutiliza el identificador de un presupuesto extra de Ana');
select throws_ok(
  $$ select pg_temp.cambiar_extra('36000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'ni lo cambia aunque sepa su identificador y su versión');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  (select format('%s %s %s %s', e.name, e.limit_minor, e.ends_on, e.updated_at > '2026-11-01 10:00:00.123456+00')
   from pg_temp.cambiar_extra('36000000-0000-0000-0000-000000000002', '2026-11-01T11:00:00.123456+01:00', 600000) e),
  'Reforma 600000 2026-12-31 t', 'con la versión leída se cambia, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select pg_temp.cambiar_extra('36000000-0000-0000-0000-000000000002', '2026-11-01 10:00:00.123456+00', 1) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select is(
  (select limit_minor::int from public.extra_budgets where id = '36000000-0000-0000-0000-000000000002'),
  600000, 'queda el límite del primer cambio');

-- Cargos de los pagos fijos ---------------------------------------------------------------------
-- Un cargo pendiente del alquiler de Ana, en una versión antigua.
reset role;
insert into public.recurring_charges (id, household_id, series_id, due_on, amount_minor, created_by, updated_at)
  select '37000000-0000-0000-0000-000000000001', id, '32000000-0000-0000-0000-000000000001', '2026-11-05', -80000,
         '00000000-0000-0000-0000-00000000000a', '2026-11-01 10:00:00.123456+00'
  from hogar;

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$ select public.update_recurring_charge('37000000-0000-0000-0000-000000000001', '2026-11-01 10:00:00.123456+00', 'skipped', null) $$,
  'STM05', null, 'Bruno no cambia un cargo de Ana aunque sepa su identificador y su versión');

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$ select public.update_recurring_charge('37000000-0000-0000-0000-000000000001', '2026-11-01 10:00:00.123+00', 'skipped', null) $$,
  'STM05', null, 'una versión recortada a milisegundos no es la misma');
select is(
  (select format('%s %s', c.status, c.updated_at > '2026-11-01 10:00:00.123456+00')
   from public.update_recurring_charge('37000000-0000-0000-0000-000000000001', '2026-11-01T11:00:00.123456+01:00', 'skipped', null) c),
  'skipped t', 'con la versión leída Ana salta el cargo, y devuelve la fila con su versión nueva');
select throws_ok(
  $$ select public.update_recurring_charge('37000000-0000-0000-0000-000000000001', '2026-11-01 10:00:00.123456+00', 'pending', null) $$,
  'STM05', null, 'otro dispositivo que aún tiene la versión antigua no pisa el cambio');
select throws_ok(
  $$ select public.update_recurring_charge('37000000-0000-0000-0000-000000000001', null, 'pending', null) $$,
  'STM05', null, 'ni quien no dice qué versión leyó');
select is(
  (select status from public.recurring_charges where id = '37000000-0000-0000-0000-000000000001'),
  'skipped', 'el cargo sigue saltado');

select * from finish();
rollback;
