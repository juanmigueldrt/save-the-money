# Registro de errores e informes de fallos (ORC-72)

Estado: el registro local está hecho. Los informes de fallos que salen del dispositivo están pendientes de la decisión del dueño («Necesita al dueño»).

## El problema

Las apps no dejaban ningún rastro cuando algo fallaba. Los errores del servidor que la app no conoce se convertían en `unknown(código)` y el tipo del error se perdía, así que un fallo en un dispositivo no se podía diagnosticar.

## Lo que se hace ahora: registro local, sin datos personales

Cada plataforma tiene **una sola función pura** que decide qué va en una línea del registro, y es la única vía por la que la app registra errores:

- iOS y macOS: `ErrorLog.line(operation:error:)` en `Packages/STMData/Sources/STMData/ErrorLog.swift`, escrita con `Logger` (os) en la categoría `errores`.
- Android: `lineaDeError(operacion, error)` en `android/app/src/main/java/com/savethemoney/android/data/RegistroDeErrores.kt`, escrita con `android.util.Log` con la etiqueta `STM`.

La línea tiene como mucho cuatro campos:

| Campo | De dónde sale |
|---|---|
| `operacion` | El nombre de la función de la app que falló (un texto fijo del código). |
| `tipo` | El tipo del error (`PostgrestError`, `URLError`, `AppError.unknown`…). |
| `codigo` | El código del error: SQLSTATE o `PGRST…` de Postgres, el código de Supabase Auth (`invalid_credentials`…), el de `URLError`, o el código de `AppError.unknown`. Sólo letras, números y `_`, como mucho 40. |
| `http` | El estado HTTP de la respuesta, si lo hay. |

Nunca entra en la línea el mensaje del error. Los mensajes del servidor pueden citar valores de la fila (importes, nombres, notas, beneficiarios, etiquetas, nombres de usuario, correos, códigos de invitación), y los cuerpos de petición y respuesta también. Tampoco entran ids de hogar, de usuario ni de fila.

Dónde se registra (sólo fallos, nunca lo que va bien):

- Cada llamada al servidor pasa por `mapped` (`SupabaseBackend` en las dos plataformas). Ahí se registra el error tal como llega, antes de convertirlo en el mensaje en español, así que un `unknown` conserva el tipo y el código.
- Los errores que no vienen del servidor (un fallo de la propia app) se registran donde se enseñan: `ServerModel.perform` y `reloadAfterSave` en iOS y `Action.run` y `reloadAfterSave` en Android.
- Las cancelaciones no se registran: no son fallos.

Los registros se quedan en el dispositivo. Nadie los recibe salvo que el usuario los comparta (por ejemplo, un `sysdiagnose` en iOS o `adb logcat` en Android).

## Informes de fallos que salen del dispositivo

Opciones:

1. **Ninguno.** Sólo el registro local de arriba. Sin coste ni datos nuevos que proteger, pero un fallo sólo se diagnostica si el usuario comparte el registro.
2. **Los de las plataformas.** App Store Connect (Xcode Organizer) recibe informes de cierres y bloqueos de quien ha aceptado «Compartir con desarrolladores de apps» en Ajustes. Google Play Console (Android vitals) los recibe de quien ha aceptado compartir datos de uso y diagnóstico. No hace falta código ni dependencias: ya llegan si la app se publica en las tiendas, con el consentimiento que pide el sistema. Sólo traen la pila de llamadas del cierre, no los registros de la app.
3. **Un servicio de terceros (Sentry, Crashlytics…) con consentimiento.** Más detalle (errores que no cierran la app, contexto), pero añade una dependencia, un tercero que recibe datos del dispositivo, una pantalla de consentimiento, un cambio en la política de privacidad y en las fichas de las tiendas, y el riesgo de que un mensaje con datos personales llegue al tercero.

**Recomendación:** ninguno más allá de lo que ya dan las plataformas (opción 2), por ahora. Se vuelve a mirar si los informes de las tiendas no bastan para encontrar un fallo que se repite.

## Necesita al dueño

- Decidir entre las opciones 1, 2 y 3. Con la recomendada (2) no hay que cambiar código: basta con mirar Xcode Organizer y Android vitals tras publicar. Con la 3 hay que elegir el servicio, escribir la pantalla de consentimiento y actualizar la política de privacidad y las fichas de privacidad de las tiendas antes de enviar nada.
