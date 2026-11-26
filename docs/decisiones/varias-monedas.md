# Varias monedas: cimientos (ORC-71)

Estado: decidido lo de este documento hasta «Lo que se hace ahora». Lo de «Siguientes pasos» está descrito pero no hecho, y «Necesita al dueño» son decisiones de producto pendientes.

## El problema

La base guarda una moneda en el hogar (`households.base_currency`), en cada cuenta (`accounts.currency`) y en cada activo (`holdings.currency`), pero las apps tratan todos los importes como si fueran euros:

- Las apps no envían la moneda al crear una cuenta ni dejan elegirla. Hoy todas las cuentas creadas desde las apps son `EUR`, que es el valor por defecto de la columna.
- iOS lee la moneda de la cuenta y del activo. Android la lee, pero la ignora al dar formato: `Money.format` siempre escribe «€».
- Los movimientos, presupuestos, pagos fijos y metas no tienen columna de moneda: son unidades menores de «la moneda que toque».
- En iOS, `Money.+` y `Money.-` cerraban la app con un `precondition` al mezclar monedas. Como `Portfolio.value` empieza a sumar desde `0 €`, un hogar con un solo activo en dólares cerraba la app al abrir Inversiones.
- El dueño podía cambiar `base_currency` con datos apuntados, y ningún importe se convertía.

## Modelo elegido

**Cada importe pertenece a una moneda, y la moneda la pone la cuenta (o el activo).**

1. `Money` (iOS) sigue llevando `minor` y `currency`. Android sigue guardando `Long` en céntimos y usa `Money.Amount(minor, currency)` cuando hay que sumar importes que pueden ser de monedas distintas.
2. La moneda de un movimiento es la de su cuenta. No se añade columna de moneda a `transactions`: sería un dato duplicado que puede contradecir a la cuenta. Lo mismo para las cuotas y las condiciones de una tarjeta (la cuenta de la tarjeta) y para las operaciones, precios y planes de un activo (el activo).
3. Lo que no cuelga de una cuenta (presupuestos, presupuestos extra, pagos fijos sin cuenta, metas sin cuenta) está en la moneda del hogar, `base_currency`.
4. `base_currency` es además la moneda en la que se enseñan los totales del hogar (patrimonio, presupuesto, informes).
5. Sumar importes de monedas distintas exige una **conversión explícita**. Sin ella no hay total.

Se descarta «un `Money` sin moneda y la moneda solo en la cuenta» porque el importe viaja por la app separado de su cuenta (totales, informes, exportaciones) y la moneda se perdería justo donde hace falta comprobarla.

## Lo que se hace ahora

### 1. El dominio no suma monedas distintas

iOS, `Packages/STMCore/Sources/STMCore/Money.swift`:

- `a + b` y `a - b` con la misma moneda funcionan como siempre.
- Con monedas distintas devuelven `Money.mixed`: un valor que **no es un importe**. Su `minor` es 0, su moneda es `"*"` (no es un código que la base admita, así que ninguna cuenta puede tenerlo), `isMixed` es verdadero y `formatted()` devuelve «Varias monedas». La mezcla se contagia: `mixed + lo que sea` sigue siendo `mixed`.
- Un importe de cero no tiene moneda que mezclar: `0 € + 5 $` son `5 $`. Por eso todos los `reduce(Money.zero) { $0 + $1 }` que ya había dan el total correcto en un hogar con una sola moneda que no sea el euro, sin tocar esos archivos.
- `a < b` con monedas distintas ya no cierra la app: ordena por código de moneda. No dice cuál vale más; solo da un orden estable.
- `converted(to:rate:)` es la única forma de pasar de una moneda a otra.

Android, `android/app/src/main/java/com/savethemoney/android/data/Money.kt`:

- `Money.total(importes)` aplica la misma regla y devuelve `null` cuando hay mezcla. `Money.MIXED` es el texto «Varias monedas». `Money.convert(minor, rate)` es la conversión explícita.
- `Portfolio.value` y `Portfolio.cost` usan `Money.total`; con mezcla valen 0, `Portfolio.mixedCurrencies` es verdadero y la pantalla de Inversiones enseña «Varias monedas».

Los casos están en `testdata/vectors/money_currencies.json` y los leen las dos plataformas.

Por qué un valor «no es un importe» y no un error que se lanza: `+` se usa en decenas de sitios y en archivos que otras tareas están cambiando; un `+` que lanza obligaría a reescribirlos todos ahora. Con este diseño ninguna pantalla puede enseñar una cifra que mezcle monedas a través de `Money.+`, y ninguna se cierra.

Límite conocido: la regla va de izquierda a derecha. `5 $ − 5 $ + 3 €` da `3 €` (los dólares ya sumaban cero) y `5 $ + 3 € − 5 $` da «Varias monedas». Nunca sale una cifra falsa; como mucho se niega un total que se podría haber dado.

### 2. Qué enseña cada total cuando hay mezcla

Hoy la mezcla solo puede aparecer si alguien crea una cuenta o un activo con otra moneda fuera de las apps (la API lo permite). Con eso:

| Total | iOS | Android |
| --- | --- | --- |
| Valor, coste y ganancia de la cartera | «Varias monedas»; sin ganancia ni reparto por clase | «Varias monedas»; sin ganancia ni reparto |
| Cartera con una sola moneda que no es el euro | Total correcto en esa moneda | Cifra correcta, pero con «€» (Android no da formato por moneda) |
| Saldo total de las cuentas (`FinanceModel.totalBalance`) | «Varias monedas» | Suma los céntimos como si fueran euros |
| Totales del calendario de pagos, de una exportación, de los pagos fijos del mes, de las tarjetas | «Varias monedas» (usan `Money.+`) | Suman céntimos como euros |
| Patrimonio neto, presupuesto, informes, evolución de la cartera, reparto por clase | Suman `minor` directamente: céntimos como euros | Igual |

