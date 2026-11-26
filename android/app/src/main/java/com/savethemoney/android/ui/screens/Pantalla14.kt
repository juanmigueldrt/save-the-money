package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.BudgetTemplate
import com.savethemoney.android.data.CategoryLine
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SemicircleGauge
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.temporal.ChronoUnit

/** 14 Presupuesto: semicírculo 50/30/20 con leyenda y avance por categoría. */
@Composable
fun Pantalla14(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val scope = rememberCoroutineScope()
    var eligiendo by remember { mutableStateOf(false) }
    var eligiendoPeriodo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { budgets.load() }
    val report = budgets.report(finance.categories)
    val template = (budgets.budget ?: budgets.proposal)?.template ?: BudgetTemplate.FiftyThirtyTwenty
    val hoy = finance.today()
    // Cada grupo ocupa lo gastado sobre lo repartido; si no hay base, se reparte el arco entre lo gastado.
    val total = maxOf(report.base, report.groups.sumOf { it.spent }).coerceAtLeast(1).toFloat()
    val restantes = if (budgets.isCurrentPeriod) ChronoUnit.DAYS.between(hoy, budgets.period.end) else null
    val lineas = report.lines.filter { it.category.budgetGroup != null }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.edit, { nav.go(Route.EditarPresupuesto) }, contentDescription = "Editar presupuesto")
                IconBtn(StmIcons.moreVert, { eligiendo = true }, contentDescription = "Más opciones")
            }
            LargeTitle("Presupuesto", "${budgets.period.title} · plantilla ${template.needs}/${template.wants}/${template.savings}")
        },
        bottomBar = { NavBar(Tab.Presupuesto, nav::tab) },
        snackbar = budgets.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            {
                SelectorSheet(
                    "Presupuesto",
                    listOf(
                        "Día de cobro" to { nav.go(Route.DiaDeCobro) },
                        "Nuevo presupuesto extra" to { nav.go(Route.FormExtra()) },
                        "Elegir periodo" to { eligiendoPeriodo = true },
                    ),
                    { eligiendo = false },
                )
            }
        } else if (eligiendoPeriodo) {
            { SelectorPeriodos(budgets, { eligiendoPeriodo = false }) }
        } else null,
    ) {
        SelectorPeriodo(budgets)
        Spacer(Modifier.height(16.dp))
        if (budgets.isCurrentPeriod) {
            GastarHoyCard(budgets, finance)
            Spacer(Modifier.height(16.dp))
        }
        if (budgets.budget == null) {
            StmCard {
                Text(
                    budgets.proposal?.let { "Aún no hay presupuesto para este periodo. Puedes partir del de ${it.period.title.lowercase()}." }
                        ?: "Aún no hay presupuesto para este periodo. Mientras tanto, se reparten los ingresos reales con 50/30/20.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                Btn("Crear presupuesto", { nav.go(Route.EditarPresupuesto) })
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
        if (budgets.budget != null) {
            val insights = budgets.insights(finance.categories)
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListItem(
                    if (insights.unbudgeted < 0) "Límites por encima de lo previsto" else "Queda por presupuestar",
                    trailingText = Money.format(insights.unbudgeted),
                )
                if (budgets.isCurrentPeriod) {
                    Divider(inset = 16.dp)
                    ListItem("Al ritmo de hoy gastarás", trailingText = Money.format(insights.projectedSpent))
                }
            }
        }
        if (lineas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            StmCard {
                lineas.forEachIndexed { i, line ->
                    if (i > 0) Spacer(Modifier.height(16.dp))
                    CategoryLine(line) { nav.go(Route.Movimientos) }
                }
            }
        }
        if (report.uncategorized > 0) {
            Spacer(Modifier.height(16.dp))
            StmCard(onClick = { nav.go(Route.Movimientos) }) {
                Row(Modifier.fillMaxWidth()) {
                    Text("Gastos sin categoría", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Text(Money.format(report.uncategorized), style = StmType.labelLarge, color = c.onSurface)
                }
                Spacer(Modifier.height(4.dp))
                Text("Ponles categoría en Movimientos para que cuenten en su grupo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(16.dp))
        ExtrasSection(budgets, finance, nav)
    }
}

/** «Línea» de categoría: icono, nombre, detalle, porcentaje y progreso; en rojo si se pasa. */
@Composable
private fun CategoryLine(line: CategoryLine, onClick: () -> Unit) {
    val c = Stm.colors
    val icon = iconoCategoria(line.category)
    val limit = line.available
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
        if (line.carried != 0L) {
            Spacer(Modifier.height(4.dp))
            Text(
                if (line.carried < 0) "Incluye ${Money.format(-line.carried)} de menos del periodo anterior"
                else "Incluye ${Money.format(line.carried)} que sobró del periodo anterior",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
}
