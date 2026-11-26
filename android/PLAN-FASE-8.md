# Plan de la fase 8 (Android)

Estado: los pasos 1 a 6 tienen código en `android/app/src/main/java/com/savethemoney/android/`.
Lo comprobado es que el código existe y usa las tablas y RPC indicadas; no se ha
probado en un dispositivo ni se ha generado un APK por paso.

1. Hecho: 34 pantallas nativas (`ui/screens/`).
2. Hecho: login, hogar, invitaciones y modo demo sin clave (`ui/Session.kt`, `data/Backend.kt`).
3. Hecho: cuentas y movimientos (accounts, transactions, categories, vista account_balances), listar, crear, editar y borrar, e importar CSV (`data/CsvImport.kt`, `ui/screens/Mas.kt`).
4. Hecho: presupuesto 50/30/20 (budgets, budget_lines, RPC `save_period_budget`) con el semicírculo, y Flujo (Sankey, `ui/screens/Analisis.kt`).
5. Hecho: pagos fijos y suscripciones (recurring_series), metas con aportaciones y proyección (goals, goal_contributions), avisos locales (`ui/Avisos.kt`).
6. Hecho: exportar CSV (`data/Export.kt`), PDF de pagos del mes (`ui/Exportar.kt`), tema claro/oscuro, borrar datos y empezar de cero (RPC `reset_household`), cerrar sesión, escanear QR (`ui/EscanerQr.kt`). También están tarjetas de crédito (`ui/screens/Tarjetas.kt`), patrimonio (`ui/TrackingModel.kt`), score (credit_scores) e inversiones (`ui/screens/Inversiones.kt`).

Pendiente: solo probar en dispositivo los pasos 3 a 6 (su código ya está, ver arriba) y decidir si se archiva este plan.

Reglas: replicar los cálculos de `Packages/STMCore` y el comportamiento de `App/`. No cambiar `supabase/migrations`. Un commit y un APK por paso, sin parar entre pasos, con resumen al acabar cada uno. Las claves solo en `android/local.properties`; nada de datos reales en git.
