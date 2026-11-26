-- Diagnóstico ORC-63: las consultas de supabase/tests/diagnostics cuentan bien las filas que
-- apuntan a algo de otro miembro, y no dan nada en un hogar limpio. Datos inventados.
--
-- La prueba no copia las consultas: psql lee los dos archivos y crea una vista temporal con
-- cada uno, así que lo que se prueba es lo mismo que se pega en el editor SQL. Que se pueda
-- crear la vista demuestra además que cada archivo es una sola sentencia select.
-- pg_prove se ejecuta desde supabase/tests (la segunda ruta es por si se lanza desde database/).
\set cruzadas `cat diagnostics/orc-63_filas_cruzadas.pgsql 2>/dev/null || cat ../diagnostics/orc-63_filas_cruzadas.pgsql`
\set saldos `cat diagnostics/orc-63_saldos.pgsql 2>/dev/null || cat ../diagnostics/orc-63_saldos.pgsql`

begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

create temp view cruzadas as
:cruzadas

create temp view saldos as
:saldos

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}'),
  ('00000000-0000-0000-0000-00000000000d', 'dani@savethemoney.invalid', '{"username":"dani"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

-- Ana y Bruno comparten hogar; Carla tiene el suyo. Dani tiene filas en el de Ana pero ya no es miembro.
-- Todo se siembra como superusuario, con created_by a mano: así eran los datos anteriores a la privacidad.
insert into public.households (id, name, created_by) values
  ('10000000-0000-0000-0000-000000000001', 'Casa cruzada', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000002', 'Casa limpia', '00000000-0000-0000-0000-00000000000c');
insert into public.household_members (household_id, user_id, role) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'owner'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'member'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c', 'owner');

create temp table ids (name text primary key, id uuid) on commit drop;
create temp table vistos (quien text, account_id uuid, saldo bigint) on commit drop;
grant select on ids to authenticated;
grant select, insert on vistos to authenticated;

-- Siembra un hogar con una fila de cada tipo: lo enlazado es de `dueno` y lo que enlaza, de `otro`.
-- Con dueno = otro sale un hogar limpio con la misma forma.
create function pg_temp.sembrar(prefijo text, hogar uuid, dueno uuid, otro uuid) returns void
language plpgsql as $$
declare
  cat_dueno uuid;
  cat_otro uuid;
  cuenta uuid;
  tarjeta uuid;
  cuenta_otro uuid;
  compra uuid;
  compra_tarjeta uuid;
  serie uuid;
  meta uuid;
  activo uuid;
  presupuesto uuid;
begin
  select c.id into strict cat_dueno from public.categories c
    where c.household_id = hogar and c.created_by = dueno and c.name = 'Supermercado';
  select c.id into strict cat_otro from public.categories c
    where c.household_id = hogar and c.created_by = otro and c.name = 'Supermercado';

  insert into public.accounts (household_id, name, opening_balance_minor, owner_id, created_by)
    values (hogar, 'Cuenta de prueba', 100000, otro, dueno) returning id into cuenta;
  insert into public.accounts (household_id, name, kind, created_by)
    values (hogar, 'Tarjeta de prueba', 'credit_card', dueno) returning id into tarjeta;
  insert into public.accounts (household_id, name, created_by)
    values (hogar, 'Otra cuenta de prueba', otro) returning id into cuenta_otro;

  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description, created_by)
    values (hogar, cuenta, cat_dueno, '2026-11-02', -1000, 'Compra propia', dueno);
  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description, created_by)
    values (hogar, cuenta, cat_dueno, '2026-11-03', -4500, 'Cuenta y categoría ajenas', otro) returning id into compra;
  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description, created_by)
    values (hogar, cuenta, cat_otro, '2026-11-03', -500, 'Cuenta ajena', otro);
  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description, created_by)
    values (hogar, cuenta_otro, cat_dueno, '2026-11-04', -700, 'Categoría ajena', otro);
  insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, created_by)
    values (hogar, tarjeta, '2026-11-05', -30000, 'Compra con la tarjeta', otro) returning id into compra_tarjeta;

  insert into public.credit_cards (account_id, household_id, credit_limit_minor, pay_from_account_id, created_by)
    values (tarjeta, hogar, 200000, cuenta, otro);
  insert into public.card_installments (household_id, account_id, transaction_id, months, created_by)
    values (hogar, tarjeta, compra_tarjeta, 3, dueno);

  insert into public.recurring_series (household_id, name, amount_minor, account_id, category_id, starts_on, created_by)
    values (hogar, 'Pago fijo de prueba', 4500, cuenta, cat_dueno, '2026-11-03', otro) returning id into serie;
  insert into public.recurring_charges (household_id, series_id, due_on, amount_minor, status, transaction_id, created_by)
    values (hogar, serie, '2026-11-03', -4500, 'confirmed', compra, dueno);

  insert into public.goals (household_id, name, target_minor, account_id, created_by)
    values (hogar, 'Meta de prueba', 500000, cuenta, otro) returning id into meta;
  insert into public.goal_contributions (household_id, goal_id, amount_minor, made_on, created_by)
    values (hogar, meta, 10000, '2026-11-03', dueno);

  insert into public.holdings (household_id, name, account_id, owner_id, created_by)
    values (hogar, 'Fondo de prueba', cuenta, dueno, otro) returning id into activo;
  insert into public.holding_prices (household_id, holding_id, priced_on, price, created_by)
    values (hogar, activo, '2026-11-03', 10, dueno);
  insert into public.investment_trades (household_id, holding_id, traded_on, quantity, price, created_by)
    values (hogar, activo, '2026-11-03', 2, 10, dueno);
  insert into public.investment_plans (household_id, holding_id, account_id, amount_minor, starts_on, created_by)
    values (hogar, activo, cuenta_otro, 5000, '2026-12-01', dueno);

  insert into public.budgets (household_id, month, created_by)
    values (hogar, '2026-11-01', otro) returning id into presupuesto;
  insert into public.budget_lines (household_id, budget_id, category_id, limit_minor)
    values (hogar, presupuesto, cat_dueno, 30000);
  insert into public.extra_budgets (household_id, name, limit_minor, starts_on, category_ids, account_ids, created_by)
    values (hogar, 'Extra de prueba', 80000, '2026-11-01', array[cat_dueno], array[cuenta], otro);

  insert into ids values
    (prefijo || 'cuenta', cuenta), (prefijo || 'tarjeta', tarjeta), (prefijo || 'cuenta_otro', cuenta_otro);
