# Diagnósticos de la base de datos

Consultas de solo lectura para mirar el estado del proyecto real. No cambian nada y no
devuelven nombres, conceptos ni correos. Se ejecutan a mano; no son migraciones.

Viven dentro de `supabase/tests` para que la prueba pgTAP pueda leerlas: así lo que se prueba
en CI es exactamente lo que se pega en el editor SQL. Llevan la extensión `.pgsql` para que
`supabase test db` no las tome por pruebas (solo ejecuta `.sql` y `.pg`).

## ORC-63: filas que apuntan a algo de otro miembro

Antes de la migración `20261115000000_privacidad_por_usuario.sql` todo el hogar compartía
cuentas, categorías y movimientos. Ahora cada fila es de quien la creó (`created_by`) y cada
miembro solo ve lo suyo. Una fila anterior que apunta a algo de otro miembro queda a medias:
por ejemplo, un movimiento de Bruno en una cuenta de Ana no entra en el saldo que ve Ana, y
Bruno no puede editarlo porque no ve la cuenta.

Prueba: `supabase/tests/database/16_orc63_diagnostico.test.sql`.

### Cómo ejecutarlo

En el panel de Supabase del proyecto real, SQL Editor, con el rol `postgres` (el de por
defecto, que no pasa por el RLS). El editor solo enseña el resultado de la última sentencia,
así que cada archivo se ejecuta por separado:

1. Pegar el contenido de `orc-63_filas_cruzadas.pgsql`, ejecutar y guardar el resultado (CSV).
2. Pegar el contenido de `orc-63_saldos.pgsql`, ejecutar y guardar el resultado (CSV).
3. Anotar los dos resultados en ORC-63. «Sin filas» también es un resultado: anotarlo.

### Consulta 1: `orc-63_filas_cruzadas.pgsql`

Una fila por hogar, tabla y tipo de problema, con cuántas filas hay (`filas`). Los casos que
no aparecen valen cero. Sin filas en el resultado = no hay nada que corregir.

| `tipo` | Qué significa |
| --- | --- |
| `cuenta_de_otro`, `categoria_de_otro`, `meta_de_otro`, `activo_de_otro`, `tarjeta_de_otro`, `movimiento_de_otro`, `pago_fijo_de_otro`, `cuenta_de_pago_de_otro` | La fila de `tabla` es de un miembro y lo que enlaza es de otro (o no tiene creador). |
| `sin_creador` | `created_by` es nulo (su usuario se borró). Nadie ve la fila. |
| `creador_no_miembro` | Quien la creó ya no es miembro de ese hogar. Nadie ve la fila. |
| `titular_de_otro` | Cuenta o activo marcado como de un miembro (`owner_id`) pero creado por otro: su titular no lo ve. |

Notas:

- `budget_lines` no tiene `created_by`: cada línea cuenta como de quien creó su presupuesto.
- En `extra_budgets` se cuenta cada categoría o cuenta de sus listas, no cada presupuesto.
- Una fila sin creador solo sale en `sin_creador`, no en los tipos `_de_otro`.
- Lo más probable en un hogar con datos anteriores: `transactions` / `categoria_de_otro`,
  porque la migración dio todas las categorías que había a quien creó el hogar.

### Consulta 2: `orc-63_saldos.pgsql`

Una fila por cuenta que tiene movimientos que su saldo no cuenta. El saldo de una cuenta
(vista `account_balances`) solo lo ve quien la creó, y solo suma los movimientos de esa
persona. Los demás miembros no ven la cuenta ni su saldo.

| Columna | Qué significa |
| --- | --- |
| `movimientos_total` | Todos los movimientos de la cuenta. |
| `movimientos_visibles` | Los que cuenta hoy el saldo que ve quien creó la cuenta. |
| `movimientos_ocultos` | Los que no cuenta: de otro miembro, sin creador, o todos si quien creó la cuenta ya no es miembro. |
| `otros_creadores` | Cuántas personas distintas apuntaron los ocultos (los sin creador no cuentan aquí). |
| `diferencia_minor` | Saldo con todos los movimientos menos saldo que se ve hoy, en céntimos. Negativo: el saldo que se ve es más alto que el real. |

`diferencia_minor` es la única cifra de dinero que sale, y es una diferencia, no un saldo.
Si es cero con `movimientos_ocultos` mayor que cero, los ocultos se compensan entre sí.

### Después

Qué hacer con las filas afectadas (reasignarlas, y con qué regla) lo decide Jean a la vista
del resultado. La corrección va en una migración nueva con su prueba, y se vuelven a ejecutar
las dos consultas para comparar: después tienen que salir sin filas.
