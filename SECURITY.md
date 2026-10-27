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
  aprobación manual en el entorno `produccion`.

## En la app

- La sesión se guarda en el Llavero.
- Los logs marcan importes, nombres y notas como privados.
- «Borrar datos» borra en el servidor sólo los datos de quien lo pide.

## Avisar de un problema

Abre un aviso privado en la pestaña *Security* del repositorio
(«Report a vulnerability»), no un issue público.
