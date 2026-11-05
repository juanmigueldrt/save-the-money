package com.savethemoney.android

/** Qué hace un toque. Los números son los de las pantallas del diseño (01–34). */
sealed interface Action {
    data class Go(val screen: Int) : Action
    data class Tab(val screen: Int) : Action
    data class Reset(val screen: Int) : Action
    data object Back : Action
}

private val TABS = listOf(4, 14, 16, 22, 30) // Inicio, Presupuesto, Flujo, Metas, Más
private val TAB_ROOTS = TABS.toSet()

/** Capas que reciben el toque cuando se pulsa un texto o icono de dentro. */
private val TAPPABLE = setOf(
    "Elemento de lista", "Botón", "FAB", "Chip", "Botón de icono", "Avatar", "Destino de navegación",
    "Tarjeta", "Tarjeta visual", "Gastado", "Próximo cargo", "Entra", "Sale", "Elemento de menú",
)

private fun tappable(n: DNode) = n.name in TAPPABLE || n.name.startsWith("Meta ")

private sealed interface Target {
    data class Text(val text: String) : Target
    data class Icon(val icon: String) : Target
}

private class Link(val screen: Int, val target: Target, val action: Action)

private fun t(screen: Int, text: String, action: Action) = Link(screen, Target.Text(text), action)
private fun i(screen: Int, icon: String, action: Action) = Link(screen, Target.Icon(icon), action)
private fun go(n: Int) = Action.Go(n)

/** El recorrido de la app: qué pantalla abre cada elemento. */
private val LINKS = listOf(
    t(1, "Entrar", Action.Reset(4)), t(1, "Crear cuenta", go(2)),
    t(2, "Crear cuenta#2", go(3)),
    t(3, "Crear hogar", Action.Reset(4)), t(3, "Unirme", Action.Reset(4)),
    i(4, "search", go(5)), t(4, "Ver todo", go(5)), t(4, "Añadir movimiento", go(7)),
    t(4, "Patrimonio neto", go(17)), t(4, "Gastado", Action.Tab(14)), t(4, "Próximo cargo", go(11)),
    t(4, "Supermercado Día", go(34)), t(4, "Nómina", go(6)), t(4, "Repsol", go(34)), t(4, "A", go(28)),
    t(5, "Supermercado Día", go(8)), t(5, "Panadería La Espiga", go(8)), t(5, "Mercadona", go(8)),
    t(5, "Frutería Lola", go(8)), t(5, "Restaurante Sol", go(11)), t(5, "Añadir", go(7)),
    t(6, "Importar CSV", go(32)),
    t(8, "Cambiar categoría", go(31)), t(8, "Aplazar con la tarjeta", go(13)), t(8, "Eliminar", Action.Back),
    t(8, "Dividir gasto", go(7)), t(8, "Ocultar de informes", Action.Back),
    t(10, "Visa compartida", go(11)), t(10, "Ver calendario", go(11)), t(10, "Mastercard", go(11)),
    t(10, "Límite", go(12)), i(10, "add", go(9)),
    i(11, "edit", go(12)), t(11, "Aplazar", go(13)), t(11, "Restaurante Sol", go(13)),
    t(13, "Cancelar", Action.Back), t(13, "Aplazar", Action.Back),
    i(14, "edit", go(15)), t(14, "Comida", go(5)), t(14, "Ocio", go(5)), t(14, "Transporte", go(5)),
    t(15, "Aplicar", Action.Back),
    t(16, "Entra", go(5)), t(16, "Sale", go(5)),
    t(17, "Cuentas", go(6)), t(17, "Inversiones", go(25)), t(17, "Tarjetas", go(10)), i(17, "add", go(18)),
    i(18, "ios_share", go(19)), t(18, "Ahorro medio", go(19)), t(18, "Categoría que más sube", go(14)),
    t(20, "Nuevo pago", go(21)), t(20, "Alquiler", go(21)), t(20, "Streaming", go(21)),
    t(22, "Nueva meta", go(24)), t(22, "Fondo de emergencia", go(23)), t(22, "Viaje a Lisboa", go(23)),
    t(22, "Préstamo del coche", go(23)), i(23, "edit", go(24)),
    i(25, "event_repeat", go(27)), i(25, "add", go(26)), t(25, "Fondo indexado mundial", go(26)),
    t(26, "Comprar#2", Action.Back), t(27, "Fondo indexado mundial", go(26)),
    t(28, "Invitar a alguien", go(29)),
    t(30, "Tarjetas", go(10)), t(30, "Pagos fijos", go(20)), t(30, "Patrimonio, informes y score", go(17)),
    t(30, "Inversiones", go(25)), t(30, "Hogar", go(28)), t(30, "Importar CSV", go(32)),
    t(30, "Categorías", go(31)), t(30, "Borrar datos y empezar de cero", go(33)),
    t(32, "Importar 148 movimientos", go(5)),
    t(33, "Cancelar", Action.Back), t(33, "Borrar", Action.Reset(1)),
    t(34, "Editar", go(7)), t(34, "Duplicar", Action.Back), t(34, "Aplazar", go(13)), t(34, "Eliminar", Action.Back),
)

/** Engancha las acciones a las capas: enlaces de la lista, barra de navegación, atrás y «Guardar». */
fun wireNavigation(design: Design) {
    design.screens.forEachIndexed { index, screen ->
        val number = index + 1
        val nodes = screen.descendants().toList()

        nodes.filter { it.name == "Barra de navegación" }.forEach { bar ->
            bar.children.filter { it.name == "Destino de navegación" }.forEachIndexed { i, dest ->
                dest.action = Action.Tab(TABS[i])
            }
        }
        nodes.filter { it.name == "Botón de icono" }.forEach { btn ->
            val icon = btn.children.firstOrNull { it.type == 'I' }?.name
            if (icon in setOf("arrow_back", "close") && btn.x < 20f && number !in TAB_ROOTS) btn.action = Action.Back
        }
        nodes.filter { it.name == "Botón" && it.descendants().any { d -> d.text?.text == "Guardar" } }
            .forEach { it.action = Action.Back }

        LINKS.filter { it.screen == number }.forEach { link ->
            val node = when (val target = link.target) {
                is Target.Text -> {
                    val (text, nth) = target.text.split("#").let { it[0] to (it.getOrNull(1)?.toInt() ?: 1) }
                    nodes.filter { it.text?.text == text }.getOrNull(nth - 1)
                        ?.let { found -> sequenceOf(found).plus(found.ancestors()).firstOrNull(::tappable) }
                }
                is Target.Icon -> nodes.firstOrNull { it.name == "Botón de icono" && it.children.any { c -> c.name == target.icon } }
            }
            checkNotNull(node) { "Pantalla $number: no encuentro ${link.target}" }
            node.action = link.action
        }
    }
}
