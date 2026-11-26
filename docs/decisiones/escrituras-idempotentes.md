# Escrituras idempotentes y control de concurrencia

Estado: aceptada (ORC-69 para los movimientos, `public.transactions`; ORC-142 la extiende al resto de
tablas que se escriben desde un formulario, ver «El resto de tablas» más abajo).

## Problema

- Un reintento tras un corte de red apuntaba el mismo movimiento dos veces: la app no podía
  elegir el identificador de la fila.
- Dos dispositivos que cambiaban el mismo movimiento se pisaban sin aviso: ganaba el último.

## Modelo elegido

### Apuntar: identificador de la app, una vez por formulario

- La app genera un UUID al abrir el formulario y lo manda en cada intento de guardar.
  - iOS/macOS: `MovementFormView.newMovementId` (`App/Sources/FinanceViews.swift`), dentro de `MovementDraft.id`.
  - Android: `idMovimiento` en `Pantalla07` (`ui/screens/Movimientos.kt`), dentro de `MovementDraft.id`.
- El servidor guarda con `public.create_movement(...)`: `insert ... on conflict (id) do nothing`
  y devuelve la fila guardada.
  - Mismo identificador y mismos datos (cuenta, importe y día): devuelve lo guardado, no apunta nada.
  - Mismo identificador y otros datos: falla con `STM01`, igual que `create_transfer` y `create_trade`.
  - Identificador de un movimiento de otra persona: falla con `23505`. No se lee ni se cambia esa fila.

### Cambiar: la versión leída es `updated_at`

- Cada movimiento que llega del servidor trae `updated_at`. La app lo guarda **como texto, tal
  cual llegó** (`Movement.updatedAt`), y lo devuelve al cambiar el movimiento.
- El servidor cambia con `public.update_movement(movement, seen, ...)`: un solo
  `update ... where id = movement and updated_at = seen`. La comprobación y el cambio son la
  misma sentencia, así que entre dos cambios a la vez solo entra el primero.
- Si no cambia ninguna fila (otra versión, movimiento borrado o de otra persona) falla con
  `STM05`. Las apps lo convierten en `AppError.movementChanged` / `AppError.MovementChanged`,
  recargan los movimientos y avisan: «Este movimiento ha cambiado en otro dispositivo y se ha
  vuelto a cargar…». No se guarda nada del cambio rechazado.

### Por qué funciones y no un upsert directo

Un `upsert` con `ignoreDuplicates` desde la app no devuelve la fila cuando ya existía, no
distingue «ya estaba guardado» de «ese identificador es de otra persona» y no puede avisar de
que se repite con otros datos. Un `update` con filtro por `updated_at` devuelve cero filas sin
decir por qué. Las funciones dan una respuesta clara en una sola petición y una sola
transacción, y siguen el patrón de `create_transfer` y `create_trade`.

Las dos funciones son `security invoker`: corren con los permisos de quien llama y el RLS
sigue decidiendo quién apunta y quién cambia cada fila.

### Precisión y zonas horarias de `updated_at`

- Postgres guarda `timestamptz` con microsegundos. PostgREST lo devuelve como texto ISO 8601
  con los seis decimales y el desplazamiento horario (`2026-11-26T10:00:00.123456+00:00`).
- `Date` en Swift (un `Double`) y los formateadores ISO de milisegundos pierden microsegundos.
  Por eso ninguna de las dos apps convierte ese valor a fecha: se guarda y se manda el mismo texto.
- El texto lleva su desplazamiento, así que el servidor lo interpreta igual sea cual sea la zona
  de la sesión o del dispositivo. La comparación la hace Postgres entre dos `timestamptz`.
- `updated_at` lo pone el trigger `touch_updated_at` con `now()` (la hora de inicio de la
  transacción). Dos cambios distintos del mismo movimiento con el mismo microsegundo de inicio
  no se distinguirían; se acepta ese riesgo. Si hiciera falta más, el siguiente paso es una
  columna `version` entera.
- Cualquier cambio de la fila en el servidor cambia la versión, también los indirectos (por
  ejemplo borrar su categoría la deja sin categoría). La app recibe `STM05`, recarga y se repite.
  Tras borrar una cuenta o una categoría desde la app, esta recarga ya lo que la usaba (movimientos,
  pagos fijos, metas, inversiones, tarjetas y presupuesto), así que la siguiente edición no avisa (ORC-147).

## Qué cubre y qué no

Cubre:

- Apuntar un movimiento desde el formulario (también el gasto con tarjeta a plazos o recurrente).
- Cambiar un movimiento: formulario, marcar revisado, excluir, edición masiva, «cambiar similares».

