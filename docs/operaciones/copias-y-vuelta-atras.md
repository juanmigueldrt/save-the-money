# Copias de seguridad y vuelta atrás de migraciones

Estado: procedimiento escrito, **restauración todavía sin probar** (ver «Prueba pendiente»).
Ticket: ORC-73. Documentación de Supabase consultada el 26-11-2026:
[Database Backups](https://supabase.com/docs/guides/platform/backups),
[Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore),
[`supabase db push`](https://supabase.com/docs/reference/cli/supabase-db-push),
[`supabase migration list`](https://supabase.com/docs/reference/cli/supabase-migration-list).

> El repositorio es público y la base guarda datos financieros privados. Un volcado con datos
> (`--data-only`, o un volcado completo) **nunca** se sube al repositorio, a un artefacto o caché
> de GitHub Actions, a un log ni a un issue. Se guarda sólo en un disco cifrado y se borra al
> terminar. Un volcado sólo de esquema no tiene filas y sí se puede compartir.

## Qué copias hay

Según la documentación de Supabase:

| Plan | Copia automática | Cuánto tiempo |
| --- | --- | --- |
| Free | Ninguna. Supabase recomienda hacer volcados propios con `supabase db dump`. | — |
| Pro | Diaria (física) | 7 días |
| Team | Diaria | 14 días |
| Enterprise | Diaria | 30 días |
| PITR (complemento de pago, Pro o superior, necesita cómputo Small o mayor) | Continua; sustituye a la diaria | 7, 14 o 28 días |

- Las copias diarias se ven y se restauran en el panel: **Database > Backups**. Restaurar
  sobrescribe el proyecto entero y lo deja sin servicio mientras dura.
- Las copias no incluyen los ficheros de Storage (esta app no los usa) ni las contraseñas de roles
  propios (esta app no tiene).
- Borrar el proyecto borra también sus copias.

Qué plan tiene el proyecto real no está en el repositorio: lo confirma el dueño (ver «Necesita el
dueño»).

## Qué hace el despliegue (`.github/workflows/deploy-db.yml`)

1. Job `revisar`, **antes** de la aprobación: lista los ficheros de `supabase/migrations` que trae
   el push (nuevos `A`, cambiados `M`, borrados `D`) en el resumen de la ejecución. No usa secretos
   ni se conecta al proyecto. Avisa si se cambia o borra una migración existente: una migración ya
   aplicada no se vuelve a aplicar, así que ese cambio no llega a producción.
2. Aprobación manual del entorno `produccion` (sin cambios).
3. Job `push`, después de aprobar y antes de aplicar nada, dos pasos de sólo lectura:
   - `supabase backups list`: las copias físicas que tiene el proyecto.
   - `supabase migration list --remote`: migraciones locales frente a las aplicadas. Las que sólo
     están en local son las que se aplican a continuación.
   Si la lista de migraciones no se puede leer, el job falla y **no** se aplica nada. Si la que
   no se puede leer es la lista de copias, el job avisa y sigue: en el plan Free no hay copias
   automáticas y un fallo ahí dejaría el proyecto sin poder recibir migraciones. Los dos escriben
   su salida en el resumen de la ejecución: sólo fechas de copias y nombres de migraciones, nunca
   filas.
4. `supabase db push --remote --yes`, el único paso que escribe.

El workflow enseña la lista de copias, pero **no** bloquea si no puede leerla ni comprueba cuándo
se hizo la última. Eso lo mira quien aprueba (paso 3 de la lista siguiente) hasta que el dueño decida
automatizarlo.

## Antes de aprobar un despliegue

1. Abre la ejecución del workflow y lee el resumen del job `revisar`. Si hay ficheros `M` o `D`,
   no apruebes: hay que deshacer ese cambio en `main`.
2. Si alguna migración nueva cambia filas existentes (`update`, `delete`, `insert … select`,
   cambiar un `unique` o un `check`, o un `add column … not null` con un valor calculado), su
   autor tiene que haber añadido su comprobación previa y posterior en la sección
   «Comprobaciones por migración» de este documento. Ejecuta la **previa** ahora en el SQL Editor
   del proyecto real y apunta los números (sólo números, no filas).
3. Comprueba que hay una copia reciente:
   - Pro o superior: **Database > Backups** muestra una copia de las últimas 24 horas (o, con
     PITR, el último punto de recuperación es reciente).
   - Free, o si la última copia tiene más de 24 horas: haz una copia lógica en tu Mac antes de
     aprobar (sección siguiente).
4. Aprueba. Al terminar, lee en el job `push` las listas de copias y de migraciones.
5. Ejecuta la comprobación **posterior** de cada migración que cambie filas y compárala con lo que
   apuntaste. Si no cuadra, sigue «Volver atrás».

## Hacer una copia lógica en local

Necesita Docker en marcha y la contraseña de la base de datos. Guarda los ficheros en una carpeta
dentro de un disco cifrado (FileVault basta), **fuera del repositorio**.

```sh
CARPETA=~/CopiasSTM/$(date +%Y%m%d-%H%M)
mkdir -p "$CARPETA" && cd "$CARPETA"
supabase db dump --remote="$URL_PRODUCCION" -f roles.sql --role-only
supabase db dump --remote="$URL_PRODUCCION" -f schema.sql
supabase db dump --remote="$URL_PRODUCCION" -f data.sql --use-copy --data-only
supabase db dump --remote="$URL_PRODUCCION" -f history_schema.sql --schema supabase_migrations
supabase db dump --remote="$URL_PRODUCCION" -f history_data.sql --use-copy --data-only --schema supabase_migrations
```

`$URL_PRODUCCION` es la cadena de conexión del *Session pooler* (panel: **Connect**). No la
escribas en ningún fichero del repositorio. Borra las copias antiguas cuando ya no hagan falta.

## Restaurar en un proyecto de pruebas, paso a paso

Se restaura siempre primero en un proyecto **nuevo y desechable**, nunca encima del real.

1. Crea un proyecto nuevo en la misma organización (database.new), en la misma región y con la
   misma versión de Postgres (17, como `supabase/config.toml`). Llámalo `stm-restauracion-AAAAMMDD`.
2. Activa en él las extensiones no estándar que tenga el real (consulta en el real:
   `select extname from pg_extension order by 1;`).
3. Elige la copia:
   - **Desde una copia diaria (Pro o superior):** sigue
     [Duplicate Project](https://supabase.com/docs/guides/platform/clone-project) para restaurar la
     copia elegida en el proyecto nuevo. Salta al paso 6.
   - **Desde una copia lógica:** usa los ficheros de la sección anterior.
4. Toma la cadena de conexión del proyecto nuevo (*Session pooler*) en `$URL_PRUEBAS`.
   Comprueba dos veces que **no** es la del proyecto real.
5. Restaura (necesita `psql`, `brew install postgresql@17`):

   ```sh
   psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file roles.sql --file schema.sql \
     --command 'SET session_replication_role = replica' \
     --file data.sql \
     --dbname "$URL_PRUEBAS"
   psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file history_schema.sql --file history_data.sql \
     --dbname "$URL_PRUEBAS"
   ```

   `session_replication_role = replica` desactiva los triggers durante la carga (si no, por
   ejemplo, `households_seed_categories` volvería a crear categorías). Si falla por permisos de
   `supabase_admin` o `cli_login_postgres`, sigue la sección *Troubleshooting* de la guía de
   Supabase enlazada arriba.
6. Comprueba la restauración. En los dos proyectos, en sólo lectura, compara los números:

   ```sql
   begin read only;
   select 'households' as tabla, count(*) from public.households
   union all select 'household_members', count(*) from public.household_members
   union all select 'accounts', count(*) from public.accounts
   union all select 'transactions', count(*) from public.transactions
   union all select 'categories', count(*) from public.categories
   union all select 'budgets', count(*) from public.budgets
   union all select 'recurring_series', count(*) from public.recurring_series
   union all select 'holdings', count(*) from public.holdings
   union all select 'investment_trades', count(*) from public.investment_trades
   union all select 'credit_cards', count(*) from public.credit_cards
   union all select 'auth.users', count(*) from auth.users;
   select sum(amount_minor) as suma_movimientos from public.transactions;
   select max(version) as ultima_migracion from supabase_migrations.schema_migrations;
   rollback;
   ```

   Los recuentos y la suma de importes (en céntimos, entera) tienen que ser iguales a los del
   momento de la copia. La última migración tiene que ser la que esperabas.
7. Apunta en el ticket (privado, nunca en un issue público) la fecha, la copia usada, cuánto
   tardó y si los números del paso 6 cuadraron.
8. Borra el proyecto de pruebas y los ficheros locales de la copia, salvo que los quieras guardar
   en el disco cifrado.

### Prueba pendiente

Este procedimiento **no se ha probado todavía**: al escribirlo no había Docker en marcha ni un
proyecto de pruebas, y no se tocó el proyecto real. Lo prueba el dueño una vez siguiendo los pasos
de arriba, y entonces se quita esta sección y el «sin probar» del principio.

## Volver atrás

Una migración que ya se aplicó **no se edita ni se borra** de `supabase/migrations`: producción no
la vuelve a ejecutar y el repositorio deja de describir la base. Tampoco se usa
`supabase migration repair` para «desmarcarla» sin deshacer antes sus cambios. Por orden de
preferencia:

### 1. Arreglar hacia delante (lo normal)

Si la migración dejó un fallo (una política mal, una función que rechaza algo válido), se escribe
una migración nueva que lo corrige, con sus pruebas pgTAP, y se despliega como cualquier otra.
No hace falta restaurar nada y no se pierde lo que se haya escrito mientras tanto.

### 2. Migración inversa

Si hay que quitar lo que añadió, se escribe una migración nueva que hace lo contrario:

| La migración hizo | La inversa hace |
| --- | --- |
| `create function` / `create trigger` / `create policy` | `drop … if exists`, y vuelve a crear la versión anterior (cópiala de la migración que la creó). |
| `create or replace function` | `create or replace` con el cuerpo anterior. |
| `add column` | `drop column` sólo si nadie la usa y su contenido no hace falta; si no, déjala y deja de usarla. |
| `add constraint` / `create unique index` | `drop constraint` / `drop index`. |
| `drop constraint` | Comprueba antes, en sólo lectura, que ninguna fila la incumple; luego `add constraint`. |
| Cambió filas (`update`, `delete`, `insert`) | Sólo se puede deshacer si se guardó el estado anterior (ver abajo). Si no, la salida es la restauración. |

Para que una migración que **cambia filas** se pueda deshacer, guarda dentro de la misma
migración, antes de cambiarlas, la imagen anterior de lo que toca en una tabla del esquema
`private` (sin permisos para `anon` ni `authenticated`), por ejemplo:

```sql
create table private.antes_20261115_categorias as
  select id, created_by from public.categories;
revoke all on private.antes_20261115_categorias from public, anon, authenticated;
```

La inversa vuelve a poner esos valores con un `update … from` y una migración posterior borra la
tabla cuando ya no haga falta. Esos datos se quedan en la base: nunca se exportan.

### 3. Restaurar una copia (último recurso)

Restaurar el proyecto real a una copia **borra todo lo que se escribió después** de esa copia:
movimientos, presupuestos y altas de todas las personas. Sólo se hace si las opciones 1 y 2 no
sirven, después de probar la misma copia en un proyecto de pruebas (sección anterior), y lo
decide y lo hace el dueño, con la app avisada de la parada.

## Comprobaciones por migración

Para cada migración de `supabase/migrations` que cambia filas existentes. Se ejecutan en el SQL
Editor dentro de `begin read only; … rollback;` y sólo devuelven números. La **previa** se ejecuta
justo antes de aplicar la migración y la **posterior** justo después: más tarde, la propia app
cambia los datos y los números dejan de cuadrar.

Las migraciones que sólo crean tablas, funciones, políticas o índices, o añaden columnas que
admiten `null` o con un valor fijo (`false`, `true`, `80`, `'{}'`), no cambian el significado de
las filas existentes y no llevan comprobación.

Las migraciones de esta lista ya estaban aplicadas cuando se escribió este documento (se puede
confirmar con `supabase migration list --remote`): sus consultas quedan como ejemplo y como
plantilla. Una migración nueva que cambie filas añade aquí las suyas en el mismo PR.

### `20261028000000_cuentas_movimientos.sql`

Da las 17 categorías de partida a los hogares que ya existían.

```sql
-- Previa
select count(*) as hogares from public.households;
-- Posterior: esperado 0.
select count(*) as hogares_sin_sus_17_categorias
from public.households h
where (select count(*) from public.categories c where c.household_id = h.id) < 17;
```

### `20261107000000_categorias_y_ofertas.sql`

Añade «Impuestos», «Multas y sanciones» y «Tasas y trámites» a los hogares que no las tenían.

```sql
-- Previa
select (select count(*) from public.households) as hogares,
       (select count(*) from public.categories) as categorias,
       (select count(*) from public.categories
         where kind = 'expense'
           and lower(name) in ('impuestos', 'multas y sanciones', 'tasas y trámites')) as ya_existentes;
-- Posterior: categorias = categorias previas + 3 × hogares − ya_existentes,
-- y hogares_sin_alguna = 0.
select (select count(*) from public.categories) as categorias,
       (select count(*) from public.households h
         where (select count(*) from public.categories c
                 where c.household_id = h.id and c.kind = 'expense'
                   and lower(c.name) in ('impuestos', 'multas y sanciones', 'tasas y trámites')) < 3
       ) as hogares_sin_alguna;
```

### `20261115000000_privacidad_por_usuario.sql`

Asigna cada categoría existente a quien creó el hogar, da las 20 categorías de partida al resto de
miembros y cambia el presupuesto a «uno por persona y mes».

```sql
-- Previa: categorias_de_hogar_sin_creador tiene que ser 0. Si no, esas categorías quedarían
-- con created_by vacío y nadie las vería: no apliques y decide antes de quién son.
select (select count(*) from public.categories) as categorias,
       (select count(*) from public.categories c
          join public.households h on h.id = c.household_id
         where h.created_by is null) as categorias_de_hogar_sin_creador,
       (select count(*) from public.household_members m
          join public.households h on h.id = m.household_id
         where m.user_id is distinct from h.created_by) as miembros_no_creadores,
       (select count(*) from public.budgets) as presupuestos;
-- Posterior: categorias = categorias previas + 20 × miembros_no_creadores,
-- categorias_sin_dueno = 0 y presupuestos igual que antes.
select (select count(*) from public.categories) as categorias,
       (select count(*) from public.categories where created_by is null) as categorias_sin_dueno,
       (select count(*) from public.budgets) as presupuestos;
```

### `20261117000000_presupuesto_por_periodos.sql`

Crea el día de cobro de cada persona que ya estaba en un hogar y convierte los presupuestos de
«un mes» al periodo real que marcaba `month_start_day` del hogar.

```sql
-- Previa
select (select count(distinct user_id) from public.household_members) as personas_en_hogares,
       (select count(*) from public.budgets) as presupuestos;
select h.month_start_day, count(*) as presupuestos
from public.budgets b join public.households h on h.id = b.household_id
group by h.month_start_day order by 1;
-- Posterior: calendarios_de_cobro = personas_en_hogares, presupuestos igual que antes y por
-- cada month_start_day los mismos números; las tres columnas de error, 0.
select (select count(*) from public.pay_schedules) as calendarios_de_cobro,
       (select count(*) from public.budgets) as presupuestos;
select h.month_start_day,
       count(*) as presupuestos,
       count(*) filter (where b.ends_on is null or b.ends_on < b.month) as sin_fin_o_al_reves,
       count(*) filter (where extract(day from b.month) <> h.month_start_day) as inicio_mal,
       count(*) filter (where b.ends_on <> (b.month + interval '1 month' - interval '1 day')::date) as fin_mal
from public.budgets b join public.households h on h.id = b.household_id
group by h.month_start_day order by 1;
```

### `20261118000000_pagos_fijos_pendientes.sql`

Añade `pending_from` con el día de la migración a los pagos fijos que ya existían, para que no
creen cargos de meses pasados.

```sql
-- Previa
select count(*) as series from public.recurring_series;
-- Posterior, el mismo día (UTC, la fecha del servidor): series igual que antes y con_otra_fecha = 0.
select count(*) as series,
       count(*) filter (where pending_from <> current_date) as con_otra_fecha
from public.recurring_series;
```

## Necesita el dueño

- **Confirmar el plan del proyecto real.** En Free no hay ninguna copia automática: cada despliegue
  necesita antes una copia lógica a mano. En Pro hay una diaria de los últimos 7 días.
- **Probar una vez la restauración** con «Restaurar en un proyecto de pruebas». Crear un proyecto
  de pruebas puede costar dinero según el plan.
- **Revisar el primer despliegue** con estos pasos: si `supabase backups list` falla por permisos
  del token `SUPABASE_ACCESS_TOKEN` (necesita leer copias, `backups_read` en un token con
  permisos acotados), el despliegue avisa y sigue; hay que dar ese permiso al token para que la
  lista salga en el resumen. Con el plan confirmado, ese aviso se puede convertir en un fallo.
- **Decidir si se automatiza la antigüedad de la copia** (fallar si la última tiene más de 24 h).
  Con la salida real de `supabase backups list` a la vista se puede añadir sin secretos nuevos.
  En Free no tiene sentido: no hay copias que comprobar.
- **PITR** es un complemento de pago (unos 100 USD al mes con 7 días, más cómputo Small): sólo si
  se quiere poder volver a cualquier minuto.
