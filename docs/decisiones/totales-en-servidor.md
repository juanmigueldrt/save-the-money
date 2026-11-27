# Totales calculados en el servidor (ORC-70)

Estado: medido, diagnosticado y arreglado en el servidor y en las descargas (ORC-70, paso 2), y vuelto a medir. Patrimonio e Informes piden menos desde ORC-149. Los totales no se han llevado al servidor: con lo encontrado, lo más probable es que no haga falta (ver «¿Sigue compensando…?»).

## El problema

Varias pantallas descargan todos los movimientos del hogar y suman en el dispositivo. Cada carga crece con cada año de uso, y algunas se repiten cada vez que cambia un movimiento.

## Qué se descarga entero hoy

Todas estas cargas piden la tabla por páginas de 1000 filas (`allRows` / `allPages` en `Packages/STMData/Sources/STMData/SupabaseBackend.swift`, `allPages` en `android/app/src/main/java/com/savethemoney/android/data/SupabaseBackend.kt`) hasta que llega una página incompleta.

| Pantalla | iOS / macOS | Android | Qué pide |
|---|---|---|---|
| Patrimonio (evolución por mes) | `TrackingModel.loadHistory` (`App/Sources/TrackingModel.swift`), desde `TrackingViews.swift` y `RootView.swift` | `TrackingModel.loadMovements` (`ui/TrackingModel.kt`), desde `Pantalla17.kt` | Todos los movimientos. Se calcula con `NetWorth.history` (`STMCore/Tracking.swift`). |
| Informes (ingresos y gastos de seis meses, mayor subida) | `ReportsView.incomeAndExpenses` lee `tracking.allMovements`, cargado con `loadHistory` | `Pantalla18.kt` lee `tracking.allMovements`, cargado con `loadMovements` | Todos los movimientos, aunque sólo usa los últimos meses. |
| Inversiones | `InvestmentModel.load` (`App/Sources/InvestmentModel.swift`) | `InvestmentModel` (`ui/InvestmentModel.kt`) | Todos los precios (`holdingPrices`) y todas las operaciones (`trades`). |
| Exportar CSV | `FinanceModel.exportCSV` (`App/Sources/FinanceModel.swift`) | `FinanceModel` (`ui/FinanceModel.kt`, `MovementsCsv.bytes`) | Todos los movimientos. Aquí hacen falta de verdad: es la exportación. |

Las dos apps vuelven a pedir la lista entera de movimientos de Patrimonio e Informes cada vez que cambia la lista de movimientos recientes (`finance.recent`), por ejemplo al apuntar uno.

Las peticiones de movimientos son distintas en cada app:

- iOS, `SupabaseBackend.allMovements` (`STMData/SupabaseFinance.swift`): `household_id=eq.…`, `order=booked_on.asc,id.asc`.
- Android, `SupabaseFinance.movements(householdId, from, through)` (`data/SupabaseFinance.kt`) con 1900-01-01 y 2999-12-31: además `booked_on=gte.…&booked_on=lte.…`, y `order=booked_on.desc,id.asc`.

Lo que ya se pide acotado y no entra aquí: el presupuesto (`BudgetModel`, movimientos del periodo y de los periodos anteriores que compara), los presupuestos extra (sus fechas), el informe de iOS por periodo (`TrackingModel.loadReport`) y los movimientos recientes y la lista paginada (`FinanceModel`). Los saldos de las cuentas ya se suman en el servidor, con la vista `account_balances` (`supabase/migrations/20261028000000_cuentas_movimientos.sql`).

## Cómo se mide

Script: `supabase/tests/api/medicion_movimientos.py`. Workflow: `.github/workflows/medicion.yml`, sólo a mano (Actions › Medición de carga › Run workflow), con los tamaños como entrada (por defecto `10000,50000`). No corre en los PR.

