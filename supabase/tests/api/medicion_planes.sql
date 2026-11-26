-- ORC-70: planes de ejecución de las peticiones que mide medicion_movimientos.py, que es quien lanza este archivo
-- con psql contra el Supabase local, después de cargar los datos de cada tamaño. No es una prueba: sólo imprime.
--
-- Variables de psql (las pasa el script con -v):
--   hogar      id del hogar de medición
--   claims     JSON de `request.jwt.claims` del usuario de medición ({"sub": …, "role": "authenticated"})
--   mitad      offset de una página del medio de los movimientos
--   mitad_inv  offset de una página del medio de los precios y de las operaciones
--
-- Las consultas llevan la forma que genera PostgREST (un CTE `pgrst_source` con el select, el filtro, el orden y
-- el limit/offset, y fuera el json_agg). El último bloque saca de pg_stat_statements el SQL que PostgREST mandó de
-- verdad, para comprobar que la forma es la misma, con sus tiempos medios dentro de Postgres.
--
-- Bloques 1 y 2: con el rol y las claims del usuario, como hace PostgREST y como hacen las pruebas pgTAP: se aplica
-- el RLS. Bloques 3 y 4: como postgres, dueño de las tablas, que se salta el RLS: la diferencia es lo que cuesta el RLS.

\set ON_ERROR_STOP on
\pset pager off
\set cola 'select null::bigint as total_result_set, pg_catalog.count(_postgrest_t) as page_total, coalesce(json_agg(_postgrest_t), ''[]'') as body, nullif(current_setting(''response.headers'', true), '''') as response_headers, nullif(current_setting(''response.status'', true), '''') as response_status from (select * from pgrst_source) _postgrest_t'
\set movimiento '"public"."transactions"."id", "public"."transactions"."household_id", "public"."transactions"."account_id", "public"."transactions"."category_id", "public"."transactions"."booked_on", "public"."transactions"."amount_minor", "public"."transactions"."description", "public"."transactions"."notes", "public"."transactions"."import_hash", "public"."transactions"."excluded", "public"."transactions"."reviewed_at", "public"."transactions"."payee", "public"."transactions"."tags", "public"."transactions"."updated_at", "public"."transactions"."transfer_id"'

select version();
select 'transactions' as tabla, count(*) as filas from public.transactions where household_id = :'hogar'
union all select 'holding_prices', count(*) from public.holding_prices where household_id = :'hogar'
union all select 'investment_trades', count(*) from public.investment_trades where household_id = :'hogar';

\echo
\echo '=== 1. Con RLS (rol authenticated y las claims del usuario) ==='
begin;
set local request.jwt.claims to :'claims';
set local role authenticated;

\echo '--- 1.1 Movimientos, iOS (allMovements): página del medio, offset' :mitad
explain (analyze, buffers)
with pgrst_source as (
  select :movimiento from "public"."transactions"
  where "public"."transactions"."household_id" = :'hogar'
  order by "public"."transactions"."booked_on" asc, "public"."transactions"."id" asc
  limit 1000 offset :mitad
) :cola;

\echo '--- 1.2 Movimientos, Android (TrackingModel): página del medio, offset' :mitad
explain (analyze, buffers)
with pgrst_source as (
  select :movimiento from "public"."transactions"
  where "public"."transactions"."household_id" = :'hogar'
    and "public"."transactions"."booked_on" >= '1900-01-01' and "public"."transactions"."booked_on" <= '2999-12-31'
  order by "public"."transactions"."booked_on" desc, "public"."transactions"."id" asc
  limit 1000 offset :mitad
) :cola;

\echo '--- 1.3 Movimientos, iOS: la primera página (offset 0), para comparar con la del medio'
explain (analyze, buffers)
with pgrst_source as (
  select :movimiento from "public"."transactions"
  where "public"."transactions"."household_id" = :'hogar'
  order by "public"."transactions"."booked_on" asc, "public"."transactions"."id" asc
  limit 1000 offset 0
) :cola;

\echo '--- 1.4 Saldos (account_balances)'
explain (analyze, buffers)
with pgrst_source as (
  select "public"."account_balances"."account_id", "public"."account_balances"."balance_minor"
  from "public"."account_balances"
  where "public"."account_balances"."household_id" = :'hogar'
  order by "public"."account_balances"."account_id" asc
  limit 1000 offset 0
) :cola;

\echo '--- 1.5 Precios (holdingPrices): página del medio, offset' :mitad_inv
explain (analyze, buffers)
with pgrst_source as (
  select "public"."holding_prices"."id", "public"."holding_prices"."household_id", "public"."holding_prices"."holding_id",
         "public"."holding_prices"."priced_on", "public"."holding_prices"."price"
  from "public"."holding_prices"
  where "public"."holding_prices"."household_id" = :'hogar'
  order by "public"."holding_prices"."priced_on" asc, "public"."holding_prices"."id" asc
  limit 1000 offset :mitad_inv
) :cola;

