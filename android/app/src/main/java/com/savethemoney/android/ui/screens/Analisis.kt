package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.NetWorth
import com.savethemoney.android.data.NetWorthPoint
import com.savethemoney.android.data.ReportKind
import com.savethemoney.android.data.ReportPeriod
import com.savethemoney.android.data.SpendingReport
import com.savethemoney.android.data.biggestRise
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.BudgetTemplate
import com.savethemoney.android.data.CashFlow
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CategoryLine
import com.savethemoney.android.data.FlexBudget
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.SankeyLayout
import com.savethemoney.android.ui.BudgetModel
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SemicircleGauge
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.roundToLong

/** 14 Presupuesto: semicírculo 50/30/20 con leyenda y avance por categoría. */
@Composable
fun Pantalla14(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val scope = rememberCoroutineScope()
    var eligiendo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { budgets.load() }
    val report = budgets.report(finance.categories)
    val template = (budgets.budget ?: budgets.proposal)?.template ?: BudgetTemplate.FiftyThirtyTwenty
    val hoy = finance.today()
    // Cada grupo ocupa lo gastado sobre lo repartido; si no hay base, se reparte el arco entre lo gastado.
    val total = maxOf(report.base, report.groups.sumOf { it.spent }).coerceAtLeast(1).toFloat()
    val restantes = if (hoy in budgets.period) ChronoUnit.DAYS.between(hoy, budgets.period.endInclusive) else null
    val lineas = report.lines.filter { it.category.budgetGroup != null }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.edit, { nav.go(15) }, contentDescription = "Editar presupuesto")
                IconBtn(StmIcons.moreVert, { eligiendo = true }, contentDescription = "Más opciones")
            }
            LargeTitle("Presupuesto", "${tituloMes(budgets.month, hoy)} · plantilla ${template.needs}/${template.wants}/${template.savings}")
        },
        bottomBar = { NavBar(Tab.Presupuesto, nav::tab) },
        snackbar = budgets.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            { SelectorMes(budgets, hoy, { eligiendo = false }) { m -> scope.launch { budgets.show(m) } } }
        } else null,
    ) {
        if (budgets.budget == null) {
            StmCard {
                Text(
                    budgets.proposal?.let { "Aún no hay presupuesto para este mes. Puedes partir del de ${Fechas.mes(it.month.atDay(1))}." }
                        ?: "Aún no hay presupuesto para este mes. Mientras tanto, se reparten los ingresos reales con 50/30/20.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                Btn("Crear presupuesto", { nav.go(15) })
            }
            Spacer(Modifier.height(16.dp))
        }
        StmCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(300.dp, 158.dp)) {
                    SemicircleGauge(report.groups.map { Slice(it.spent.coerceAtLeast(0) / total, colorGrupo(it.group)) }, width = 300.dp, thickness = 24.dp)
                    Column(Modifier.align(Alignment.BottomCenter), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(Money.format(report.totalSpent, decimals = false), style = StmType.displaySmall, color = c.onSurface)
                        Text(
                            "de ${Money.format(report.base, decimals = false)}" + if (restantes != null) " · quedan $restantes días" else "",
                            style = StmType.bodySmall, color = c.onSurfaceVariant,
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    BudgetGroup.entries.forEach { LegendItem(colorGrupo(it), "${it.title} ${template.percentage(it)} %") }
                }
            }
        }
        if (lineas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            StmCard {
                lineas.forEachIndexed { i, line ->
                    if (i > 0) Spacer(Modifier.height(16.dp))
                    CategoryLine(line) { nav.go(5) }
                }
            }
        }
        if (report.uncategorized > 0) {
            Spacer(Modifier.height(16.dp))
            StmCard(onClick = { nav.go(5) }) {
                Row(Modifier.fillMaxWidth()) {
                    Text("Gastos sin categoría", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Text(Money.format(report.uncategorized), style = StmType.labelLarge, color = c.onSurface)
                }
                Spacer(Modifier.height(4.dp))
                Text("Ponles categoría en Movimientos para que cuenten en su grupo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
    }
}

/** 15 Editar presupuesto: modo, ingresos previstos, plantilla 50/30/20 e importes por categoría. */
@Composable
fun Pantalla15(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val inicial = budgets.draft
    var mode by remember { mutableIntStateOf(0) }
    var income by remember(inicial) { mutableStateOf(if (inicial.expectedIncome == 0L) "" else Money.input(inicial.expectedIncome)) }
    var template by remember(inicial) { mutableStateOf(inicial.template) }
    val limites = remember(inicial) { mutableStateMapOf<String, String>().apply { inicial.limits.forEach { (k, v) -> put(k, Money.input(v)) } } }
    val base = Money.parse(income)?.coerceAtLeast(0) ?: 0
    val reparto = template.allocate(base)
    val gastos = finance.categories(CategoryKind.Expense)
    val guardar = {
        action.run {
            val expected = if (income.isBlank()) 0L else Money.parse(income)?.takeIf { it >= 0 }
                ?: throw AppError.InvalidInput("Los ingresos previstos no son un importe válido.")
            val parsed = limites.filterValues { it.isNotBlank() }.mapValues { (id, text) ->
                Money.parse(text)?.takeIf { it >= 0 }
                    ?: throw AppError.InvalidInput("El límite de ${finance.category(id)?.name ?: "una categoría"} no es un importe válido.")
            }.filterValues { it > 0 }
            budgets.save(inicial.copy(expectedIncome = expected, template = template, limits = parsed))
            nav.back()
        }
    }
    LaunchedEffect(Unit) { if (budgets.budget == null && budgets.proposal == null) budgets.load() }
    StmScreen(
        topBar = {
            TopBar("Presupuesto de ${Fechas.mes(inicial.month.atDay(1))}", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Por categorías", "Flexible"), mode, { mode = it })
        Spacer(Modifier.height(16.dp))
        FilledField("Ingresos previstos", income, { income = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        Spacer(Modifier.height(16.dp))
        StmCard(color = c.surfaceContainerHighest) {
            Row(Modifier.fillMaxWidth().height(32.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Reparto ${template.needs}/${template.wants}/${template.savings}", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                SmallTonalBtn("Aplicar") { template = BudgetTemplate.FiftyThirtyTwenty }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                BudgetGroup.entries.joinToString(" · ") { "${Money.format(reparto[it] ?: 0, decimals = false)} ${it.title.lowercase()}" },
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        if (mode == 0) {
            ListCard {
                BudgetGroup.entries.forEach { group ->
                    val filas = gastos.filter { it.budgetGroup == group }
                    if (filas.isNotEmpty()) {
                        ListHeader(group.title)
                        filas.forEachIndexed { i, category ->
                            if (i > 0) Divider()
                            ListItem(
                                category.name,
                                leading = { LeadIconGrupo(iconoCategoria(category), group) },
                                trailing = { CampoLimite(category.name, limites[category.id].orEmpty()) { limites[category.id] = it } },
                            )
                        }
                    }
                }
            }
        } else {
            val flex = FlexBudget(budgets.report(finance.categories), finance.planning.series, finance.today())
            ListCard {
                ListHeader("Flexible")
                ListItem("Entra", trailingText = Money.format(flex.income))
                Divider()
                ListItem("Pagos fijos", trailingText = Money.format(-flex.fixed))
                Divider()
                ListItem("Ahorro", trailingText = Money.format(-flex.savings))
                Divider()
                ListItem("Para todo lo demás", trailingText = Money.format(flex.flexible))
                Divider()
                ListItem("Gastado", trailingText = Money.format(flex.flexibleSpent))
                Divider()
                ListItem(
                    if (flex.remaining < 0) "Gastado de más" else "Queda",
                    flex.perDay?.let { "${Money.format(it)} al día" },
                    trailingText = Money.format(flex.remaining),
                )
            }
        }
    }
}

/** 16 Flujo de caja: periodo, diagrama de flujo de ingresos a gastos y totales de entrada y salida. */
@Composable
fun Pantalla16(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val scope = rememberCoroutineScope()
    var period by remember { mutableIntStateOf(0) }
    var eligiendo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { budgets.load() }
    val months = listOf(1, 3, 12)[period]
    val report = budgets.report(finance.categories, months)
    val flow = CashFlow(report)
    val hoy = finance.today()
    val titulo = if (months == 1) tituloMes(budgets.month, hoy) else "${tituloMes(budgets.month.minusMonths(months - 1L), hoy)} – ${tituloMes(budgets.month, hoy)}"
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.calendarMonth, { eligiendo = true }, contentDescription = "Elegir mes")
            }
            LargeTitle("Flujo de caja", titulo)
        },
        bottomBar = { NavBar(Tab.Flujo, nav::tab) },
        snackbar = budgets.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            { SelectorMes(budgets, hoy, { eligiendo = false }) { m -> scope.launch { budgets.show(m) } } }
        } else null,
    ) {
        SegmentedWrap(listOf("Mes", "Trimestre", "Año"), period) { period = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("De dónde viene y a dónde va", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            if (flow.isEmpty) {
                Text(
                    "No hay movimientos en este periodo. Cuando apuntes o importes ingresos y gastos, aquí verás a dónde va tu dinero.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
            } else {
                Sankey(flow)
            }
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FlowStat("Entra", Money.format(report.income, decimals = false, signed = true), c.success, Modifier.weight(1f)) { nav.go(5) }
            FlowStat("Sale", Money.format(-report.totalSpent, decimals = false), c.onSurface, Modifier.weight(1f)) { nav.go(5) }
        }
    }
}

/** Puntos de 0 a 1 para el gráfico: de la cifra más baja a la más alta del periodo. */
internal fun normalizar(valores: List<Long>): List<Float> {
    val min = valores.minOrNull() ?: return emptyList()
    val max = valores.max()
    return valores.map { if (max == min) 0.5f else (it - min).toFloat() / (max - min) }
}

internal fun euros(minor: Long, signed: Boolean = false) = Money.format(minor, decimals = minor % 100 != 0L, signed = signed)

/** 17 Patrimonio neto: cifra, variación, evolución por periodo y lista de activos y deudas. */
@Composable
fun Pantalla17(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val tracking = finance.tracking
    val c = Stm.colors
    var range by remember { mutableIntStateOf(1) }
    LaunchedEffect(finance.recent) { if (!session.capture) tracking.loadMovements() }
    val saldos = finance.activeAccounts.map { it to finance.balance(it) }
    val hoy = NetWorth.current(finance.accounts, finance.balances, finance.today())
    val meses = listOf(2, 7, 13, tracking.monthsWithData)[range]
    val historia = tracking.history(finance.accounts, meses)
    val cambio = (historia.lastOrNull()?.net ?: 0) - (historia.firstOrNull()?.net ?: 0)
    val tramo = listOf("en 1 mes", "en 6 meses", "en 1 año", "desde el principio")[range]
    val inversiones = saldos.filter { (a, b) -> a.kind == AccountKind.Investment && b > 0 }.sumOf { it.second }
    val tarjetas = saldos.filter { (a, b) -> a.kind == AccountKind.CreditCard && b < 0 }.sumOf { it.second }
    val otrasDeudas = saldos.filter { (a, b) -> a.kind != AccountKind.CreditCard && b < 0 }.sumOf { it.second }
    StmScreen(
        topBar = {
            TopBar("Patrimonio neto", onNav = nav::back) {
                IconBtn(StmIcons.add, {
                    finance.accountToEdit = null
                    nav.go(9)
                }, contentDescription = "Añadir cuenta")
            }
        },
        snackbar = tracking.error?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        Text(if (session.capture) "48.230 €" else euros(hoy.net), style = StmType.displayMedium, color = if (hoy.net < 0) c.error else c.onSurface)
        Spacer(Modifier.height(4.dp))
        if (session.capture) Pill("+1.130 € en 6 meses") else Pill("${euros(cambio, signed = true)} $tramo", positive = cambio >= 0, icon = if (cambio >= 0) StmIcons.arrowUpward else null)
        Spacer(Modifier.height(20.dp))
        SegmentedWrap(listOf("1M", "6M", "1A", "Todo"), range) { range = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            // Alturas del diseño en una caja de 160: 156, 114,5, 129,6, 72,9, 42,7 y 0.
            LineChart(
                if (session.capture) listOf(156f, 114.5f, 129.6f, 72.9f, 42.7f, 0f).map { 1f - it / 160f } else normalizar(historia.map { it.net }),
                plotHeight = 160.dp,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Activos")
            ListItem(
                "Cuentas", leading = { LeadIcon(StmIcons.accountBalance) },
                trailingText = if (session.capture) "18.420 €" else euros(hoy.assets - inversiones), onClick = { nav.go(6) },
            )
            Divider()
            ListItem(
                "Inversiones", leading = { LeadIcon(StmIcons.candlestickChart, c.tertiaryContainer, c.onTertiaryContainer) },
                trailingText = if (session.capture) "31.950 €" else euros(inversiones), onClick = { nav.go(25) },
            )
            ListHeader("Deudas")
            ListItem(
                "Tarjetas", leading = { LeadIcon(StmIcons.creditCard, c.errorContainer, c.onErrorContainer) },
                trailingText = if (session.capture) "−2.140 €" else euros(tarjetas), onClick = { nav.go(10) },
            )
            if (otrasDeudas != 0L) {
                Divider()
                ListItem("Otras deudas", leading = { LeadIcon(StmIcons.description, c.errorContainer, c.onErrorContainer) }, trailingText = euros(otrasDeudas))
            }
        }
        // El diseño no dibuja cómo se llega a estas dos; en iOS están en el mismo apartado.
        if (!session.capture) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListItem("Informes", leading = { LeadIcon(StmIcons.monitoring) }, trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(18) })
                Divider()
                ListItem("Score crediticio", leading = { LeadIcon(StmIcons.creditScore) }, trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(19) })
            }
            Spacer(Modifier.height(16.dp))
            Text(
                "Se calcula con el saldo inicial de cada cuenta y sus movimientos. Las cuentas archivadas no cuentan.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
}

/** 18 Informes: filtros, barras de ingresos y gastos de los últimos 6 meses y resumen. */
@Composable
fun Pantalla18(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val tracking = finance.tracking
    val c = Stm.colors
    var filter by remember { mutableIntStateOf(0) }
    var kind by remember { mutableStateOf(ReportKind.Expense) }
    var period by remember { mutableStateOf(ReportPeriod.Last6Months) }
    var categoria by remember { mutableStateOf<String?>(null) }
    var selector by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(finance.recent) { if (!session.capture) tracking.loadMovements() }
    val hoy = finance.today()
    val seis = ReportPeriod.Last6Months.range(hoy)
    val movimientos = tracking.allMovements
    val ingresos = SpendingReport(movimientos, finance.categories, seis, ReportKind.Income)
    val gastos = SpendingReport(movimientos, finance.categories, seis, ReportKind.Expense)
    val tope = (ingresos.byMonth.map { it.amount } + gastos.byMonth.map { it.amount }).max().coerceAtLeast(1)
    val informe = SpendingReport(movimientos, finance.categories, period.range(hoy), kind, setOfNotNull(categoria))
    val sube = biggestRise(movimientos, finance.categories, YearMonth.from(hoy))
    StmScreen(
        topBar = {
            TopBar("Informes", onNav = nav::back) {
                if (session.capture) IconBtn(StmIcons.iosShare, { nav.go(19) }, contentDescription = "Compartir")
            }
        },
        snackbar = tracking.error?.let { e -> { Snackbar(e) } },
        overlay = selector?.let { campo ->
            {
                val cerrar = { selector = null }
                if (campo == "periodo") {
                    SelectorSheet("Periodo", ReportPeriod.entries.map { p -> p.title to { period = p } }, cerrar)
                } else {
                    val lista = finance.categories(if (kind == ReportKind.Expense) CategoryKind.Expense else CategoryKind.Income)
                    SelectorSheet("Categoría", listOf<Pair<String, () -> Unit>>("Todas" to { categoria = null }) + lista.map { x -> x.name to { categoria = x.id } }, cerrar)
                }
            }
        },
    ) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (session.capture) {
                listOf("Ingresos y gastos", "Por categoría", "Por persona", "2026").forEachIndexed { i, label ->
                    Chip(label, selected = i == filter, onClick = { filter = i })
                }
            } else {
                Chip("Ingresos y gastos", selected = filter == 0, onClick = { filter = 0 })
                Chip("Por categoría", selected = filter == 1, onClick = { filter = 1 })
                if (filter == 1) {
                    Chip(period.title, onClick = { selector = "periodo" })
                    Chip(finance.category(categoria)?.name ?: "Todas", onClick = { selector = "categoria" })
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        if (filter == 1 && !session.capture) {
            Segmented(ReportKind.entries.map { it.title }, kind.ordinal, {
                kind = ReportKind.entries[it]
                categoria = null
            })
            Spacer(Modifier.height(16.dp))
            StmCard {
                Text("${kind.title} · ${period.title.lowercase()}", style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(informe.total), style = StmType.displaySmall, color = c.onSurface)
                if (informe.byMonth.size > 1) {
                    Spacer(Modifier.height(4.dp))
                    Text("Media de ${Money.format(informe.averagePerMonth)} al mes", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(16.dp))
            if (informe.byCategory.isEmpty()) {
                Text("No hay movimientos en este periodo.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            } else {
                ListCard {
                    informe.byCategory.forEachIndexed { i, fila ->
                        if (i > 0) Divider()
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                LeadIcon(iconoCategoria(fila.category))
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(fila.title, style = StmType.bodyLarge, color = c.onSurface)
                                    Text("${Math.round(fila.share * 100)} % · ${fila.count} movimientos", style = StmType.bodySmall, color = c.onSurfaceVariant)
                                }
                                Text(Money.format(fila.amount), style = StmType.labelLarge, color = c.onSurface)
                            }
                            Spacer(Modifier.height(8.dp))
                            Progress(fila.share.toFloat())
                        }
                    }
                }
            }
            return@StmScreen
        }
        StmCard {
            Row(Modifier.fillMaxWidth()) {
                Text("Ingresos y gastos", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text("últimos 6 meses", Modifier.padding(top = 5.dp), style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            if (session.capture) {
                GroupedBars(
                    income = listOf(131.76f, 131.76f, 135.88f, 131.76f, 133.82f, 131.76f),
                    spending = listOf(111.18f, 125.59f, 140f, 107.06f, 115.29f, 52.71f),
                )
            } else {
                GroupedBars(ingresos.byMonth.map { maxOf(it.amount, 0L) * 140f / tope }, gastos.byMonth.map { maxOf(it.amount, 0L) * 140f / tope })
            }
            Spacer(Modifier.height(4.dp))
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.5.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                (if (session.capture) listOf("jun", "jul", "ago", "sep", "oct", "nov") else gastos.byMonth.map { Fechas.mes(it.month.atDay(1)).take(3) }).forEach {
                    Text(it, style = StmType.labelSmall, color = c.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                LegendItem(c.tertiary, "Ingresos")
                LegendItem(c.primary, "Gastos")
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Ahorro medio", "Lo que te queda cada mes",
                leading = { LeadIcon(StmIcons.savings, c.successContainer, c.onSuccessContainer) },
                trailingText = if (session.capture) "+452 €" else euros(ingresos.averagePerMonth - gastos.averagePerMonth, signed = true),
            )
            val texto = when {
                session.capture -> "Ocio, +18 % vs. octubre"
                sube == null -> null
                else -> sube.title + (sube.percent?.let { ", +$it %" } ?: "") + " vs. ${Fechas.mes(sube.previous.atDay(1))}"
            }
            if (texto != null) {
                Divider()
                ListItem(
                    "Categoría que más sube", texto,
                    leading = { LeadIcon(StmIcons.trendingUp, c.errorContainer, c.onErrorContainer) },
                    trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(14) },
                )
            }
        }
    }
}

/** 19 Score crediticio: indicador con la última puntuación e historial de las apuntadas a mano. */
@Composable
fun Pantalla19(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val tracking = finance.tracking
    val c = Stm.colors
    var borrando by remember { mutableStateOf<CreditScore?>(null) }
    val action = rememberAction()
    LaunchedEffect(Unit) { if (!session.capture) tracking.loadScores() }
    val ultimo = tracking.latestScore
    StmScreen(
        topBar = {
            TopBar("Score crediticio", onNav = nav::back) {
                IconBtn(StmIcons.add, { nav.go(38) }, contentDescription = "Añadir puntuación")
            }
        },
        snackbar = (action.error ?: tracking.error)?.let { e -> { Snackbar(e) } },
        overlay = borrando?.let { item ->
            {
                BottomSheet("¿Borrar este score?", "${item.score} de ${item.maxScore}", onDismiss = { borrando = null }) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn("Cancelar", { borrando = null }, kind = BtnKind.Text)
                        Btn("Borrar", {
                            action.run {
                                tracking.delete(item)
                                borrando = null
                            }
                        }, kind = BtnKind.Error)
                    }
                }
            }
        },
    ) {
        if (!session.capture && ultimo == null) {
            StmCard {
                Text("Apunta el score que te da tu banco o tu proveedor para ver cómo evoluciona.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn("Apuntar mi score", { nav.go(38) })
            }
            return@StmScreen
        }
        StmCard {
            val valor = if (session.capture) "742" else "${ultimo!!.score}"
            val titulo = if (session.capture) "Bueno" else ultimo!!.rating.title
            val tono = if (session.capture) c.success else when (ultimo!!.rating) {
                CreditScore.Rating.Excellent, CreditScore.Rating.Good -> c.success
                CreditScore.Rating.Fair -> c.onSurfaceVariant
                CreditScore.Rating.Poor -> c.error
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                // El tramo del diseño barre 129,6° de 180°.
                SemicircleGauge(listOf(Slice(if (session.capture) 0.72f else ultimo!!.fraction.toFloat(), tono)), width = 280.dp, thickness = 20.dp, gapDegrees = 0f)
                Column(Modifier.padding(top = 92.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(valor, style = StmType.displaySmall, color = c.onSurface)
                    Text(titulo, style = StmType.labelMedium, color = tono)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Lo apuntas tú a mano: en España no hay una fuente abierta para consultarlo.", Modifier.fillMaxWidth(),
                style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Historial")
            if (session.capture) {
                ListItem(
                    "742", "Octubre 2026 · informe del banco",
                    leading = { LeadIcon(StmIcons.creditScore, c.successContainer, c.onSuccessContainer) },
                    trailing = { Pill("+12", icon = null) },
                )
                Divider()
                ListItem(
                    "730", "Julio 2026",
                    leading = { LeadIcon(StmIcons.creditScore, c.surfaceContainerHighest, c.onSurfaceVariant) },
                    trailing = { Pill("−5", positive = false, icon = null) },
                )
                Divider()
                ListItem("735", "Abril 2026", leading = { LeadIcon(StmIcons.creditScore, c.surfaceContainerHighest, c.onSurfaceVariant) })
            } else {
                tracking.scores.forEachIndexed { i, item ->
                    if (i > 0) Divider()
                    val delta = tracking.scores.getOrNull(i + 1)?.takeIf { it.maxScore == item.maxScore }?.let { item.score - it.score }
                    ListItem(
                        "${item.score} de ${item.maxScore} · ${item.rating.title}",
                        listOfNotNull("${Fechas.mesTitulo(item.day)} ${item.day.year}", item.trimmedProvider, item.note).joinToString(" · "),
                        leading = {
                            if (i == 0) LeadIcon(StmIcons.creditScore, c.successContainer, c.onSuccessContainer)
                            else LeadIcon(StmIcons.creditScore, c.surfaceContainerHighest, c.onSurfaceVariant)
                        },
                        trailing = { if (delta != null && delta != 0) Pill(if (delta > 0) "+$delta" else "${Money.MINUS}${-delta}", positive = delta > 0, icon = null) },
                        onClick = { borrando = item },
                    )
                }
            }
        }
        if (!session.capture) {
            Spacer(Modifier.height(16.dp))
            Text("Sólo lo ves tú: no se comparte con el resto del hogar. Los tramos son orientativos. Toca uno para borrarlo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
    }
}

/** Apuntar un score. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla38(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val tracking = finance.tracking
    val ultimo = remember { tracking.latestScore }
    var score by remember { mutableStateOf("") }
    var escala by remember { mutableIntStateOf(ultimo?.maxScore ?: 850) }
    var proveedor by remember { mutableStateOf(ultimo?.trimmedProvider.orEmpty()) }
    var fecha by remember { mutableStateOf(finance.today()) }
    var nota by remember { mutableStateOf("") }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeEscala by remember { mutableStateOf(false) }
    val action = rememberAction()

    fun guardar() = action.run {
        val valor = score.trim().toIntOrNull() ?: throw AppError.InvalidInput("Escribe el score con números.")
        tracking.add(CreditScore("", valor, escala, proveedor, fecha.toString(), nota))
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Apuntar score", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeEscala) {
            { SelectorSheet("Escala", listOf(850, 900, 999, 1000, 100).map { e -> "Sobre $e" to { escala = e } }) { eligeEscala = false } }
        } else {
            null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Score", score, { score = it }, keyboard = KeyboardType.Number, autoFocus = true)
            FilledField("Escala", "Sobre $escala", trailing = StmIcons.arrowDropDown, onClick = { eligeEscala = true })
            FilledField("Proveedor (opcional)", proveedor, { proveedor = it })
            FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField("Nota (opcional)", nota, { nota = it })
            Text("Sólo lo ves tú. No se comparte con el hogar.", style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(finance.today())) fecha = it }) { eligeFecha = false }
}

// ───────────────────────── Piezas privadas ─────────────────────────

/** «Elemento de leyenda»: punto de 8 dp y texto. */
@Composable
private fun LegendItem(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(label, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

/** «Línea» de categoría: icono, nombre, detalle, porcentaje y progreso; en rojo si se pasa. */
@Composable
private fun CategoryLine(line: CategoryLine, onClick: () -> Unit) {
    val c = Stm.colors
    val icon = iconoCategoria(line.category)
    val limit = line.limit
    val detail = when {
        limit == null -> Money.format(line.spent, decimals = false)
        line.isOver -> "${Money.format(line.spent - limit, decimals = false)} por encima"
        else -> "${Money.format(line.spent, decimals = false, symbol = false)} de ${Money.format(limit, decimals = false)}"
    }
    Column(Modifier.fillMaxWidth().tap(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().height(40.dp), verticalAlignment = Alignment.CenterVertically) {
            if (line.isOver) LeadIcon(icon, c.errorContainer, c.onErrorContainer) else LeadIcon(icon)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(line.category.name, style = StmType.bodyLarge, color = c.onSurface)
                Text(detail, style = StmType.bodySmall, color = if (line.isOver) c.error else c.onSurfaceVariant)
            }
            if (limit != null && limit > 0) Text("${line.spent * 100 / limit}%", style = StmType.labelLarge, color = c.onSurface)
        }
        // La barra ocupa % × (348 − 14) dp en el diseño, no el ancho entero.
        line.fraction?.let { f ->
            Spacer(Modifier.height(8.dp))
            if (line.isOver) Progress(f * 334 / 348, color = c.error, track = c.errorContainer) else Progress(f * 334 / 348)
        }
    }
}

@Composable
private fun colorGrupo(group: BudgetGroup): Color = when (group) {
    BudgetGroup.Needs -> Stm.colors.primary
    BudgetGroup.Wants -> Stm.colors.tertiary
    BudgetGroup.Savings -> Stm.colors.secondary
}

@Composable
private fun LeadIconGrupo(icon: ImageVector, group: BudgetGroup) {
    val c = Stm.colors
    when (group) {
        BudgetGroup.Wants -> LeadIcon(icon, c.tertiaryContainer, c.onTertiaryContainer)
        else -> LeadIcon(icon)
    }
}

/** "Noviembre", y el año si no es el actual. */
private fun tituloMes(month: YearMonth, hoy: LocalDate): String =
    Fechas.mesTitulo(month.atDay(1)) + if (month.year != hoy.year) " de ${month.year}" else ""

@Composable
private fun BoxScope.SelectorMes(budgets: BudgetModel, hoy: LocalDate, cerrar: () -> Unit, elegir: (YearMonth) -> Unit) {
    SelectorSheet("Elegir mes", budgets.months().map { m -> tituloMes(m, hoy) to { cerrar(); elegir(m) } }, onDismiss = cerrar)
}

/** Importe editable de una fila: gris y alineado a la derecha, como el importe del diseño. */
@Composable
private fun CampoLimite(categoria: String, value: String, onChange: (String) -> Unit) {
    val c = Stm.colors
    val style = StmType.bodyMediumTight.copy(color = c.onSurfaceVariant, textAlign = TextAlign.End)
    Row(verticalAlignment = Alignment.CenterVertically) {
        BasicTextField(
            value, onChange, Modifier.width(88.dp).semantics { contentDescription = "Límite de $categoria" },
            textStyle = style, singleLine = true, cursorBrush = SolidColor(c.primary),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterEnd) {
                    if (value.isEmpty()) Text("Sin límite", style = style)
                    inner()
                }
            },
        )
        if (value.isNotEmpty()) Text(" €", style = style)
    }
}

/** Importe final de una fila, en gris. */
@Composable
private fun Amount(text: String) {
    Text(text, style = StmType.bodyMediumTight, color = Stm.colors.onSurfaceVariant, textAlign = TextAlign.End)
}

/** «Botón» tonal pequeño de 32 dp. */
@Composable
private fun SmallTonalBtn(label: String, onClick: () -> Unit) {
    val c = Stm.colors
    Box(
        Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(c.secondaryContainer).tap(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = StmType.labelLarge, color = c.onSecondaryContainer)
    }
}

/** Tarjeta de total: etiqueta y cifra serif en color. */
@Composable
private fun FlowStat(label: String, value: String, color: Color, modifier: Modifier, onClick: () -> Unit) {
    StmCard(modifier, onClick = onClick) {
        Text(label, style = StmType.labelMedium, color = Stm.colors.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(value, style = StmType.titleLarge, color = color)
    }
}

/**
 * «Botón segmentado» que se ajusta al texto: 12 dp a cada lado (16 en los extremos),
 * segmentos de 48 dp como mínimo y divisores de 1 dp sin ancho propio.
 */
@Composable
private fun SegmentedWrap(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Row(
                Modifier.fillMaxHeight().widthIn(min = 48.dp)
                    .let { if (on) it.background(c.secondaryContainer) else it }
                    .drawBehind { if (i > 0) drawRect(c.outline, size = Size(1.dp.toPx(), size.height)) }
                    .tap(role = Role.RadioButton) { onSelect(i) }
                    .padding(start = if (i == 0) 16.dp else 12.dp, end = if (i == options.lastIndex) 16.dp else 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (on) {
                    StmIcon(StmIcons.check, c.onSecondaryContainer, size = 18.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(label, style = StmType.labelLarge, color = if (on) c.onSecondaryContainer else c.onSurface, maxLines = 1)
            }
        }
    }
}

/** «Sankey»: ingresos → grupos 50/30/20 → categorías, con las medidas del diseño. */
@Composable
private fun Sankey(flow: CashFlow) {
    val c = Stm.colors
    val alto = maxOf(300, flow.nodes.count { it.column == 2 } * 34)
    val colores = flow.nodes.associate { node ->
        node.id to when (val r = node.role) {
            CashFlow.Role.Income -> c.success
            CashFlow.Role.FromBalance -> c.error
            CashFlow.Role.Uncategorized -> c.outline
            CashFlow.Role.Unspent -> c.outlineVariant
            is CashFlow.Role.Group -> colorGrupo(r.group)
        }
    }
    // El diseño deja 8 dp a cada lado: nodos en x = 8, 169 y 330 con 348 de ancho.
    BoxWithConstraints(Modifier.fillMaxWidth().height(alto.dp)) {
        val layout = remember(flow.nodes, maxWidth) { SankeyLayout(flow, maxWidth.value - 16.0, alto.toDouble(), gap = 10.0) }
        Canvas(Modifier.matchParentSize()) {
            val u = 1.dp.toPx()
            val inicio = 8 * u
            layout.bands.forEach { b ->
                val x0 = inicio + b.sourceX.toFloat() * u
                val x1 = inicio + b.targetX.toFloat() * u
                val mid = (x0 + x1) / 2
                val s0 = b.sourceTop.toFloat() * u
                val d0 = b.targetTop.toFloat() * u
                val t = b.thickness.toFloat() * u
                val path = Path().apply {
                    moveTo(x0, s0)
                    cubicTo(mid, s0, mid, d0, x1, d0)
                    lineTo(x1, d0 + t)
                    cubicTo(mid, d0 + t, mid, s0 + t, x0, s0 + t)
                    close()
                }
                drawPath(path, (colores[b.to] ?: c.outline).copy(alpha = 0.28f))
            }
            flow.nodes.forEach { n ->
                val r = layout.nodes[n.id] ?: return@forEach
                drawRoundRect(
                    colores[n.id] ?: c.outline, Offset(inicio + r.x.toFloat() * u, r.y.toFloat() * u),
                    Size(r.width.toFloat() * u, maxOf(r.height.toFloat() * u, u)), CornerRadius(2 * u),
                )
            }
        }
        // Si dos nodos quedan muy juntos, la etiqueta baja para no pisar la anterior.
        (0..2).forEach { columna ->
            var ultimo = -100f
            flow.nodes.filter { it.column == columna }.forEach { n ->
                val r = layout.nodes[n.id] ?: return@forEach
                val importe = Money.format(n.value.roundToLong(), decimals = false)
                val y = maxOf(if (columna == 0) r.y.toFloat() + 6 else r.midY.toFloat() - 8, ultimo + if (columna == 0) 32 else 16)
                ultimo = y
                when (columna) {
                    0 -> Column(
                        Modifier.offset((r.x + 22).dp, y.dp).clip(RoundedCornerShape(4.dp)).background(c.surfaceContainerLowest).padding(horizontal = 4.dp),
                    ) {
                        Text(n.title, style = StmType.labelSmall, color = c.onSurface, maxLines = 1)
                        Text(importe, style = StmType.labelSmall, color = c.onSurface, maxLines = 1)
                    }
                    1 -> SankeyLabel("${n.title} · $importe", r.x.toFloat() + 4, y, chip = true)
                    else -> SankeyLabel(n.title, r.x.toFloat() + 4, y)
                }
            }
        }
    }
}

/** Etiqueta alineada a la derecha que acaba en [endX] dp; con [chip], sobre fondo de tarjeta. */
@Composable
private fun SankeyLabel(text: String, endX: Float, y: Float, chip: Boolean = false) {
    val c = Stm.colors
    Box(Modifier.width(endX.dp).offset(y = y.dp), contentAlignment = Alignment.TopEnd) {
        if (chip) {
            Text(
                text, Modifier.clip(RoundedCornerShape(4.dp)).background(c.surfaceContainerLowest).padding(horizontal = 4.dp),
                style = StmType.labelSmall, color = c.onSurface, maxLines = 1,
            )
        } else {
            Text(text, style = StmType.labelSmall, color = c.onSurfaceVariant, maxLines = 1)
        }
    }
}

/**
 * Barras agrupadas de 148 dp: 3 guías, por mes una barra de ingresos (`tertiary`) y otra de gastos
 * (`primary`) de 14 dp separadas 4, con grupos cada 58 dp desde x = 13. Alturas en dp.
 */
@Composable
private fun GroupedBars(income: List<Float>, spending: List<Float>) {
    val c = Stm.colors
    Canvas(Modifier.fillMaxWidth().height(148.dp)) {
        val u = 1.dp.toPx()
        repeat(3) { i -> drawRect(c.outlineVariant, Offset(0f, size.height * i / 3f), Size(size.width, u)) }
        fun bar(x: Float, h: Float, color: Color) =
            drawRoundRect(color, Offset(x * u, size.height - h * u), Size(14 * u, h * u), CornerRadius(4 * u))
        income.indices.forEach { i ->
            bar(13f + 58f * i, income[i], c.tertiary)
            bar(31f + 58f * i, spending[i], c.primary)
        }
    }
}