1. El workflow arranca el Supabase local igual que el job de Supabase de `ci.yml` (base de datos, auth, PostgREST y Kong) en un runner `ubuntu-latest`.
2. El script da de alta un usuario normal y un hogar, con cuatro cuentas y cinco activos. Todas las peticiones van con su sesión: el RLS se aplica como en la app.
3. Para cada tamaño N, de menor a mayor, el hogar llega a N movimientos (repartidos al azar, con semilla fija, en seis años y en las cuatro cuentas, con categoría), N/10 precios y N/10 compras. Datos inventados.
4. Los datos se cargan por la API en lotes de 1000 filas por petición. `transactions` no tiene triggers de alta, así que no hace falta generarlos dentro de Postgres. La carga no se cronometra. Lo que se mide es la lectura, y las filas se leen igual que las de un hogar real: mismas tablas, índices, RLS y columnas.
5. Se cronometran, tres veces cada una, las peticiones que hacen hoy las apps, con el mismo `select`, filtros y orden, y páginas `offset`/`limit` de 1000:
   - movimientos tal como los pide iOS;
   - movimientos tal como los pide Android;
   - precios (`holding_prices`, `order=priced_on.asc,id.asc`, igual en las dos apps);
   - operaciones (`investment_trades`, `order=traded_on.asc,id.asc`, igual en las dos apps);
   - saldos (`account_balances`, `order=account_id.asc`).
6. Para cada ejecución se apuntan las filas, las peticiones, el tiempo total, el tiempo por página y los bytes de respuesta. El tiempo es el de las peticiones: enviar, esperar al servidor y leer el cuerpo entero. No cuenta decodificar el JSON.
7. El script comprueba que llegan todas las filas, sin repetir, y que la suma de los movimientos y los saldos coinciden con lo cargado. Si algo no cuadra, el job falla.

### Límites de la medición

- **Son tiempos del Supabase local en un runner de CI, no de un móvil con red móvil.** El cliente y el servidor están en la misma máquina: no hay latencia de red ni límite de ancho de banda, y el runner no es el servidor de producción. Sirven para ver cómo crece el coste con N y cuánto pesa cada parte, no para prometer tiempos al usuario.
- Por eso se apuntan también los bytes: el coste de transferencia se calcula aparte, con el ancho de banda que se quiera suponer. Son bytes del cuerpo **sin comprimir** (el script no pide gzip). iOS (URLSession) lo pide siempre y el JSON se comprime mucho, así que lo que viaja por la red será menos. En Android no se ha comprobado.
- No mide lo que pasa en el dispositivo después: decodificar el JSON, guardar la lista en memoria y recalcular `NetWorth.history` o `SpendingReport`.
- Las páginas se piden una detrás de otra, como en las apps. En la primera medición todas iban con `offset`, que obliga al servidor a saltarse las páginas anteriores. Desde el paso 2 de ORC-70 los movimientos se piden por cursor, en las apps y en el script.

## Resultados

Supabase local en un runner de GitHub, mediana de las tres ejecuciones. Son las cifras resumidas que dio quien lanzó el workflow: el desglose por petición (iOS y Android por separado, precios y operaciones por separado, y sus bytes) está en el resumen del job y no se ha copiado aquí.

| Movimientos | Descargarlos todos (páginas de 1000) | Por página | Bytes | Saldos (`account_balances`) |
|---:|---:|---:|---:|---:|
| 10.000 | 5,8 s (11 peticiones) | 0,53 s | 4,4 MB | 0,87 s |
| 50.000 | 116 s (51 peticiones) | 2,3 s | 21,8 MB | 4,25 s |

Precios y operaciones (una décima parte de las filas): 0,18 s con 1.000 y 2,6 s con 5.000.

