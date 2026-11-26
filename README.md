# Save the Money

App de presupuesto personal para dos personas que comparten hogar: cuentas,
movimientos, presupuesto 50/30/20, flujo de caja, suscripciones, metas de ahorro
y de deudas. Nativa en SwiftUI para iPhone y Mac, y en Kotlin con Jetpack Compose
para Android, con Supabase de backend.

> Este repositorio es público. No contiene claves ni datos de nadie: todo lo que
> hay en `Fixtures/` y en las pruebas es inventado. Lee [SECURITY.md](SECURITY.md)
> antes de contribuir.

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `App/` | La app multiplataforma (iOS 17 y macOS 14) |
| `Packages/STMCore` | Lógica sin interfaz: `Money`, plantilla 50/30/20, usuarios, invitaciones |
| `Packages/STMData` | Cliente Supabase que implementa los servicios de `STMCore` (supabase-swift) |
| `Packages/STMUI` | Colores, tipografías y componentes del diseño, en claro y oscuro |
| `android/` | La app Android (Kotlin, Compose, minSdk 28): lógica en `data/`, pantallas en `ui/` |
| `supabase/` | Migraciones SQL, políticas RLS y sus pruebas pgTAP en `tests/database/` |
| `testdata/vectors/` | Vectores de prueba compartidos por iOS y Android (ver abajo) |
| `Config/` | Ajustes de compilación; los secretos van en `Secrets.xcconfig`, que git ignora |
| `.github/workflows/` | CI (`ci.yml`) y aplicación de migraciones (`deploy-db.yml`) |

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

Pruebas de la app en el Mac (las mismas que corre CI; requiere el `Secrets.xcconfig` de arriba):

```sh
xcodebuild test -project SaveTheMoney.xcodeproj -scheme SaveTheMoney -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

Para compilar en el simulador de iPhone, usa `-destination 'generic/platform=iOS Simulator'` con `CODE_SIGNING_ALLOWED=NO`.

## Android

Necesitas JDK 17 (`brew install openjdk@17`) y el SDK de Android. Apunta
`JAVA_HOME` y `ANDROID_HOME` a ellos (en Homebrew, por ejemplo,
`/opt/homebrew/share/android-commandlinetools`).

```sh
cd android
./gradlew testDebugUnitTest lintDebug ktlintCheck
```

Sin `android/local.properties` la app compila y arranca en modo demo, sin datos
ni claves. Para usar el Supabase local, pasa la URL y la clave anon con
`-Psupabase.url=…` y `-Psupabase.anonKey=…` (el `supabase start` las muestra). Las
claves reales van sólo en `android/local.properties`, que git ignora.

Las líneas base de Android Lint y ktlint (`android/app/lint-baseline.xml` y
`android/app/config/ktlint/baseline.xml`) ocultan los avisos que ya había: sólo
fallan los nuevos.

## Base de datos

`supabase start` levanta Postgres, Auth y Studio en Docker. `supabase test db`
ejecuta las pruebas pgTAP de `supabase/tests/database/`, que comprueban RLS y las
funciones SQL. Las migraciones de producción sólo se aplican desde GitHub Actions
(`deploy-db.yml`), con aprobación manual.

## Pruebas compartidas y CI

Los archivos de `testdata/vectors/` los leen `SharedVectorsTests.swift` (STMCore) y
`SharedVectorsTest.kt` (Android). Si un comportamiento debe ser igual en las dos
plataformas, añade el caso ahí, no dos pruebas separadas.

`ci.yml` ejecuta seis trabajos en cada PR:

| Trabajo | Qué comprueba | Cómo reproducirlo |
| --- | --- | --- |
| Secretos | gitleaks en todo el historial | `docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.21.2 git /repo --config /repo/.gitleaks.toml --redact --verbose` |
| STMCore (Linux) | pruebas y cobertura de `STMCore` | `swift test --package-path Packages/STMCore` |
| Supabase | migraciones y RLS | `supabase start` y `supabase test db` |
| App (iOS y macOS) | compilación para iPhone y pruebas en Mac | comandos de arriba |
| Android | pruebas unitarias, Lint y ktlint | `./gradlew testDebugUnitTest lintDebug` y `./gradlew ktlintCheck` |
| SwiftLint | estilo de Swift con `--strict` | `docker run --rm -v "$PWD:/repo" -w /repo ghcr.io/realm/swiftlint:0.65.0 lint --strict` |

SwiftLint usa `.swiftlint.yml` y `.swiftlint-baseline.json`. La línea base guarda
rutas bajo `/repo`, por eso CI y el comando de arriba montan el repo en esa ruta.

## Fuentes

El diseño sigue el manual "Estilo Monarch" v2. Los títulos usan Source Serif 4
(licencia SIL OFL 1.1), incluida en `Packages/STMUI/Sources/STMUI/Fonts`; el resto
del texto usa la fuente del sistema (SF Pro) con Dynamic Type.
