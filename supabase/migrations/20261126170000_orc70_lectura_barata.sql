-- ORC-70: leer movimientos, precios y operaciones no cuesta una llamada a función por fila.
--
-- Medido con 50.000 movimientos (docs/decisiones/totales-en-servidor.md): la política de lectura
-- `(select private.is_mine(household_id, created_by))` se ejecutaba una vez por fila recorrida, unos 80 µs cada
-- una, porque la llamada depende de dos columnas de la fila y el `select` que la envuelve no la convierte en un
-- valor calculado una vez. Una página del medio tardaba 2,1 s; la misma consulta sin RLS, 28 ms.
--
-- Aquí la misma condición se escribe de forma que lo que no depende de la fila se calcule una vez por consulta:
--
--   private.is_mine(h, c)  =  c is not null and c = auth.uid() and private.is_member(h)
--   private.is_member(h)   =  existe en household_members una fila (household_id = h, user_id = auth.uid())
--
--   nueva condición        =  created_by = (select auth.uid())
--                             and household_id = any (array(select private.my_household_ids()))
--   my_household_ids()     =  los household_id de household_members con user_id = auth.uid()
--
-- Son la misma condición para cualquier fila y cualquier usuario:
--   * `created_by = auth.uid()` sólo es verdadero si ninguno de los dos es nulo: cubre `c is not null`.
--   * `h = any(los hogares de auth.uid())` es verdadero exactamente cuando existe la fila (h, auth.uid()) en
--     household_members, que es lo que mira is_member. Sin sesión (auth.uid() nulo) la lista sale vacía.
--   * Donde una da falso la otra puede dar nulo: una política trata igual falso y nulo (la fila no pasa).
-- Las pruebas (24_orc70_lectura_barata.test.sql) comparan fila a fila la condición nueva con private.is_mine.
--
-- Sólo cambian las políticas de LECTURA de las tres tablas que crecen con el uso. Las de alta, cambio y borrado,
-- y las del resto de tablas (pocas filas por hogar), siguen con private.is_mine, sin tocar.

-- Los hogares de quien consulta. security definer por el mismo motivo que private.is_member: lee
-- household_members sin pasar por su RLS (que a su vez llama a is_member) y sin depender de sus permisos.
-- No tiene argumentos: sólo devuelve los hogares del propio usuario, que ya puede ver.
create function private.my_household_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.household_id from public.household_members m where m.user_id = (select auth.uid());
$$;

revoke all on function private.my_household_ids() from public, anon, authenticated;
grant execute on function private.my_household_ids() to authenticated;

-- alter policy cambia sólo la expresión: el nombre, la orden (select) y el rol (authenticated) siguen igual,
-- y no hay ningún momento sin política.
alter policy transactions_select on public.transactions
  using (created_by = (select auth.uid())
         and household_id = any (array(select private.my_household_ids())));

alter policy holding_prices_select on public.holding_prices
  using (created_by = (select auth.uid())
         and household_id = any (array(select private.my_household_ids())));

alter policy investment_trades_select on public.investment_trades
  using (created_by = (select auth.uid())
         and household_id = any (array(select private.my_household_ids())));

-- El orden en que las apps piden precios y operaciones (por fecha y por id dentro del hogar) no lo daba
-- ningún índice: cada página leía y ordenaba todas las filas del hogar. Los movimientos ya tienen
-- transactions_household_booked_idx, que da el orden por fecha.
-- `create index` sin `concurrently`: bloquea las escrituras de la tabla mientras se crea, y aquí es aceptable
-- porque las tablas de producción son pequeñas hoy. Con tablas grandes habría que crearlos aparte, con concurrently.
create index holding_prices_household_priced_idx on public.holding_prices (household_id, priced_on, id);
create index investment_trades_household_traded_idx on public.investment_trades (household_id, traded_on, id);