Ejecución del workflow: [45817403865](https://github.com/juanmigueldrt/save-the-money/actions/runs/45817403865), 26-11-2026. Los planes de ejecución: [45820500401](https://github.com/juanmigueldrt/save-the-money/actions/runs/45820500401), mismo día.

### Lectura

- Con 5 veces más filas, descargarlo todo cuesta 20 veces más: cada página es más lenta cuanto más grande es la tabla.
- Los saldos, que es lo único que ya suma el servidor, cuestan unos 85 microsegundos por movimiento (0,87 s / 10.000 y 4,25 s / 50.000). Sumar 50.000 enteros debería costar milisegundos.
- 50.000 movimientos no se cargan en un tiempo aceptable: la opción A queda descartada tal cual.

## Diagnóstico

Estado: confirmado con los planes de ejecución (más abajo). Lo que sigue se escribió antes de verlos y se deja como estaba.

### Qué hay en el servidor

- Las políticas de lectura de `transactions`, `accounts`, `holding_prices` e `investment_trades` son `using ((select private.is_mine(household_id, created_by)))` (`20261115000000_privacidad_por_usuario.sql`).
- `private.is_mine` es una función SQL con `set search_path`: Postgres no la puede incrustar en la consulta. Dentro llama a `auth.uid()`, que lee el JSON de las claims, y a `private.is_member`, que es `security definer` y busca en `household_members`.
- El `(select …)` que envuelve la llamada no la convierte en un valor que se calcula una vez: la llamada depende de dos columnas de la fila (`household_id` y `created_by`), así que es una subconsulta correlacionada y se ejecuta para cada fila que recorre la consulta. El consejo de Supabase de envolver en `select` sólo ahorra trabajo cuando lo envuelto no depende de la fila, como `(select auth.uid())`.
- `transactions` tiene el índice `(household_id, booked_on desc)`, que ya sirve para el orden por fecha de las dos apps. `holding_prices` e `investment_trades` sólo tienen índice por `household_id`: su orden (`priced_on, id` y `traded_on, id`) no lo da ningún índice.

### Lo que se esperaba ver en los planes

Si cada fila recorrida cuesta unos 85 µs de política, las cifras medidas salen solas:

| Petición | Filas que pasan por la política | Estimación | Medido |
|---|---:|---:|---:|
| Saldos, 10.000 | 10.000 | 0,87 s | 0,87 s |
| Saldos, 50.000 | 50.000 | 4,25 s | 4,25 s |
| Movimientos, 10.000: cada página recorre `offset` + 1000 filas | 65.000 en 11 páginas | 5,7 s | 5,8 s |
| Movimientos, 50.000: lo mismo | 1.325.000 en 51 páginas | 113 s | 116 s |
| Precios u operaciones, 1.000: cada página recorre todas las filas | 2.000 en 2 páginas | 0,17 s | 0,18 s |
| Precios u operaciones, 5.000: lo mismo | 30.000 en 6 páginas | 2,6 s | 2,6 s |

Por eso se esperaba:

1. **Página del medio de movimientos** (bloques 1.1 y 1.2): `Limit` sobre `Incremental Sort` (ya ordenado por `booked_on`, falta `id`) sobre un `Index Scan` de `transactions_household_booked_idx`, con `Filter: (SubPlan …)`. El `SubPlan` con tantos `loops` como `offset` + 1000, y casi todo el tiempo dentro de él: unos 2,2 s con `offset` 25.000 y menos de 0,1 s en la primera página (1.3). El `offset` no es caro por saltarse filas, sino porque cada fila saltada pasa antes por la política.
2. **Saldos** (1.4): la suma recorre los movimientos de las cuentas con el mismo `Filter: (SubPlan …)`, con `loops` = todos los movimientos.
3. **Precios y operaciones** (1.5 y 1.6): sin índice que dé el orden, cada página lee todas las filas del hogar, les pasa la política y ordena (`Sort` con `top-N heapsort`). `loops` del `SubPlan` = todas las filas, en cada página.
4. **Sin RLS** (bloque 3): las mismas consultas en milisegundos.
5. **Coste por fila** (bloque 4): 4.2 (`is_mine`) cerca de 85 µs por fila; 4.4 y 4.5 (el autor y la pertenencia calculados una vez) cerca de 4.1 (sin condición).

### Lo que dijeron los planes

Ejecución 45820500401 del workflow (2026-11-26), con 50.000 movimientos. Las cinco previsiones se cumplieron:

| Consulta | Con RLS | Sin RLS | Qué muestra el plan |
|---|---:|---:|---|
| Movimientos, página del medio (`offset` 25.000), iOS y Android | 2.130 ms | 28 ms | `Index Scan` de `transactions_household_booked_idx` con `Filter: (SubPlan 1)`, 26.033 ejecuciones de 0,079 ms |
| Movimientos, primera página | 85 ms | | 1.009 ejecuciones del `SubPlan` |
| Saldos (`account_balances`) | 4.010 ms | 23 ms | 50.000 ejecuciones del `SubPlan` sobre `transactions` |
| Precios y operaciones, cualquier página | 400 ms | 3 ms | `Seq Scan` y `Sort`, 5.000 ejecuciones del `SubPlan` en cada página |

Coste de cada forma de la condición sobre los 50.000 movimientos (bloque 4): sin condición, 5 ms; `(select private.is_mine(…))`, 3.978 ms; sólo `(select private.is_member(…))`, 479 ms; el autor y la pertenencia calculados una vez, 8 a 11 ms. El plan genérico (bloque 2) fue el mismo que el normal. El `Sort` y el `json_agg` no pesaban.

El problema no era descargar y sumar en el dispositivo, ni el `offset` en sí, sino la política: 0,08 ms por cada fila que la consulta recorre, y con `offset` cada página recorre todas las anteriores.

## Qué se ha cambiado (ORC-70, paso 2)

Migración `20261126170000_orc70_lectura_barata.sql`, pruebas `24_orc70_lectura_barata.test.sql`.

1. **Política de lectura de `transactions`, `holding_prices` e `investment_trades`.** Antes: `(select private.is_mine(household_id, created_by))`. Ahora: `created_by = (select auth.uid()) and household_id = any (array(select private.my_household_ids()))`. El usuario y la lista de sus hogares se calculan una vez por consulta, no por fila. Es la misma condición escrita de otra forma (la migración explica por qué, caso a caso) y las pruebas comparan fila a fila lo que ve cada usuario con lo que daba `private.is_mine`: lo propio, lo de otro miembro, filas sin autor, filas de alguien que ya no es miembro, filas con su nombre en un hogar ajeno, y una sesión sin usuario.
2. **Lo que no se ha tocado.** Las políticas de alta, cambio y borrado de esas tres tablas y todas las de las demás (cuentas, activos, presupuestos, metas, tarjetas…) siguen con `private.is_mine`: son tablas de pocas filas por hogar, donde 0,08 ms por fila no se nota, y cada política que no cambia es una menos que demostrar.
3. **Índices** `(household_id, priced_on, id)` en `holding_prices` y `(household_id, traded_on, id)` en `investment_trades`: dan el orden en que las apps piden las páginas. `transactions` no necesita otro: `transactions_household_booked_idx` ya da el orden por fecha y dentro de un día hay pocas filas que ordenar por `id`.
4. **Descarga completa de movimientos por cursor**, en iOS (`allMovements`) y en Android (`movements(householdId, from, through)`): cada página se pide detrás de la última fila de la anterior, con el día de esa fila como límite (`booked_on >= día` en iOS, `<=` en Android) para que el servidor empiece a leer el índice ahí, y un `or` que desempata por `id` dentro del día. Cada app conserva su orden. De paso, un alta o un borrado a mitad de la descarga ya no hace saltar ni repetir filas. Precios y operaciones siguen con `offset`: con el índice y la política nueva, saltarse 5.000 filas cuesta milisegundos.

El script de medición y `medicion_planes.psql` piden ahora los movimientos igual que las apps, por cursor.

## Después del arreglo

Medido con el workflow «Medición de carga» sobre la rama del arreglo, con 10.000 y 50.000 movimientos (mediana de las tres ejecuciones). La columna «Antes» es la de la tabla de Resultados.

| Movimientos | Petición | Antes | Después |
|---:|---|---:|---:|
| 10.000 | Descargarlos todos | 5,8 s | 0,08 s |
| 10.000 | Por página | 0,53 s | 0,007 s |
| 10.000 | Saldos (`account_balances`) | 0,87 s | 0,012 s |
| 10.000 | Precios y operaciones (1.000 filas) | 0,18 s | 0,006 s y 0,009 s |
| 50.000 | Descargarlos todos | 116 s | 0,40 s (iOS) y 0,35 s (Android) |
| 50.000 | Por página | 2,3 s | 0,008 s |
| 50.000 | Saldos (`account_balances`) | 4,25 s | 0,028 s |
| 50.000 | Precios y operaciones (5.000 filas) | 2,6 s | 0,025 s y 0,033 s |

Ejecución del workflow: [45826443661](https://github.com/juanmigueldrt/save-the-money/actions/runs/45826443661), 26-11-2026.

Con 50.000 movimientos la descarga completa pasa de 116 s a 0,4 s (unas 300 veces menos) y los saldos de 4,25 s a 28 ms. El tiempo ya crece en línea con las filas: cada página tarda lo mismo con 10.000 que con 50.000. Los bytes no cambian (21,8 MB con 50.000 movimientos): lo que queda es lo que tarda en viajar y decodificarse el JSON, que esta medición no ve porque el servidor está al lado.

### ¿Sigue compensando llevar los totales al servidor?

Con los números de arriba:

- La razón de tiempo que motivó el ticket desaparece: sumar en el servidor no habría arreglado nada, porque la suma que ya hacía el servidor (`account_balances`) era igual de lenta por la misma política.
- Lo que queda son los bytes: Patrimonio e Informes siguen bajando una fila por movimiento (4,4 MB por cada 10.000, sin comprimir) cada vez que cambia la lista. Para eso la opción B (pedir sólo tres columnas, y en Informes sólo los últimos meses) es más barata que cualquier agregado en el servidor y no obliga a repetir en SQL las reglas de `STMCore`.
- Recomendación: no hacer C, D ni E. La opción B se hizo en ORC-149 (más abajo).

## Opción B hecha (ORC-149)

Sin tocar el servidor:

- **Patrimonio.** Las dos apps piden todos los movimientos con cuatro columnas (`id`, `account_id`, `booked_on`, `amount_minor`) en vez de quince: `movementAmounts` en `STMData/SupabaseFinance.swift` y en `data/SupabaseFinance.kt`, por cursor y en el mismo orden (día e id ascendentes). `id` sólo hace falta para el cursor. `NetWorth.history` da el mismo resultado con estas filas: lo comprueban los vectores de `testdata/vectors/net_worth.json` en las dos plataformas.
- **Informes en iOS.** «Ingresos y gastos» y la categoría que más sube piden sólo los últimos seis meses (`TrackingModel.loadSixMonths`). El informe por periodo ya pedía su tramo. De paso, la petición por fechas de iOS (`periodColumns`) lleva ahora `transfer_id`, como la de Android: sin él, el presupuesto y los informes sólo reconocían una transferencia sin categoría por su pareja del mismo día.
- **Informes en Android.** La pantalla pide los movimientos desde `reportWindowStart`: el primer día del periodo más largo que puede elegir y de su periodo anterior (unos 25 meses), en vez de todos. Una prueba compara todos los informes de la pantalla con la lista entera y con la ventana.

Lo que no cambia: Patrimonio sigue bajando una fila por movimiento, y las dos apps siguen pidiéndolo todo cada vez que cambia la lista de movimientos recientes.

### Medición

Pendiente de la ejecución del workflow «Medición de carga» sobre esta rama (ver la tabla del PR de ORC-149). El script mide ahora también la petición de Patrimonio y las dos de Informes.

### El resto de políticas y los dos índices: no se tocan

- **Políticas con `private.is_mine`** (`accounts_select` y las demás): se evalúan fila a fila, a 0,08 ms por fila. Son tablas de decenas de filas por hogar: unos milisegundos por petición. La vista de saldos, que era la única lectura grande que pasaba por ellas, ya tarda 28 ms con 50.000 movimientos. Reescribirlas obligaría a demostrar otra vez, política a política, que la frontera de privacidad no cambia, para un ahorro que no se puede medir.
- **`holding_prices_household_id_idx` e `investment_trades_household_id_idx`**: son prefijo de los índices de ORC-70 y Postgres ya no los necesita. Sobran, pero sólo cuestan una entrada de índice más por alta en dos tablas pequeñas. Quitarlos es una migración en producción para un ahorro que tampoco se nota. Si algún día otra migración toca esas tablas, se quitan en ella.

## Opciones para llevar los totales al servidor

Ninguna se ha hecho. Todas necesitarían una migración nueva con pruebas pgTAP, cambios en STMData y en Android, y pruebas que comparen sus totales con los de `STMCore` sobre los mismos datos (vectores en `testdata/vectors/`).

### A. No cambiar nada

Si 50.000 movimientos se cargan en un tiempo aceptable, se deja como está.

- Coste: ninguno.
- Riesgo: el coste sigue creciendo con los años, y se repite cada vez que cambia un movimiento.

### B. Pedir menos de lo mismo

Sin tocar el servidor:

- Patrimonio sólo necesita `account_id`, `booked_on` y `amount_minor`, no las 15 columnas de `movementColumns`.
- Informes sólo usa los últimos meses: puede pedir un rango de fechas, como ya hace el presupuesto.
- No volver a pedirlo todo en cada cambio, sino sólo cuando haga falta.

- Coste: bajo, sólo en las apps.
- Límite: Patrimonio sigue bajando una fila por movimiento. Menos bytes, mismo número de filas.

### C. Vista `security_invoker` con totales por mes y cuenta

Una vista como `account_balances`, pero agrupada por cuenta y mes (`date_trunc('month', booked_on)`), con la suma de `amount_minor`. Patrimonio la acumula en el dispositivo con el saldo inicial.

- Coste: una migración pequeña, una petición por pantalla y filas = cuentas × meses, no movimientos.
- Límites: el servidor sigue recorriendo todos los movimientos del hogar en cada petición (con el índice `transactions_household_booked_idx`). El mes de calendario no es el periodo del hogar cuando `month_start_day` no es 1: Informes no la podría usar tal cual.

### D. Funciones `security invoker` con parámetros

Por ejemplo, totales por mes o por categoría entre dos fechas, con el día de inicio de mes del hogar. Devuelven sólo los totales que pinta cada pantalla.

- Coste: medio. Cada regla de `STMCore` que influye en el total (`excluded`, las transferencias entre cuentas propias, incluidas las que se reconocen sin `transfer_id`, los periodos por `month_start_day`, la moneda de cada cuenta) habría que repetirla en SQL y mantenerla igual en tres sitios.
- Riesgo: que el servidor y `STMCore` den totales distintos. Hacen falta vectores compartidos que lo comprueben.

### E. Tabla de totales mantenida con triggers

Una tabla con la suma por cuenta y mes que se actualiza en cada alta, cambio o borrado de movimiento.

- Coste: alto. Lectura casi gratis, pero cada escritura toca otra fila más (con bloqueos si dos miembros apuntan a la vez), y hay que rellenarla en una migración sobre los datos que ya existen.
- Riesgo: si un trigger falla o se salta, los totales dejan de cuadrar sin que nadie lo vea.

### F. Caché local con carga incremental

El dispositivo guarda los movimientos y sólo pide los cambiados desde la última vez (`updated_at`).

- Coste: alto en las dos apps. Los borrados no dejan rastro en `transactions`: haría falta una tabla de borrados o un borrado lógico.
- Límite: la primera carga, la de un móvil nuevo, sigue siendo la de todo.

### Precios y operaciones de inversión

La cartera necesita el último precio de cada activo y las participaciones netas, no todo el historial. Se podrían pedir con una vista del último precio por activo y otra de participaciones por activo. La gráfica de evolución del activo sí necesita la serie: se pediría sólo para el activo abierto. Los N/10 del script son una suposición: un hogar real tendrá muchos menos precios y operaciones que movimientos.
