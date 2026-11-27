# Seguridad y privacidad

El repositorio es público, así que sólo contiene código. Los datos de quien usa
la app viven en su dispositivo y en su proyecto de Supabase, protegidos por RLS.

## Lo que nunca se sube

- La clave `service_role` o `sb_secret_…` de Supabase, la contraseña de la base de
  datos y los tokens `sbp_…`. Van sólo en los secretos de GitHub del repositorio.
- `Config/Secrets.xcconfig` (URL y clave anon del proyecto real).
- CSV de bancos, PDF o CSV exportados, copias de la base de datos o capturas con
  datos reales. Los CSV sólo se permiten dentro de carpetas `Fixtures/` y deben
  ser inventados.
- Certificados y perfiles de firma de Apple.

`.gitignore`, gitleaks (en pre-commit y en CI) y la protección de push de GitHub
lo hacen cumplir. Si un secreto llega a subirse, se **revoca y se cambia** en
Supabase en el momento: borrarlo del historial no basta.

## Base de datos

- Todas las tablas tienen RLS y el rol `anon` no tiene permisos sobre ninguna.
- Cada tabla nueva llega con pruebas en `supabase/tests/database` que comprueban
  que otro hogar no puede leerla ni escribirla.
- Las funciones `security definer` fijan `search_path = ''` y comprueban
  `auth.uid()`.
- Las migraciones se aplican al proyecto real sólo desde GitHub Actions y con
  aprobación manual en el entorno `produccion`. Antes de aplicarlas, el despliegue
  lista las copias de seguridad y las migraciones pendientes, y se para si no puede
  leer las migraciones. Cómo comprobar la copia y cómo volver atrás:
  [docs/operaciones/copias-y-vuelta-atras.md](docs/operaciones/copias-y-vuelta-atras.md).

## Qué pasa con tus datos al dejar un hogar

Regla decidida el 2026-11-27 (ORC-56). La aplica el servidor con un trigger, así que vale también para las
versiones antiguas de las apps. Pruebas: `supabase/tests/database/25_orc56_datos_al_salir.test.sql`.

- **Sales por tu cuenta:** se borra en el momento todo lo que apuntaste en ese hogar (cuentas, movimientos,
  categorías, presupuestos, metas, tarjetas, inversiones y pagos fijos). La app lo avisa antes y no se puede deshacer.
- **Te quita el dueño:** dejas de ser miembro en el momento, pero tus datos se guardan 30 días. En ese plazo sólo tú
  puedes exportar tus movimientos; nadie más los ve, tampoco el dueño. Si vuelves a entrar antes, los recuperas.
  A los 30 días ya no se pueden exportar y una tarea diaria los borra.
- **Se borra tu usuario:** se borran todas tus filas de todos los hogares.

Lo que no cubre todavía: borrar la cuenta desde la app (ORC-74), y que el dueño no pueda dejar el hogar sin dueño (ORC-59).

## En la app

- La sesión (tokens de acceso y de refresco) no se guarda nunca en claro:
  - iOS y macOS: en el Llavero (almacén por defecto de supabase-swift).
  - Android: cifrada con AES-GCM y una clave de Android Keystore que no sale del
    dispositivo, en las preferencias de la app. Una sesión en claro de versiones
    anteriores se cifra y se borra al arrancar; si no se puede descifrar, la app
    arranca sin sesión. Esas preferencias quedan fuera de las copias en la nube
    y de la transferencia entre dispositivos.
- Las apps sólo registran fallos, en el registro local del dispositivo (`Logger` en
  iOS y macOS, categoría `errores`; `android.util.Log` en Android, etiqueta `STM`).
  Cada línea lleva como mucho: el nombre de la operación (un texto fijo del código),
  el tipo del error, su código (de Postgres, de Supabase Auth o de red) y el estado
  HTTP. Nunca el mensaje del error ni el cuerpo de la petición o la respuesta, que
  pueden citar importes, nombres, notas, beneficiarios, etiquetas, usuarios, correos,
  tokens o códigos de invitación; tampoco ids de hogar, usuario o fila. No se envía
  nada fuera del dispositivo:
  [docs/decisiones/informes-de-fallos.md](docs/decisiones/informes-de-fallos.md).
- «Borrar datos» borra en el servidor sólo lo que creó quien lo pide. Lo de otros miembros se borra sólo si cuelga de algo suyo (p. ej. los movimientos de una cuenta).

## Avisar de un problema

Abre un aviso privado en la pestaña *Security* del repositorio
(«Report a vulnerability»), no un issue público.
