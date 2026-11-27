# Compartir cuentas, metas o presupuestos con otro miembro (ORC-76)

Estado: diseño escrito. Nada implementado. Faltan tres decisiones del dueño (al final).

## El problema

Desde la privacidad por usuario (`20261115000000_privacidad_por_usuario.sql`) cada miembro del hogar ve y toca sólo lo que creó. Dos personas que viven juntas no pueden ver la cuenta común, la meta del viaje ni el presupuesto de las vacaciones del otro. La migración lo dejó pendiente: «Compartir algo concreto con el otro miembro llega en otra migración».

Además, el campo `owner_id` de cuentas y activos («de quién es», nulo = compartida) viene de antes de la privacidad y ya no hace lo que dice: una cuenta «compartida» sólo la ve quien la creó.

## Qué se puede compartir

| Qué | Qué ve la otra persona | En la primera entrega |
|---|---|---|
| Una cuenta | La cuenta, su saldo y sus movimientos | Sí |
| Una meta | La meta, su progreso y sus aportaciones | Sí |
| Un presupuesto extra (vacaciones, obra) | El presupuesto y lo gastado | Sí |
| El presupuesto del mes | — | No: es personal por diseño (cada uno tiene el suyo del mismo mes) |
| Una tarjeta | Va con su cuenta: se comparte la cuenta | Sí, con la cuenta |
| Inversiones, pagos fijos | — | No. Se añaden después con el mismo mecanismo si hacen falta |

Se comparte una cosa concreta con una persona concreta del mismo hogar. No existe «compartir todo».

## Modelo de permisos

Una tabla nueva, `shares`, con una fila por cada cosa compartida con cada persona:

| Columna | Qué es |
|---|---|
| `household_id` | El hogar. Las dos personas tienen que ser miembros |
| `kind` | `account`, `goal` o `extra_budget` |
| `target_id` | La fila compartida |
| `shared_by` | Quien la creó y la comparte. Sólo el creador puede compartir lo suyo |
| `shared_with` | Con quién |
| `can_write` | Si la otra persona puede apuntar en ella |

Reglas:

1. **Sólo comparte el creador**, y sólo con miembros actuales del hogar. Nadie puede compartirse a sí mismo algo de otro.
2. **Sólo lectura por defecto.** La otra persona ve, no cambia.
3. **Con escritura (`can_write`), sólo se puede apuntar**, no cambiar ni borrar lo del otro:
   - en una cuenta compartida, apuntar movimientos propios (que son suyos: los puede editar y borrar ella, y los ve también el dueño de la cuenta);
   - en una meta compartida, hacer aportaciones propias.
   La cuenta, la meta o el presupuesto en sí (nombre, saldo inicial, archivar, borrar) los cambia sólo su creador.
4. **Dejar de compartir** lo hace el creador en cualquier momento, y también la otra persona («dejar de ver»). Los movimientos que la otra persona apuntó en la cuenta se quedan en la cuenta: los sigue viendo su dueño, y quien los apuntó deja de verlos, igual que deja de ver la cuenta.
5. **Al salir del hogar o ser quitado** (ORC-56) se borran las filas de `shares` de esa persona, en los dos sentidos. Lo que apuntó en una cuenta ajena se borra con sus datos.

## Cómo se aplica en el servidor

- Las políticas de **lectura** de `accounts`, `transactions`, `goals`, `goal_contributions`, `extra_budgets`, `credit_cards` y `card_installments` pasan de «es mío» a «es mío o está compartido conmigo».
- Para `transactions`, la tabla grande, se mantiene la forma barata de ORC-70: la lista de cuentas compartidas conmigo se calcula una vez por consulta (`account_id = any(array(select private.shared_account_ids()))`), no por fila.
- Las políticas de **alta** de `transactions` y `goal_contributions` admiten además una cuenta o meta compartida conmigo con `can_write`.
- Las políticas de **cambio y borrado** no se tocan: sólo el creador de cada fila.
- La vista de saldos (`account_balances`) ya es `security_invoker`: el saldo de una cuenta compartida incluirá todos los movimientos que quien consulta puede ver, que son todos los de la cuenta.
- Pruebas pgTAP: lo compartido se ve y lo no compartido no; sólo lectura no deja apuntar; con escritura se apunta pero no se edita lo ajeno; dejar de compartir corta el acceso en el momento; un tercer miembro no ve nada; otro hogar no ve nada. Y una comparación fila a fila con las políticas actuales cuando `shares` está vacía, como en ORC-70: sin nada compartido, nadie ve nada distinto de hoy.

## Cómo se ve en las apps

- En la ficha de una cuenta, meta o presupuesto extra propio: «Compartir con…», la lista de miembros, y el interruptor «Puede apuntar».
- Lo compartido conmigo aparece en mis listas con la etiqueta «De Ana».
- **Totales.** Una cuenta compartida conmigo no entra en mi patrimonio ni en mis informes: es de otra persona. Los movimientos que yo apunto en ella sí cuentan como gasto mío en mi presupuesto e informes.

## `owner_id`

Se elimina. Hoy sólo se elige al crear una cuenta o un activo y no cambia quién lo ve. Con `shares` deja de tener sentido: «de quién es» es quien lo creó, y «compartida» es que tiene filas en `shares`.

- Entrega 1: las apps dejan de enseñarlo y de enviarlo.
- Entrega posterior: una migración borra la columna, cuando ya no quede ninguna versión instalada que la envíe.

## Riesgos

- Es otra vez un cambio en la frontera de privacidad, y más grande que ORC-70: siete tablas. La defensa es la misma: pruebas que comparan fila a fila con las políticas actuales cuando no hay nada compartido.
- Los totales (patrimonio, presupuesto, informes) se calculan en el dispositivo con lo que la app descarga. Si lo compartido se descarga mezclado con lo propio, un total puede contar dinero de otra persona. Cada lectura tiene que decir si incluye lo compartido o no, y las pruebas con vectores compartidos tienen que cubrirlo en iOS y en Android.
- El borrado en cascada: borrar una cuenta borra todos sus movimientos, también los que apuntó la otra persona. Hoy eso no puede pasar (ORC-63 dio 0 filas cruzadas); con escritura compartida, sí. La app tiene que avisarlo antes de borrar una cuenta compartida.

## Entregas

1. Servidor: tabla, políticas y pruebas. Sin apps: nadie comparte nada todavía y nada cambia.
2. Apps: compartir y ver cuentas, sólo lectura.
3. Apps: metas y presupuestos extra.
4. Apps: «Puede apuntar».
5. Quitar `owner_id`.

## Decisiones que necesito del dueño

| Decisión | Recomendación |
|---|---|
| ¿Compartir es sólo ver, o también apuntar? | Empezar sólo con ver (entregas 1 a 3) y añadir «Puede apuntar» después. Es lo que menos puede salir mal |
| ¿Una cuenta compartida conmigo cuenta en mi patrimonio? | No. Se ve aparte, como «De Ana» |
| ¿Se quita «De quién es» (`owner_id`) de cuentas y activos? | Sí |
