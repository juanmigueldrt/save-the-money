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

## En la app

- La sesión (tokens de acceso y de refresco) no se guarda nunca en claro:
  - iOS y macOS: en el Llavero (almacén por defecto de supabase-swift).
  - Android: cifrada con AES-GCM y una clave de Android Keystore que no sale del
    dispositivo, en las preferencias de la app. Una sesión en claro de versiones
    anteriores se cifra y se borra al arrancar; si no se puede descifrar, la app
    arranca sin sesión. Esas preferencias quedan fuera de las copias en la nube
    y de la transferencia entre dispositivos.
- Los logs marcan importes, nombres y notas como privados.
- «Borrar datos» borra en el servidor sólo lo que creó quien lo pide. Lo de otros miembros se borra sólo si cuelga de algo suyo (p. ej. los movimientos de una cuenta).

## Avisar de un problema

Abre un aviso privado en la pestaña *Security* del repositorio
(«Report a vulnerability»), no un issue público.
