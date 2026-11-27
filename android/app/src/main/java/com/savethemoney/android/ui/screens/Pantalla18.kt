package com.savethemoney.android.ui.screens

import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.GroupedSpending
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Payee
import com.savethemoney.android.data.ReportKind
import com.savethemoney.android.data.ReportPeriod
import com.savethemoney.android.data.SpendingReport
import com.savethemoney.android.data.biggestRise
import com.savethemoney.android.data.monthContaining
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

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
    LaunchedEffect(finance.recent) { tracking.loadReports() }
    val hoy = finance.today()
    val inicioMes = finance.household.monthStartDay
    val seis = ReportPeriod.Last6Months.range(hoy, inicioMes)
    val movimientos = tracking.reportMovements
    val categorias = finance.categories
    // Cada informe recorre todos los movimientos: se recuerdan y sólo se rehacen si cambian sus datos o los filtros.
    val ingresos = remember(movimientos, categorias, seis, inicioMes) { SpendingReport(movimientos, categorias, seis, ReportKind.Income, monthStartDay = inicioMes) }
    val gastos = remember(movimientos, categorias, seis, inicioMes) { SpendingReport(movimientos, categorias, seis, ReportKind.Expense, monthStartDay = inicioMes) }
    val tope = (ingresos.byMonth.map { it.amount } + gastos.byMonth.map { it.amount }).max().coerceAtLeast(1)
    val informe = remember(movimientos, categorias, period, hoy, kind, categoria, inicioMes) {
        SpendingReport(movimientos, categorias, period.range(hoy, inicioMes), kind, setOfNotNull(categoria), inicioMes)
    }
    val anterior = remember(movimientos, categorias, period, hoy, kind, categoria, inicioMes) {
        SpendingReport(movimientos, categorias, period.previousRange(hoy, inicioMes), kind, setOfNotNull(categoria), inicioMes)
    }
    val sube = remember(movimientos, categorias, hoy, inicioMes) { biggestRise(movimientos, categorias, monthContaining(hoy, inicioMes), inicioMes) }
    val agrupacion = when (filter) {
        2 -> GroupedSpending.Grouping.Tag
        3 -> GroupedSpending.Grouping.Payee
        else -> null
    }
    val agrupado = remember(agrupacion, movimientos, categorias, period, hoy) {
        agrupacion?.let { GroupedSpending.report(it, movimientos, categorias, period.range(hoy)) }.orEmpty()
    }
    val context = LocalContext.current
    val compartirInforme = {
        val texto = if (agrupacion != null) {
            "${agrupacion.title} · ${period.title.lowercase()}\n" + agrupado.joinToString("\n") {
                (if (agrupacion == GroupedSpending.Grouping.Tag) "#" else "") + "${it.title}: ${Money.format(it.spent)}"
            }
        } else if (filter == 1) {
            textoInforme(informe, anterior, period, finance.category(categoria)?.name)
        } else {
            textoIngresosGastos(ingresos, gastos)
        }
        val envio = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT, "Informe de Save the Money").putExtra(Intent.EXTRA_TEXT, texto)
        context.startActivity(Intent.createChooser(envio, "Compartir informe"))
    }
    StmScreen(
        topBar = {
            TopBar("Informes", onNav = nav::back) {
                IconBtn(StmIcons.iosShare, compartirInforme, contentDescription = "Compartir")
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
            Chip("Ingresos y gastos", selected = filter == 0, onClick = { filter = 0 })
            Chip("Por categoría", selected = filter == 1, onClick = { filter = 1 })
            Chip("Por etiqueta", selected = filter == 2, onClick = { filter = 2 })
            Chip("Por beneficiario", selected = filter == 3, onClick = { filter = 3 })
            if (filter >= 1) Chip(period.title, onClick = { selector = "periodo" })
            if (filter == 1) Chip(finance.category(categoria)?.name ?: "Todas", onClick = { selector = "categoria" })
        }
        Spacer(Modifier.height(16.dp))
        if (agrupacion != null) {
            val esEtiqueta = agrupacion == GroupedSpending.Grouping.Tag
            val top = agrupado.maxOfOrNull { it.spent }?.coerceAtLeast(1) ?: 1
            if (agrupado.isEmpty()) {
                Text(
                    if (esEtiqueta) "No hay movimientos con etiquetas en este periodo. Añádelas al editar un movimiento."
                    else "No hay movimientos con beneficiario en este periodo. Añádelo al editar un movimiento.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
            } else {
                ListCard {
                    agrupado.forEachIndexed { i, fila ->
                        if (i > 0) Divider()
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                LeadIcon(if (esEtiqueta) StmIcons.flag else StmIcons.person)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(if (esEtiqueta) "#${fila.title}" else fila.title, style = StmType.bodyLarge, color = c.onSurface)
                                    Text(
                                        if (fila.income > 0) "${fila.count} movimientos · ingresos ${Money.format(fila.income)}" else "${fila.count} movimientos",
                                        style = StmType.bodySmall, color = c.onSurfaceVariant,
                                    )
                                }
                                Text(Money.format(fila.spent), style = StmType.labelLarge, color = c.onSurface)
                            }
                            Spacer(Modifier.height(8.dp))
                            Progress(fila.spent.toFloat() / top)
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Un movimiento con varias etiquetas cuenta en cada una. No se incluyen transferencias ni excluidos.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            return@StmScreen
        }
        if (filter == 1) {
            Segmented(ReportKind.entries.map { it.title }, kind.ordinal, {
                kind = ReportKind.entries[it]
                categoria = null
            })
            Spacer(Modifier.height(16.dp))
            StmCard {
                Text("${kind.title} · ${period.title.lowercase()}", style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(informe.total), style = StmType.displaySmall, color = c.onSurface)
                comparacion(informe, anterior, period)?.let { (texto, bueno) ->
                    Spacer(Modifier.height(4.dp))
                    Text(texto, style = StmType.labelLarge, color = when (bueno) { null -> c.onSurfaceVariant; true -> c.success; false -> c.error })
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    (if (informe.byMonth.size > 1) "Media de ${Money.format(informe.averagePerMonth)} al mes · " else "") + "${Money.format(informe.averagePerDay)} al día",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
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
            GroupedBars(ingresos.byMonth.map { maxOf(it.amount, 0L) * 140f / tope }, gastos.byMonth.map { maxOf(it.amount, 0L) * 140f / tope })
            Spacer(Modifier.height(4.dp))
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.5.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                gastos.byMonth.map { Fechas.mes(it.month.atDay(1)).take(3) }.forEach {
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
                trailingText = euros(ingresos.averagePerMonth - gastos.averagePerMonth, signed = true),
            )
            val texto = when {
                sube == null -> null
                else -> sube.title + (sube.percent?.let { ", +$it %" } ?: "") + " vs. ${Fechas.mes(sube.previous.atDay(1))}"
            }
            if (texto != null) {
                Divider()
                ListItem(
                    "Categoría que más sube", texto,
                    leading = { LeadIcon(StmIcons.trendingUp, c.errorContainer, c.onErrorContainer) },
                    trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(Route.Presupuesto) },
                )
            }
        }
    }
}

/**
 * "+12 % · +40,00 € frente al mes pasado a estas alturas". En gastos, subir es malo; en ingresos, bueno.
 * Devuelve el texto y si es buena noticia (nulo si no cambia), o nulo si no hay nada que comparar.
 */
private fun comparacion(informe: SpendingReport, anterior: SpendingReport, period: ReportPeriod): Pair<String, Boolean?>? {
    if (informe.total <= 0 && anterior.total <= 0) return null
    val (diferencia, porcentaje) = informe.change(anterior)
    if (diferencia == 0L) return "Igual que ${period.previousTitle}" to null
    val sube = diferencia > 0
    val pct = porcentaje?.let { (if (it > 0) "+" else "") + "$it % · " } ?: ""
    return "$pct${Money.format(diferencia, signed = true, options = Money.display.copy(plusSign = true))} frente a ${period.previousTitle}" to
        (if (informe.kind == ReportKind.Expense) !sube else sube)
}

/** El informe por categorías en texto, siempre con importes completos (no respeta el modo incógnito). */
private fun textoInforme(informe: SpendingReport, anterior: SpendingReport, period: ReportPeriod, categoria: String?): String {
    val e = { minor: Long -> Money.format(minor, options = Money.Display.Standard) }
    val (diferencia, porcentaje) = informe.change(anterior)
    return buildString {
        appendLine("${informe.kind.title} · ${period.title}" + (categoria?.let { " · $it" } ?: ""))
        appendLine("Del ${Fechas.numerica(informe.range.start)} al ${Fechas.numerica(informe.range.endInclusive)}")
        appendLine("Total: ${e(informe.total)}")
        appendLine("Media por día: ${e(informe.averagePerDay)}")
        appendLine("Frente a ${period.previousTitle}: ${Money.format(diferencia, signed = true, options = Money.Display.Standard)}" + (porcentaje?.let { " ($it %)" } ?: ""))
        if (informe.byCategory.isNotEmpty()) appendLine()
        informe.byCategory.forEach { appendLine("${it.title}: ${e(it.amount)} (${Math.round(it.share * 100)} %, ${it.count} movimientos)") }
    }.trimEnd()
}

/** Ingresos y gastos de los últimos 6 meses en texto, con importes completos. */
private fun textoIngresosGastos(ingresos: SpendingReport, gastos: SpendingReport): String {
    val e = { minor: Long -> Money.format(minor, options = Money.Display.Standard) }
    return buildString {
        appendLine("Ingresos y gastos · últimos 6 meses")
        ingresos.byMonth.zip(gastos.byMonth).forEach { (i, g) ->
            appendLine("${Fechas.mesTitulo(i.month.atDay(1))} ${i.month.year}: ingresos ${e(i.amount)}, gastos ${e(g.amount)}")
        }
        appendLine("Ahorro medio al mes: ${Money.format(ingresos.averagePerMonth - gastos.averagePerMonth, signed = true, options = Money.Display.Standard)}")
    }.trimEnd()
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