No cubre (se queda como estaba):

- Borrar un movimiento: es idempotente por naturaleza, pero no deja rastro para otro dispositivo.
- Importar un CSV: ya no duplica gracias a la huella (`account_id, import_hash`). Los pagos fijos que
  crea llevan un id fijado al primer intento, por su nombre, y repetir la importación lo reutiliza (ORC-147).
- Confirmar un pago fijo, duplicar un movimiento y «Deshacer» un borrado: cada pulsación es un
  movimiento nuevo con identificador nuevo.
- El presupuesto del periodo (`budgets`, `budget_lines`) y el calendario de cobro (`pay_schedules`):
  se guardan enteros con `save_period_budget` y un upsert por persona; no tienen alta que se pueda
  duplicar, pero tampoco comprobación de versión.
- Las versiones anteriores de las apps: siguen usando `insert` y `update` directos, que
  conservan sus permisos. Funcionan, pero sin estas dos protecciones.

## El resto de tablas (ORC-142)

Mismo modelo, misma respuesta y mismos códigos (`STM01`, `STM05`, `23505`), en
`20261126140000_orc142_escrituras_idempotentes.sql`:

| Tabla | Alta | Cambio | Un alta repetida vale si coinciden |
| -- | -- | -- | -- |
| `accounts` | `create_account` | `update_account` | hogar, nombre, tipo, saldo inicial |
| `goals` | `create_goal` | `update_goal` | hogar, nombre, tipo, objetivo |
| `goal_contributions` | `create_goal_contribution` | — (no se cambian) | meta, importe, día |
| `recurring_series` | `create_recurring_series` | `update_recurring_series` | hogar, nombre, tipo, importe, primer día |
| `credit_cards` | `create_credit_card` | `update_credit_card` | hogar, límite, día de extracto, día de cargo, forma de pago |
| `card_installments` | `create_card_installment` | `update_card_installment` | compra, plazo, interés |
| `holdings` | `create_holding` | `update_holding` | hogar, nombre, tipo |
| `investment_plans` | `create_investment_plan` | `update_investment_plan` | activo, importe, primer día |
| `categories` | `create_category` | `update_category` | hogar, nombre, tipo |
| `extra_budgets` | `create_extra_budget` | `update_extra_budget` | hogar, nombre, límite, primer día |
| `recurring_charges` | — (en lote, `unique (series_id, due_on)`) | `update_recurring_charge` | — |

En las apps:

- Cada modelo trae `updatedAt` (el texto del servidor, sin convertir). **Sin versión es un alta, con
  versión es un cambio**: así, guardar otra vez un formulario cuyo alta sí llegó al servidor repite el
  alta (y recibe lo guardado) en vez de intentar un cambio sin versión.
- El identificador se crea al abrir el formulario y se reutiliza en cada «Guardar». Lo que nace de
  otro formulario hereda su identificador: el pago fijo y el aplazado de un gasto con tarjeta llevan
  el del movimiento; la aportación mensual que se crea al comprar, el de la compra.
- Las condiciones de una tarjeta no tienen identificador propio (su clave es la cuenta): el
  formulario guarda la versión que cargó al abrirse.
- Si un alta o un cambio falla, el modelo recarga esa lista: detrás del aviso se ve lo que hay en el
  servidor. El aviso de `STM05` y el de `STM01` son los mismos que en los movimientos, con un texto
  que ya no habla de «movimiento» ni de «pago».
- Cambios indirectos que también cambian la versión: elegir otra cuenta predeterminada u otro
  presupuesto extra favorito (el anterior pierde la marca), apuntar un precio (cambia el activo),
  confirmar un cargo, y borrar una cuenta o una categoría (lo que la enlazaba se queda sin ella).

## Siguientes pasos hacia el modo sin conexión

Ninguno está hecho. En este orden:

1. ~~Extender el mismo modelo (identificador de la app + versión) a las demás tablas que se
   escriben desde el formulario.~~ Hecho en ORC-142.
2. Borrado lógico (`deleted_at`) para que un borrado se pueda sincronizar, y lectura de cambios
   desde una versión (`updated_at > último visto`).
3. Cola local de escrituras pendientes en cada app, que reintenta con el mismo identificador.
4. Regla de conflictos visible para la persona cuando un cambio hecho sin conexión llega tarde
   (hoy: se rechaza y se recarga).
5. Cuando ninguna versión antigua esté en uso, quitar el permiso de `insert`/`update` directo
   sobre `transactions` y sobre las tablas de ORC-142, para que toda escritura pase por las funciones.
