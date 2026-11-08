# Plan de la fase 8 (Android)

Hechos: paso 1 (34 pantallas nativas) y paso 2 (login, hogar, invitaciones y modo demo sin clave).

3. Cuentas y movimientos reales: listar, crear, editar y borrar (accounts, transactions, categories, vista account_balances) e importar CSV como en iOS.
4. Presupuesto 50/30/20 (budgets, budget_lines, RPC save_budget) con el semicírculo, y Flujo (Sankey) con movimientos reales.
5. Pagos fijos y suscripciones (recurring_series), metas con aportaciones y proyección (goals, goal_contributions), avisos locales de Android.
6. Más opciones: exportar CSV, PDF de pagos del mes, tema claro/oscuro, borrar datos y empezar de cero (RPC reset_household), cerrar sesión, escanear QR con cámara. Si da tiempo: tarjetas de crédito, patrimonio, score e inversiones como en iOS.

Reglas: replicar los cálculos de `Packages/STMCore` y el comportamiento de `App/`. No cambiar `supabase/migrations`. Un commit y un APK por paso, sin parar entre pasos, con resumen al acabar cada uno. Las claves solo en `android/local.properties`; nada de datos reales en git.