end;
$$;

select pg_temp.sembrar('cruzada_', '10000000-0000-0000-0000-000000000001',
                       '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');
select pg_temp.sembrar('limpia_', '10000000-0000-0000-0000-000000000002',
                       '00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000c');

-- Además, en el hogar cruzado: una cuenta y un movimiento sin creador, y una cuenta con un
-- movimiento de alguien que ya no es miembro.
insert into public.accounts (household_id, name, created_by)
  values ('10000000-0000-0000-0000-000000000001', 'Cuenta sin creador', null);
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, created_by)
  select '10000000-0000-0000-0000-000000000001', id, '2026-11-06', 200, 'Movimiento sin creador', null::uuid
  from ids where name = 'cruzada_cuenta';
with x as (insert into public.accounts (household_id, name, created_by)
           values ('10000000-0000-0000-0000-000000000001', 'Cuenta de quien se fue', '00000000-0000-0000-0000-00000000000d')
           returning id)
insert into ids select 'cruzada_cuenta_de_dani', id from x;
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description, created_by)
  select '10000000-0000-0000-0000-000000000001', id, '2026-11-06', -900, 'Compra de quien se fue',
         '00000000-0000-0000-0000-00000000000d'::uuid
  from ids where name = 'cruzada_cuenta_de_dani';

-- Lo que ve hoy cada uno en la vista de saldos, con su RLS.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
insert into vistos select 'ana', account_id, balance_minor from public.account_balances;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
insert into vistos select 'bruno', account_id, balance_minor from public.account_balances;
reset role;