\echo '--- 1.6 Operaciones (trades): página del medio, offset' :mitad_inv
explain (analyze, buffers)
with pgrst_source as (
  select "public"."investment_trades"."id", "public"."investment_trades"."household_id",
         "public"."investment_trades"."holding_id", "public"."investment_trades"."traded_on",
         "public"."investment_trades"."side", "public"."investment_trades"."quantity",
         "public"."investment_trades"."price", "public"."investment_trades"."fee_minor",
         "public"."investment_trades"."note"
  from "public"."investment_trades"
  where "public"."investment_trades"."household_id" = :'hogar'
  order by "public"."investment_trades"."traded_on" asc, "public"."investment_trades"."id" asc
  limit 1000 offset :mitad_inv
) :cola;
rollback;

\echo
\echo '=== 2. Con RLS y plan genérico: PostgREST prepara la consulta con parámetros y Postgres puede no saber el limit ==='
begin;
set local request.jwt.claims to :'claims';
set local role authenticated;
set local plan_cache_mode to force_generic_plan;
prepare pagina (uuid, bigint, bigint) as
with pgrst_source as (
  select :movimiento from "public"."transactions"
  where "public"."transactions"."household_id" = $1
  order by "public"."transactions"."booked_on" asc, "public"."transactions"."id" asc
  limit $2 offset $3
) :cola;
\echo '--- 2.1 Movimientos, iOS: página del medio, offset' :mitad
explain (analyze, buffers) execute pagina (:'hogar', 1000, :mitad);
deallocate pagina;
rollback;

\echo
\echo '=== 3. Las mismas consultas sin RLS (rol postgres) ==='
begin;
\echo '--- 3.1 Movimientos, iOS: página del medio, offset' :mitad
explain (analyze, buffers)
with pgrst_source as (
  select :movimiento from "public"."transactions"
  where "public"."transactions"."household_id" = :'hogar'
  order by "public"."transactions"."booked_on" asc, "public"."transactions"."id" asc
  limit 1000 offset :mitad
) :cola;

\echo '--- 3.2 Saldos (account_balances)'
explain (analyze, buffers)
with pgrst_source as (
  select "public"."account_balances"."account_id", "public"."account_balances"."balance_minor"
  from "public"."account_balances"
  where "public"."account_balances"."household_id" = :'hogar'
  order by "public"."account_balances"."account_id" asc
  limit 1000 offset 0
) :cola;

\echo '--- 3.3 Precios: página del medio, offset' :mitad_inv
explain (analyze, buffers)
with pgrst_source as (
  select "public"."holding_prices"."id", "public"."holding_prices"."household_id", "public"."holding_prices"."holding_id",
         "public"."holding_prices"."priced_on", "public"."holding_prices"."price"
  from "public"."holding_prices"
  where "public"."holding_prices"."household_id" = :'hogar'
  order by "public"."holding_prices"."priced_on" asc, "public"."holding_prices"."id" asc
  limit 1000 offset :mitad_inv
) :cola;
rollback;

\echo
\echo '=== 4. Cuánto cuesta por fila cada forma de la condición (rol postgres, con las claims; no son políticas) ==='
begin;
set local request.jwt.claims to :'claims';

\echo '--- 4.1 Sin condición: sólo recorrer los movimientos del hogar'
explain (analyze, buffers)
select count(*) from public.transactions t where t.household_id = :'hogar';

\echo '--- 4.2 La condición de la política de hoy: (select private.is_mine(household_id, created_by))'
explain (analyze, buffers)
select count(*) from public.transactions t
where t.household_id = :'hogar' and (select private.is_mine(t.household_id, t.created_by));

\echo '--- 4.3 Sólo la pertenencia: (select private.is_member(household_id))'
explain (analyze, buffers)
select count(*) from public.transactions t
where t.household_id = :'hogar' and (select private.is_member(t.household_id));

\echo '--- 4.4 Sólo el autor: created_by = (select auth.uid())'
explain (analyze, buffers)
select count(*) from public.transactions t
where t.household_id = :'hogar' and t.created_by = (select auth.uid());

\echo '--- 4.5 Autor y pertenencia buscados una vez (candidata para la parte B, sin decidir)'
explain (analyze, buffers)
select count(*) from public.transactions t
where t.household_id = :'hogar'
  and t.created_by = (select auth.uid())
  and t.household_id in (select m.household_id from public.household_members m where m.user_id = (select auth.uid()));
rollback;

\echo
\echo '=== 5. Lo que PostgREST mandó de verdad (pg_stat_statements): las consultas de lectura más caras ==='
\x on
select calls, rows, round(total_exec_time::numeric, 1) as total_ms, round(mean_exec_time::numeric, 1) as media_ms,
       round(max_exec_time::numeric, 1) as max_ms, shared_blks_hit, shared_blks_read, query
from extensions.pg_stat_statements
where query like '%pgrst_source%'
  and query not ilike '%insert into%'
  and (query like '%"transactions"%' or query like '%"account_balances"%' or query like '%"holding_prices"%'
       or query like '%"investment_trades"%')
order by total_exec_time desc
limit 8;
