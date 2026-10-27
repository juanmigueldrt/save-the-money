# Save the Money

App de presupuesto personal para dos personas que comparten hogar: cuentas,
movimientos, presupuesto 50/30/20, flujo de caja, suscripciones, metas de ahorro
y de deudas. Nativa en SwiftUI para iPhone y Mac, con Supabase de backend.

> Este repositorio es público. No contiene claves ni datos de nadie: todo lo que
> hay en `Fixtures/` y en las pruebas es inventado. Lee [SECURITY.md](SECURITY.md)
> antes de contribuir.

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `App/` | La app multiplataforma (iOS 17 y macOS 14) |
| `Packages/STMCore` | Lógica sin interfaz: `Money`, plantilla 50/30/20, usuarios, invitaciones |
| `Packages/STMUI` | Colores, tipografías y componentes del diseño, en claro y oscuro |
| `supabase/` | Migraciones SQL, políticas RLS y sus pruebas pgTAP |
| `Config/` | Ajustes de compilación; los secretos van en `Secrets.xcconfig`, que git ignora |

## Empezar en el Mac

Necesitas Xcode 16 o posterior, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
y, para el backend local, Docker y la [CLI de Supabase](https://supabase.com/docs/guides/cli).

```sh
brew install xcodegen supabase/tap/supabase pre-commit
pre-commit install                      # busca secretos antes de cada commit
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # y rellénalo
xcodegen generate
open SaveTheMoney.xcodeproj
```

Backend local con datos de prueba:

```sh
supabase start        # muestra la URL y la clave anon locales
supabase test db      # pruebas de RLS
```

Pruebas de la lógica, sin simulador:

```sh
swift test --package-path Packages/STMCore
```

## Fuentes

El diseño usa Source Serif 4 e Inter (licencia OFL). Mientras no estén incluidas
en la app, se usan las fuentes del sistema equivalentes.
