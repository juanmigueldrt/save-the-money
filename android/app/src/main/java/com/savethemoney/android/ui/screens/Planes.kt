package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurrenceUnit
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.monthlyTotal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

/** 20 Pagos fijos: total del mes y cargos recurrentes agrupados en próximos e ingresos. */
@Composable
fun Pantalla20(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val hoy = planning.today()
    val porFecha = planning.activeSeries.sortedBy { it.nextDue(hoy) ?: LocalDate.MAX }
    val gastos = porFecha.filter { it.kind != RecurringKind.Income }
    val ingresos = porFecha.filter { it.kind == RecurringKind.Income }
    val archivados = planning.series.filter { it.isArchived }
    val total = planning.series.monthlyTotal(RecurringKind.Subscription, hoy) + planning.series.monthlyTotal(RecurringKind.Essential, hoy)
    fun editar(s: RecurringSeries?) {
        planning.seriesToEdit = s
        nav.go(21)
    }
    StmScreen(
        topBar = {
            // En el diseño la fila mide 60 (no 64) y el título va justo debajo, sin subtítulo.
            Box(Modifier.fillMaxWidth().height(60.dp)) {
                TopBar(null, onNav = nav::back) { IconBtn(StmIcons.search, null, contentDescription = "Buscar") }
            }
            Text("Pagos fijos", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        fab = { Fab("Nuevo pago") { editar(null) } },
        snackbar = planning.error?.let { e -> { Snackbar(e) } },
    ) {
        StmCard {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f).padding(top = 4.dp)) {
                    Text("Este mes", style = StmType.labelMedium, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    Text(Money.format(total), style = StmType.titleLarge, color = c.onSurface)
                }
                Tag(if (gastos.size == 1) "1 pago" else "${gastos.size} pagos")
            }
        }
        Spacer(Modifier.height(16.dp))
        if (porFecha.isEmpty() && archivados.isEmpty()) {
            StmCard {
                Text(
                    "Apunta suscripciones, alquiler, luz o tu nómina para ver cuánto suman y recibir un aviso antes de cada cobro.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
            }
        } else {
            ListCard {
                if (gastos.isNotEmpty()) {
                    ListHeader("Próximos")
                    gastos.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
                if (ingresos.isNotEmpty()) {
                    ListHeader("Ingresos")
                    ingresos.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
                if (archivados.isNotEmpty()) {
                    ListHeader("Archivados")
                    archivados.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
            }
        }
    }
}

/** 21 Nuevo o editar pago fijo: tipo, importe, periodicidad, precio de oferta con contador de cargos y avisos. */
@Composable
fun Pantalla21(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val editando = remember { planning.takeSeries() }
    val base = remember(planning.series) { editando ?: if (session.capture) planning.series.firstOrNull { it.name == "Streaming" } else null }
    val tipos = RecurringKind.entries
    var kind by remember(base) { mutableIntStateOf(tipos.indexOf(base?.kind ?: RecurringKind.Subscription)) }
    var name by remember(base) { mutableStateOf(base?.name ?: "") }
    var amount by remember(base) { mutableStateOf(base?.let { Money.format(it.amountMinor, symbol = false) } ?: "") }
    var cada by remember(base) { mutableStateOf(base?.recurrence ?: Recurrence.Monthly) }
    var fecha by remember(base) { mutableStateOf(base?.startDay ?: finance.today()) }
    var conFin by remember(base) { mutableStateOf(base?.endDay != null) }
    var fin by remember(base) { mutableStateOf(base?.endDay ?: finance.today()) }
    var cuenta by remember(base) { mutableStateOf(base?.accountId) }
    var categoria by remember(base) { mutableStateOf(base?.categoryId) }
    var offer by remember(base) { mutableStateOf(base?.hasIntro ?: false) }
    var offerPrice by remember(base) { mutableStateOf(base?.introMinor?.let { Money.format(it, symbol = false) } ?: "") }
    var charges by remember(base) { mutableIntStateOf(base?.introCharges ?: 3) }
    var remind by remember(base) { mutableStateOf(base == null || base.remindDaysBefore != null) }
    var dias by remember(base) { mutableIntStateOf(base?.remindDaysBefore ?: 1) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf<String?>(null) }
    var confirmar by remember { mutableStateOf(false) }
    val action = rememberAction()
    val esIngreso = tipos[kind] == RecurringKind.Income
    val tipoCategoria = if (esIngreso) CategoryKind.Income else CategoryKind.Expense

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val dinero = Money.parse(amount)?.takeIf { it > 0 } ?: falla("El importe no es válido.")
        val conOferta = offer && !esIngreso
        val oferta = if (conOferta) Money.parse(offerPrice)?.takeIf { it > 0 } ?: falla("El precio de oferta no es válido.") else null
        val item = (editando ?: RecurringSeries("", planning.household.id, name, amountMinor = dinero, startsOn = fecha.toString())).copy(
            name = name, kind = tipos[kind], amountMinor = dinero, accountId = cuenta, categoryId = categoria,
            every = cada.every, unit = cada.unit, startsOn = fecha.toString(), endsOn = if (conFin) fin.toString() else null,
            remindDaysBefore = if (remind) dias else null, introMinor = oferta, introCharges = if (conOferta) charges else null,
        )
        planning.save(item)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando != null) "Editar pago fijo" else "Nuevo pago fijo", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            confirmar && editando != null -> {
                {
                    StmDialog(
                        "¿Borrar este pago fijo?",
                        "Se borra para todo el hogar. Los movimientos ya apuntados no se tocan.",
                        icon = StmIcons.deleteForever,
                        onDismiss = { confirmar = false },
                        actions = {
                            Btn("Cancelar", { confirmar = false }, kind = BtnKind.Text)
                            Btn("Borrar", {
                                action.run {
                                    planning.delete(editando)
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        },
                    )
                }
            }
            selector != null -> {
                {
                    val cerrar = { selector = null }
                    when (selector) {
                        "cada" -> SelectorSheet(
                            "Frecuencia",
                            (if (cada in Recurrence.Common) Recurrence.Common else Recurrence.Common + cada).map { r -> r.title to { cada = r } },
                            cerrar,
                        )
                        "cuenta" -> SelectorSheet(
                            "Cuenta",
                            listOf<Pair<String, () -> Unit>>("Sin cuenta" to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                            cerrar,
                        )
                        else -> SelectorSheet(
                            "Categoría",
                            listOf<Pair<String, () -> Unit>>("Sin categoría" to { categoria = null }) + finance.categories(tipoCategoria).map { x -> x.name to { categoria = x.id } },
                            cerrar,
                        )
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(
                tipos.map { it.title }, kind,
                { nuevo ->
                    kind = nuevo
                    // Una categoría de gasto no vale para un ingreso, y al revés.
                    val quiere = if (tipos[nuevo] == RecurringKind.Income) CategoryKind.Income else CategoryKind.Expense
                    if (finance.category(categoria)?.kind != quiere) categoria = null
                },
            )
            FilledField("Nombre", name, { name = it })
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField("Importe", amount, { amount = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal)
                FilledField("Cada", periodo(cada), modifier = Modifier.weight(1f), trailing = StmIcons.arrowDropDown, onClick = { selector = "cada" })
            }
            FilledField(
                if (editando != null) "Desde" else "Próximo cargo", Fechas.largo(fecha, finance.today()),
                trailing = StmIcons.calendarToday, onClick = { eligeFecha = "inicio" },
            )
            if (!esIngreso) {
                ListCard {
                    ListItem(
                        "Precio de oferta al principio", "Por ejemplo, 3 meses a 5,99 €",
                        trailing = { StmSwitch(offer) { offer = it } },
                    )
                }
                if (offer) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilledField(
                            "Precio de oferta", offerPrice, { offerPrice = it }, Modifier.weight(1f),
                            suffix = "€", keyboard = KeyboardType.Decimal, autoFocus = session.capture,
                        )
                        Stepper(if (charges == 1) "1 cargo" else "$charges cargos", { charges = (charges - 1).coerceAtLeast(1) }, { charges = (charges + 1).coerceAtMost(36) })
                    }
                }
            }
            ListCard {
                ListItem("Se comparte con todo el hogar")
                Divider(inset = 16.dp)
                ListItem("Avisarme ${textoAviso(dias)}", trailing = { StmSwitch(remind) { remind = it } })
            }
            // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
            if (remind) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Cuándo avisar", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Stepper(when (dias) { 0 -> "Mismo día"; 1 -> "1 día"; else -> "$dias días" }, { dias = (dias - 1).coerceAtLeast(0) }, { dias = (dias + 1).coerceAtMost(14) })
                }
            }
            FilledField("Cuenta", finance.account(cuenta)?.name ?: "Sin cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField("Categoría", finance.category(categoria)?.name ?: "Sin categoría", trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
            ListCard {
                ListItem("Tiene fecha de fin", trailing = { StmSwitch(conFin) { conFin = it } })
            }
            if (conFin) {
                FilledField("Último cargo", Fechas.largo(fin, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "fin" })
            }
            if (editando != null) {
                Btn(
                    if (editando.isArchived) "Reactivar" else "Archivar (ya no se paga)",
                    {
                        action.run {
                            planning.setArchived(editando, !editando.isArchived)
                            nav.back()
                        }
                    },
                    kind = BtnKind.Text,
                )
                Btn("Borrar", { confirmar = true }, kind = BtnKind.Text, color = c.error)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    eligeFecha?.let { campo ->
        SelectorFecha(if (campo == "fin") fin else fecha, { if (campo == "fin") fin = it else fecha = it }) { eligeFecha = null }
    }
}

/** 22 Metas: filtros y tarjetas de cada meta con su progreso. */
@Composable
fun Pantalla22(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    var filter by remember { mutableIntStateOf(0) }
    val visibles = planning.progress.filter { p ->
        when (filter) {
            0 -> p.goal.kind == GoalKind.Savings && !p.isReached
            1 -> p.goal.kind == GoalKind.Debt && !p.isReached
            else -> p.isReached
        }
    }
    fun nueva() {
        planning.goalToEdit = null
        nav.go(24)
    }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) { IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones") }
            LargeTitle("Metas", "Fija metas (y cúmplelas)")
        },
        bottomBar = { NavBar(Tab.Metas, nav::tab) },
        fab = { Fab("Nueva meta") { nueva() } },
        snackbar = planning.error?.let { e -> { Snackbar(e) } },
    ) {
        ChipRow {
            listOf("Ahorro", "Deudas", "Completadas").forEachIndexed { i, label ->
                Chip(label, selected = i == filter, onClick = { filter = i })
            }
        }
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (planning.progress.isEmpty()) {
                StmCard {
                    Text("Sin metas todavía", style = StmType.titleMedium, color = c.onSurface)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Crea una meta para ahorrar (un viaje, un fondo de emergencia) o para terminar de pagar una deuda. Verás cuánto falta y cuándo llegarás.",
                        style = StmType.bodyMedium, color = c.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Btn("Crear una meta", ::nueva)
                }
            } else if (visibles.isEmpty()) {
                Text("No hay metas en esta sección.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            visibles.forEach { p ->
                val deuda = p.goal.kind == GoalKind.Debt
                GoalCard(
                    iconoMeta(p.goal), p.goal.trimmedName, resumenMeta(p), p.fraction, importe(p.saved), "de ${importe(p.goal.targetMinor)}",
                    if (deuda) c.errorContainer else c.secondaryContainer,
                    if (deuda) c.onErrorContainer else c.onSecondaryContainer,
                ) {
                    planning.selectedGoalId = p.goal.id
                    nav.go(23)
                }
            }
        }
    }
}

/** 23 Detalle de meta: lo ahorrado, la proyección y las aportaciones. */
@Composable
fun Pantalla23(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val goal = planning.selectedGoal ?: planning.goals.firstOrNull().takeIf { session.capture } ?: return
    val p = planning.progress(goal)
    val aportes = planning.contributions(goal)
    val miembros by produceState(emptyList<HouseholdMember>(), planning.household.id) {
        value = runCatching { session.backend.members(planning.household.id) }.getOrDefault(emptyList())
    }
    var borrando by remember { mutableStateOf<GoalContribution?>(null) }
    val action = rememberAction()
    StmScreen(
        topBar = {
            TopBar(goal.trimmedName, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    planning.goalToEdit = goal
                    nav.go(24)
                }, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
            }
        },
        fab = {
            Fab(if (goal.kind == GoalKind.Savings) "Aportar" else "Apuntar pago") {
                planning.selectedGoalId = goal.id
                nav.go(35)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = borrando?.let { item ->
            {
                SelectorSheet(
                    Fechas.corto(item.day),
                    listOf<Pair<String, () -> Unit>>("Borrar esta aportación" to { action.run { planning.delete(item) } }),
                    { borrando = null },
                )
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text(if (goal.kind == GoalKind.Savings) "Ahorrado" else "Pagado", style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(importe(p.saved), style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.dp))
        Text("de ${importe(goal.targetMinor)} · ${(p.fraction * 100).roundToInt()} %", style = StmType.bodyMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        GoalProgress(p.fraction)
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Proyección", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            curva(p)?.let { puntos ->
                LineChart(puntos, plotHeight = 120.dp, color = c.tertiary)
                Spacer(Modifier.height(8.dp))
            }
            Text(proyeccion(p, planning.today()), style = StmType.bodyMedium, color = if (p.isOnTrack == false) c.error else c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Aportaciones")
            if (aportes.isEmpty()) ListItem("Todavía no hay aportaciones.")
            aportes.forEachIndexed { i, item ->
                if (i > 0) Divider()
                val nombre = miembros.firstOrNull { it.profile.id == item.createdBy }?.profile?.name
                ListItem(
                    Money.format(item.amountMinor, decimals = item.amountMinor % 100 != 0L, signed = true),
                    listOfNotNull(Fechas.corto(item.day), nombre).joinToString(" · "),
                    leading = { Avatar(nombre?.take(1)?.uppercase() ?: "·") },
                    trailing = item.note?.let { n -> { Note(n) } },
                    onClick = { borrando = item },
                )
            }
        }
        Spacer(Modifier.height(72.dp))
    }
}

/** 24 Nueva o editar meta: tipo, nombre, importe (con error), fecha, aporte necesario y datos opcionales. */
@Composable
fun Pantalla24(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val editando = remember { planning.takeGoal() }
    val base = remember(planning.goals) { editando ?: if (session.capture) planning.goals.firstOrNull { it.name == "Viaje a Lisboa" } else null }
    val hoy = planning.today()
    var kind by remember(base) { mutableIntStateOf(if (base?.kind == GoalKind.Debt) 1 else 0) }
    var name by remember(base) { mutableStateOf(base?.name ?: "") }
    // La captura enseña el estado de error del diseño.
    var target by remember(base) { mutableStateOf(if (session.capture) "abc" else base?.let { Money.format(it.targetMinor, symbol = false) } ?: "") }
    var fecha by remember(base) { mutableStateOf(base?.targetDay) }
    var starting by remember(base) { mutableStateOf(base?.startingMinor?.takeIf { it != 0L }?.let { Money.format(it, symbol = false) } ?: "") }
    var plan by remember(base) { mutableStateOf(base?.monthlyPlanMinor?.let { Money.format(it, symbol = false) } ?: "") }
    var cuenta by remember(base) { mutableStateOf(base?.accountId) }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeCuenta by remember { mutableStateOf(false) }
    var confirmar by remember { mutableStateOf(false) }
    val action = rememberAction()
    val deuda = kind == 1
    val invalid = target.isNotEmpty() && (Money.parse(target) ?: 0) <= 0
    val objetivo = Money.parse(target)?.takeIf { it > 0 } ?: base?.targetMinor
    val limite = fecha
    val necesario = if (limite != null && objetivo != null) {
        GoalProgress(
            Goal(editando?.id ?: "", "", name, targetMinor = objetivo, startingMinor = Money.parse(starting) ?: 0, targetOn = limite.toString()),
            planning.contributions, hoy,
        ).neededMonthly
    } else {
        null
    }

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val meta = Money.parse(target)?.takeIf { it > 0 } ?: falla(if (deuda) "Indica cuánto se debía." else "Indica cuánto quieres juntar.")
        // Un campo vacío es cero o nada; lo que no se entiende, se avisa.
        val inicio = if (starting.isBlank()) 0 else Money.parse(starting) ?: falla("Algún importe no es válido.")
        val previsto = if (plan.isBlank()) null else Money.parse(plan) ?: falla("Algún importe no es válido.")
        val item = (editando ?: Goal("", planning.household.id, name, targetMinor = meta)).copy(
            name = name, kind = if (deuda) GoalKind.Debt else GoalKind.Savings, targetMinor = meta, startingMinor = inicio,
            monthlyPlanMinor = previsto, targetOn = fecha?.toString(), accountId = cuenta,
        )
        planning.save(item)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando != null) "Editar meta" else "Nueva meta", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            confirmar && editando != null -> {
                {
                    StmDialog(
                        "¿Borrar esta meta?",
                        "Se borran también sus aportaciones, para todo el hogar. No se puede deshacer.",
                        icon = StmIcons.deleteForever,
                        onDismiss = { confirmar = false },
                        actions = {
                            Btn("Cancelar", { confirmar = false }, kind = BtnKind.Text)
                            Btn("Borrar", {
                                action.run {
                                    planning.delete(editando)
                                    // Se sale también del detalle, que ya no existe.
                                    nav.back()
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        },
                    )
                }
            }
            eligeCuenta -> {
                {
                    SelectorSheet(
                        "Cuenta asociada",
                        listOf<Pair<String, () -> Unit>>("Ninguna" to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                        { eligeCuenta = false },
                    )
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("Ahorro", "Pagar deuda"), kind, { kind = it })
            FilledField("Nombre de la meta", name, { name = it }, supporting = "Lo verás en tu lista de metas")
            FilledField(
                if (deuda) "Cuánto se debía al empezar" else "Importe objetivo", target, { target = it }, keyboard = KeyboardType.Decimal,
                trailing = if (invalid) StmIcons.error else null,
                supporting = if (invalid) "Escribe un importe, por ejemplo 150" else null,
                error = invalid,
            )
            FilledField(
                "Fecha límite", limite?.let { "${Fechas.mesTitulo(it)} ${it.year}" } ?: "Sin fecha",
                trailing = StmIcons.calendarToday, onClick = { eligeFecha = true },
            )
            if (necesario != null && limite != null) {
                val meses = maxOf(1, ChronoUnit.MONTHS.between(YearMonth.from(hoy), YearMonth.from(limite)).toInt())
                StmCard(color = c.surfaceContainerHighest) {
                    Text("Aporte mensual necesario", style = StmType.labelMedium, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    Text("${importe(necesario)}/mes", style = StmType.titleLarge, color = c.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(if (meses == 1) "durante 1 mes" else "durante $meses meses", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
            ListCard {
                ListItem("Se comparte con el hogar", "Todos podrán ver y aportar")
            }
            // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
            if (limite != null) Btn("Quitar la fecha", { fecha = null }, kind = BtnKind.Text)
            FilledField(if (deuda) "Lo que ya has pagado (opcional)" else "Lo que ya tienes (opcional)", starting, { starting = it }, keyboard = KeyboardType.Decimal)
            FilledField("Aportación mensual prevista (opcional)", plan, { plan = it }, keyboard = KeyboardType.Decimal)
            FilledField("Cuenta asociada", finance.account(cuenta)?.name ?: "Ninguna", trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true })
            if (editando != null) {
                Btn(
                    if (editando.isArchived) "Desarchivar" else "Archivar",
                    {
                        action.run {
                            planning.setArchived(editando, !editando.isArchived)
                            nav.back()
                        }
                    },
                    kind = BtnKind.Text,
                )
                Btn("Borrar meta y aportaciones", { confirmar = true }, kind = BtnKind.Text, color = c.error)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    if (eligeFecha) SelectorFecha(limite ?: hoy.plusYears(1), { fecha = it }) { eligeFecha = false }
}

/** Aportación o pago de una deuda. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla35(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val goal = planning.selectedGoal ?: return
    var amount by remember { mutableStateOf("") }
    var sacar by remember { mutableStateOf(false) }
    var fecha by remember { mutableStateOf(finance.today()) }
    var nota by remember { mutableStateOf("") }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()
    val ahorro = goal.kind == GoalKind.Savings

    fun guardar() = action.run {
        val dinero = Money.parse(amount)?.takeIf { it > 0 } ?: throw AppError.InvalidInput("El importe no es válido.")
        planning.contribute(if (sacar) -dinero else dinero, goal, fecha, nota)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (ahorro) "Aportación" else "Pago de la deuda", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Importe", amount, { amount = it }, suffix = "€", keyboard = KeyboardType.Decimal)
            if (ahorro) {
                ListCard {
                    ListItem("Sacar dinero de la meta", trailing = { StmSwitch(sacar) { sacar = it } })
                }
            }
            FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField("Nota (opcional)", nota, { nota = it })
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}

/** Sin céntimos si son redondos, como en el diseño. */
private fun importe(minor: Long) = Money.format(minor, decimals = minor % 100 != 0L)

/** «1 mes», «3 meses», «1 año». */
private fun periodo(r: Recurrence): String = when (r.unit) {
    RecurrenceUnit.Week -> if (r.every == 1) "1 semana" else "${r.every} semanas"
    RecurrenceUnit.Month -> if (r.every == 1) "1 mes" else "${r.every} meses"
    RecurrenceUnit.Year -> if (r.every == 1) "1 año" else "${r.every} años"
}

internal fun textoAviso(dias: Int) = when (dias) {
    0 -> "el mismo día"
    1 -> "1 día antes"
    else -> "$dias días antes"
}

private fun detallePago(s: RecurringSeries, hoy: LocalDate): String {
    if (s.isArchived) return "Archivado"
    val due = s.nextDue(hoy) ?: return "Terminado"
    val partes = mutableListOf(Fechas.corto(due))
    if (s.isIntro(due)) {
        partes += "oferta " + periodo(Recurrence(s.every * (s.introCharges ?: 1), s.unit))
    } else if (s.kind != RecurringKind.Income) {
        partes += s.kind.title
    }
    if (s.recurrence != Recurrence.Monthly) partes += s.recurrence.title.lowercase()
    return partes.joinToString(" · ")
}

// shortcut: el esquema no guarda icono en Android; se deduce del nombre. Si se añade elegir icono, usar goal.icon.
private fun iconoPago(s: RecurringSeries): ImageVector {
    val n = s.trimmedName.lowercase()
    return when {
        s.kind == RecurringKind.Income -> StmIcons.work
        "agua" in n -> StmIcons.waterDrop
        "gimnasio" in n || "gym" in n -> StmIcons.fitnessCenter
        s.kind == RecurringKind.Subscription -> StmIcons.liveTv
        else -> StmIcons.home
    }
}

private fun iconoMeta(g: Goal): ImageVector {
    val n = g.trimmedName.lowercase()
    return when {
        "viaje" in n -> StmIcons.flight
        "coche" in n -> StmIcons.directionsCar
        g.kind == GoalKind.Debt -> StmIcons.creditCard
        else -> StmIcons.savings
    }
}

private fun resumenMeta(p: GoalProgress): String {
    val g = p.goal
    val llegada = p.projectedMonth
    val limite = g.targetDay
    val faltan = p.monthsLeft
    return when {
        p.isReached -> if (g.kind == GoalKind.Savings) "¡Meta conseguida!" else "¡Deuda pagada!"
        g.kind == GoalKind.Debt && faltan != null -> if (faltan == 1) "Deuda · 1 cuota" else "Deuda · $faltan cuotas"
        llegada != null && faltan != null ->
            "A este ritmo, en ${Fechas.mes(llegada.atDay(1))}" + if (faltan >= 12) " de ${llegada.year}" else ""
        limite != null -> "Compartida · ${Fechas.mes(limite)} ${limite.year}"
        else -> "Faltan ${importe(p.remaining)}"
    }
}

/** Texto de la proyección: cuándo se llega, cuándo con 100 € más y si da tiempo a la fecha límite. */
private fun proyeccion(p: GoalProgress, hoy: LocalDate): String {
    if (p.isReached) return if (p.goal.kind == GoalKind.Savings) "¡Meta conseguida!" else "¡Deuda pagada!"
    val partes = mutableListOf<String>()
    val ritmo = p.monthlyPace
    val llegada = p.projectedMonth
    if (ritmo != null && llegada != null) {
        partes += "Con ${importe(ritmo)}/mes llegas en ${Fechas.mes(llegada.atDay(1))} de ${llegada.year}"
        val mas = ritmo + 10_000
        val antes = YearMonth.from(hoy).plusMonths((p.remaining + mas - 1) / mas)
        if (antes != llegada) partes += "Con ${importe(mas)}/mes, en ${Fechas.mes(antes.atDay(1))}"
    } else {
        partes += "Faltan ${importe(p.remaining)}. Añade una aportación o un plan mensual para ver cuándo llegarás"
    }
    val necesario = p.neededMonthly
    val limite = p.goal.targetDay
    if (necesario != null && limite != null) {
        val veredicto = if (p.isOnTrack == true) "vas bien" else "necesitas ${importe(necesario)} al mes"
        partes += "Para el ${limite.dayOfMonth} de ${Fechas.mes(limite)} de ${limite.year}, $veredicto"
    }
    return partes.joinToString(". ") + "."
}

/** Nueve puntos (0–1) de lo acumulado desde hoy hasta llegar; null si no hay ritmo con el que proyectar. */
private fun curva(p: GoalProgress): List<Float>? {
    val ritmo = p.monthlyPace?.takeIf { it > 0 } ?: return null
    val meses = p.monthsLeft?.takeIf { it > 0 } ?: return null
    return List(9) { i -> ((p.saved + ritmo * meses * i / 8f) / p.goal.targetMinor).coerceIn(0f, 1f) }
}

/** Fila de un pago: el importe del próximo cargo y, si va con oferta, lo que costará luego. */
@Composable
private fun FilaPago(s: RecurringSeries, hoy: LocalDate, onClick: () -> Unit) {
    val c = Stm.colors
    val due = if (s.isArchived) null else s.nextDue(hoy)
    val ahora = due?.let(s::amountOn) ?: s.amountMinor
    val texto = Money.format(ahora, signed = s.kind == RecurringKind.Income)
    val (fondo, tinta) = when (s.kind) {
        RecurringKind.Subscription -> c.tertiaryContainer to c.onTertiaryContainer
        RecurringKind.Essential -> c.secondaryContainer to c.onSecondaryContainer
        RecurringKind.Income -> c.successContainer to c.onSuccessContainer
    }
    ListItem(
        s.trimmedName, detallePago(s, hoy),
        leading = { LeadIcon(iconoPago(s), fondo, tinta) },
        trailing = if (ahora != s.amountMinor) {
            {
                Column(horizontalAlignment = Alignment.End) {
                    Text(texto, style = StmType.labelLarge, color = c.onSurface)
                    Text("luego ${Money.format(s.amountMinor)}", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
        } else {
            null
        },
        trailingText = if (ahora != s.amountMinor) null else texto,
        onClick = onClick,
    )
}

/** «Etiqueta» neutra de 24 dp en `surface-container-highest`. */
@Composable
private fun Tag(text: String) {
    Text(
        text, style = StmType.labelMedium, color = Stm.colors.onSurfaceVariant,
        modifier = Modifier.height(24.dp).clip(RoundedCornerShape(8.dp)).background(Stm.colors.surfaceContainerHighest)
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

/** «Contador» con borde: texto y botones − / + (56 dp). */
@Composable
internal fun Stepper(text: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    val c = Stm.colors
    Row(
        Modifier.width(194.dp).height(56.dp).border(1.dp, c.outline, RoundedCornerShape(4.dp)).padding(start = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
        IconBtn(StmIcons.remove, onMinus, contentDescription = "Menos")
        Spacer(Modifier.width(4.dp))
        IconBtn(StmIcons.add, onPlus, contentDescription = "Más")
    }
}

/** Tarjeta de una meta: icono, nombre, porcentaje, progreso e importes. */
@Composable
private fun GoalCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    fraction: Float,
    saved: String,
    total: String,
    container: Color = Stm.colors.secondaryContainer,
    tint: Color = Stm.colors.onSecondaryContainer,
    onClick: () -> Unit,
) {
    val c = Stm.colors
    StmCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LeadIcon(icon, container, tint)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = StmType.titleMedium, color = c.onSurface)
                Text(subtitle, style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.width(12.dp))
            Text("${(fraction * 100).roundToInt()}%", style = StmType.labelLarge, color = c.onSurface)
        }
        Spacer(Modifier.height(12.dp))
        GoalProgress(fraction)
        Spacer(Modifier.height(12.dp))
        Row {
            Text(saved, Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurface)
            Text(total, style = StmType.bodyMedium, color = c.onSurfaceVariant)
        }
    }
}

/** «Progreso» grueso de las metas: 8 dp, hueco de 6 e indicador de parada. */
@Composable
private fun GoalProgress(fraction: Float) {
    val bar = Stm.colors.primary
    val track = Stm.colors.secondaryContainer
    Canvas(Modifier.fillMaxWidth().height(8.dp)) {
        val r = CornerRadius(size.height / 2)
        val w = size.width * fraction
        val start = w + 6.dp.toPx()
        drawRoundRect(bar, size = Size(w, size.height), cornerRadius = r)
        drawRoundRect(track, Offset(start, 0f), Size(size.width - start, size.height), r)
        drawRoundRect(bar, Offset(size.width - size.height, 0f), Size(size.height, size.height), r)
    }
}

/** Texto final secundario de un elemento de lista. */
@Composable
private fun Note(text: String) {
    Text(text, Modifier.widthIn(max = 120.dp), style = StmType.bodyMediumTight, color = Stm.colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
}
