package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.BudgetPeriod
import com.savethemoney.android.data.CashFlow
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.SankeyLayout
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlin.math.roundToLong

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
    val rango = budgets.range(months)
    val titulo = if (months == 1) budgets.period.title else BudgetPeriod(rango.start, rango.endInclusive).title
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.calendarMonth, { eligiendo = true }, contentDescription = "Elegir periodo")
            }
            LargeTitle("Flujo de caja", titulo)
        },
        bottomBar = { NavBar(Tab.Flujo, nav::tab) },
        snackbar = budgets.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            { SelectorPeriodos(budgets, { eligiendo = false }) }
        } else null,
    ) {
        SelectorPeriodo(budgets)
        Spacer(Modifier.height(16.dp))
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
            FlowStat("Entra", Money.format(report.income, decimals = false, signed = true), c.success, Modifier.weight(1f)) { nav.go(Route.Movimientos) }
            FlowStat("Sale", Money.format(-report.totalSpent, decimals = false), c.onSurface, Modifier.weight(1f)) { nav.go(Route.Movimientos) }
        }
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