-- Consulta 1: filas cruzadas -------------------------------------------------------------
select set_eq(
  $$ select tabla, tipo, filas from cruzadas where household_id = '10000000-0000-0000-0000-000000000001' $$,
  $$ values
    ('accounts'::text, 'creador_no_miembro'::text, 1::bigint),
    ('accounts', 'sin_creador', 1),
    ('accounts', 'titular_de_otro', 1),
    ('budget_lines', 'categoria_de_otro', 1),
    ('card_installments', 'movimiento_de_otro', 1),
    ('card_installments', 'tarjeta_de_otro', 1),
    ('credit_cards', 'cuenta_de_otro', 1),
    ('credit_cards', 'cuenta_de_pago_de_otro', 1),
    ('extra_budgets', 'categoria_de_otro', 1),
    ('extra_budgets', 'cuenta_de_otro', 1),
    ('goal_contributions', 'meta_de_otro', 1),
    ('goals', 'cuenta_de_otro', 1),
    ('holding_prices', 'activo_de_otro', 1),
    ('holdings', 'cuenta_de_otro', 1),
    ('holdings', 'titular_de_otro', 1),
    ('investment_plans', 'activo_de_otro', 1),
    ('investment_plans', 'cuenta_de_otro', 1),
    ('investment_trades', 'activo_de_otro', 1),
    ('recurring_charges', 'movimiento_de_otro', 1),
    ('recurring_charges', 'pago_fijo_de_otro', 1),
    ('recurring_series', 'categoria_de_otro', 1),
    ('recurring_series', 'cuenta_de_otro', 1),
    ('transactions', 'categoria_de_otro', 2),
    ('transactions', 'creador_no_miembro', 1),
    ('transactions', 'cuenta_de_otro', 3),
    ('transactions', 'sin_creador', 1) $$,
  'el hogar cruzado da cada tipo de fila cruzada con su cuenta exacta'
);
select is_empty(
  $$ select * from cruzadas where household_id = '10000000-0000-0000-0000-000000000002' $$,
  'el hogar limpio, con las mismas filas pero de una sola persona, no da nada'
);

-- Consulta 2: saldos ---------------------------------------------------------------------
select set_eq(
  $$ select i.name, s.movimientos_total, s.movimientos_visibles, s.movimientos_ocultos, s.otros_creadores, s.diferencia_minor
     from saldos s join ids i on i.id = s.account_id
     where s.household_id = '10000000-0000-0000-0000-000000000001' $$,
  $$ values
    ('cruzada_cuenta'::text, 4::bigint, 1::bigint, 3::bigint, 1::bigint, -4800::bigint),
    ('cruzada_tarjeta', 1, 0, 1, 1, -30000),
    ('cruzada_cuenta_de_dani', 1, 0, 1, 1, -900) $$,
  'salen solo las cuentas con movimientos que su saldo no cuenta, con la diferencia exacta'
);
select is_empty(
  $$ select * from saldos where household_id = '10000000-0000-0000-0000-000000000002' $$,
  'en el hogar limpio todos los saldos cuentan todos sus movimientos'
);

-- La diferencia de la consulta es la que hay de verdad entre la vista con RLS y todas las filas.
select is(
  (select saldo from vistos where quien = 'ana' and account_id = (select id from ids where name = 'cruzada_cuenta')),
  99000::bigint, 'Ana ve hoy el saldo de su cuenta sin los movimientos que apuntó Bruno'
);
select is(
  (select count(*)::int from vistos
   where quien = 'bruno' and account_id = (select id from ids where name = 'cruzada_cuenta')),
  0, 'y Bruno no ve esa cuenta ni su saldo'
);
select is(
  (select (a.opening_balance_minor + sum(t.amount_minor))::bigint
   from public.accounts a join public.transactions t on t.account_id = a.id
   where a.id = (select id from ids where name = 'cruzada_cuenta')
   group by a.id)
  - (select saldo from vistos where quien = 'ana' and account_id = (select id from ids where name = 'cruzada_cuenta')),
  (select diferencia_minor from saldos where account_id = (select id from ids where name = 'cruzada_cuenta')),
  'diferencia_minor es el saldo con todas las filas menos el que ve Ana'
);

select * from finish();
rollback;
