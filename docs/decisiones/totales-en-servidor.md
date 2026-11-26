# Totales calculados en el servidor (ORC-70)

Estado: medición preparada, sin resultados. No hay decisión todavía: depende de los números de la tabla de abajo.

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
- Las páginas se piden una detrás de otra, como en las apps. Con `offset`, cada página obliga al servidor a saltarse las anteriores: el coste por página puede crecer con N.

## Resultados

Pendiente: los rellena quien lance el workflow, con la mediana de las tres ejecuciones. El resumen del job trae las tres.

| N | Petición | Filas | Peticiones | Tiempo total (ms) | ms por página | Bytes de respuesta |
|---:|---|---:|---:|---:|---:|---:|
| 10000 | Movimientos (iOS) | | | | | |
| 10000 | Movimientos (Android) | | | | | |
| 10000 | Precios | | | | | |
| 10000 | Operaciones | | | | | |
| 10000 | Saldos | | | | | |
| 50000 | Movimientos (iOS) | | | | | |
| 50000 | Movimientos (Android) | | | | | |
| 50000 | Precios | | | | | |
| 50000 | Operaciones | | | | | |
| 50000 | Saldos | | | | | |

Ejecución del workflow (enlace y fecha):

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