Las dos últimas filas son el trabajo pendiente del paso 3 de abajo: son sumas que se saltan `Money` (iOS) o que nunca lo han usado (Android).

### 3. `base_currency` no se cambia con importes guardados

Migración `supabase/migrations/20261126110000_moneda_base_bloqueada.sql`: un trigger rechaza el cambio de `base_currency` con el error `STM06` si el hogar tiene alguna cuenta, presupuesto, presupuesto extra, pago fijo, meta o activo (todo lo demás con importe cuelga de uno de ellos). No se convierte ni se reescribe ningún importe. Un hogar vacío, o reiniciado con `reset_household`, sí puede cambiarla. Guardar la misma moneda o cambiar solo el nombre no falla.

Las dos apps convierten `STM06` en: «No se puede cambiar la moneda del hogar mientras tenga cuentas, presupuestos u otros importes guardados.» Ninguna de las dos tiene todavía una pantalla para cambiar la moneda; la regla protege la API.

## Tipos de cambio

No se guardan todavía. Lo decidido para cuando se guarden:

- Una tabla por hogar: moneda de origen, moneda de destino, fecha y tipo como `numeric` (nunca coma flotante). El tipo se lee «unidades de destino por cada unidad de origen».
- Los tipos se apuntan a mano, como los precios de los activos (`holding_prices`). Descargarlos de un servicio externo es otra decisión (coste, privacidad, dependencia).
- Un total en la moneda del hogar usa, para cada importe, el último tipo conocido con fecha igual o anterior a la del importe. Si no hay ninguno, ese total no se calcula: se enseñan los totales por moneda.
- Una transferencia entre cuentas de monedas distintas guarda los dos importes reales (lo que salió y lo que entró); no se calcula con el tipo.

## Redondeo

- Se convierte importe a importe y después se suma; nunca se suma primero y se convierte después.
- `minor × tipo`, redondeado a la unidad menor más cercana; el medio se aleja del cero (`2,5 → 3`, `−2,5 → −3`). Es el mismo redondeo que ya usan `Money(decimal:)` en iOS y `toMinor()` en Android.
- Por eso el total convertido puede diferir en algún céntimo de convertir el total. Es lo esperado, y es estable: el mismo dato da siempre la misma cifra en las dos plataformas (vectores en `money_currencies.json`).
- Solo monedas con dos decimales. `Money.decimal` divide entre 100 y los formularios admiten dos decimales.

## Siguientes pasos

En este orden; cada uno es una tarea aparte.

1. **Leer y enviar la moneda de la cuenta en las apps.** `NewAccountRow` (iOS) y su equivalente en Android no llevan `currency`; `SupabaseFinance` crea `Money(minor:)` sin la moneda de la cuenta al leer movimientos. Android necesita que `Money.format` reciba la moneda.
2. **Que el servidor ate las monedas.** Hoy `accounts.currency` y `holdings.currency` no tienen relación con `base_currency`, y un activo puede cargar en una cuenta de otra moneda (`create_trade`). Hay que decidir qué combinaciones se admiten y rechazar el resto.
3. **Quitar las sumas que se saltan `Money`.** En iOS, las que suman `.minor` y vuelven a crear `Money(minor:)`: `Tracking.swift` (patrimonio y su historia), `Budget.swift` y `BudgetPeriods.swift`, `MovementFilter.swift`, `CreditCards.swift`, `Goals.swift`, `CashFlow.swift`, `Investments.swift` (reparto por clase y evolución) y `FinanceViews.swift` (gastado e ingresado del mes). En Android, todos los `sumOf` sobre importes de cuentas o activos distintos. Cada una pasa a totales por moneda o a un total convertido.
4. **Totales por moneda en pantalla.** Donde hoy saldría «Varias monedas», enseñar una línea por moneda.
5. **Tabla de tipos de cambio** y totales convertidos a la moneda del hogar, con las reglas de arriba.
6. **Transferencias entre monedas** con los dos importes.
7. **Monedas sin dos decimales** (yen, dinar): el número de decimales pasa a depender de la moneda en `Money.decimal`, en la lectura de importes y en el formato.
8. **Cambiar la moneda de un hogar con datos**, si se quiere permitir: necesita los pasos 1 a 5 y una decisión del dueño (abajo).

## Necesita al dueño

- **¿Se podrá cambiar la moneda de un hogar con datos?** Ahora queda bloqueado. Las opciones son dejarlo así para siempre (lo más simple: quien se equivoque reinicia el hogar), o convertir todos los importes con un tipo que elija el dueño, que reescribe datos guardados y no se puede deshacer. Recomendación: dejarlo bloqueado.
- **Cuentas o activos que ya estén en otra moneda.** Las apps no pueden crearlos, pero la API sí. Antes de aplicar la migración en producción conviene mirar si existe alguno (`select currency, count(*) from public.accounts group by 1` y lo mismo con `holdings`). Si los hay, sus totales pasarán de una cifra mezclada a «Varias monedas» en iOS. No se toca ningún dato.
- **Hogares con `base_currency` distinta de `EUR` y datos apuntados.** Si existe alguno, sus importes se apuntaron como euros en las apps. La migración no lo arregla ni lo empeora, pero ya no podrá cambiar la moneda sin ayuda. Consulta: `select base_currency, count(*) from public.households group by 1`.
- **De dónde salen los tipos de cambio**: a mano (recomendado para empezar) o de un servicio externo.
