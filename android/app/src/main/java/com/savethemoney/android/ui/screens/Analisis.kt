package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
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
import com.savethemoney.android.ui.components.SemicircleGauge
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 14 Presupuesto: semicírculo 50/30/20 con leyenda y avance por categoría. */
@Composable
fun Pantalla14(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.edit, { nav.go(15) }, contentDescription = "Editar presupuesto")
                IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
            }
            LargeTitle("Presupuesto", "Noviembre · plantilla 50/30/20")
        },
        bottomBar = { NavBar(Tab.Presupuesto, nav::tab) },
    ) {
        StmCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(300.dp, 158.dp)) {
                    // Tramos medidos en el diseño: 0–60,2°, 62,2–99,8° y 101,8–122,4° (hueco de 2°).
                    SemicircleGauge(
                        listOf(Slice(62.2f / 180, c.primary), Slice(39.6f / 180, c.tertiary), Slice(22.6f / 180, c.secondary)),
                        width = 300.dp, thickness = 24.dp,
                    )
                    Column(Modifier.align(Alignment.BottomCenter), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("1.284 €", style = StmType.displaySmall, color = c.onSurface)
                        Text("de 2.400 € · quedan 25 días", style = StmType.bodySmall, color = c.onSurfaceVariant)
                    }
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    LegendItem(c.primary, "Necesidades 50 %")
                    LegendItem(c.tertiary, "Deseos 30 %")
                    LegendItem(c.secondary, "Ahorro 20 %")
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            // La barra ocupa % × (348 − 14) dp en el diseño, no el ancho entero.
            CategoryLine(StmIcons.shoppingCart, "Comida", "312 de 450 €", "69%", 0.69f * 334 / 348) { nav.go(5) }
            Spacer(Modifier.height(16.dp))
            CategoryLine(StmIcons.theaterComedy, "Ocio", "38 € por encima", "119%", 334.08f / 348, over = true) { nav.go(5) }
            Spacer(Modifier.height(16.dp))
            CategoryLine(StmIcons.directionsCar, "Transporte", "96 de 180 €", "53%", 0.53f * 334 / 348) { nav.go(5) }
        }
    }
}

/** 15 Editar presupuesto: modo, ingresos previstos, plantilla 50/30/20 e importes por categoría. */
@Composable
fun Pantalla15(nav: Nav) {
    val c = Stm.colors
    var mode by remember { mutableIntStateOf(0) }
    var income by remember { mutableStateOf("3.200,00") }
    StmScreen(
        topBar = {
            TopBar("Presupuesto de noviembre", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Por categorías", "Flexible"), mode, { mode = it })
        Spacer(Modifier.height(16.dp))
        FilledField("Ingresos previstos", income, { income = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        Spacer(Modifier.height(16.dp))
        StmCard(color = c.surfaceContainerHighest) {
            Row(Modifier.fillMaxWidth().height(32.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Reparto 50/30/20", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                SmallTonalBtn("Aplicar", nav::back)
            }
            Spacer(Modifier.height(8.dp))
            Text("1.600 € necesidades · 960 € deseos · 640 € ahorro", style = StmType.bodyMedium, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Necesidades")
            ListItem("Vivienda", leading = { LeadIcon(StmIcons.home) }, trailing = { Amount("900 €") })
            Divider()
            ListItem("Comida", leading = { LeadIcon(StmIcons.shoppingCart) }, trailing = { Amount("450 €") })
            ListHeader("Deseos")
            ListItem(
                "Ocio", leading = { LeadIcon(StmIcons.theaterComedy, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = { Amount("200 €") },
            )
        }
    }
}

/** 16 Flujo de caja: periodo, diagrama de flujo de ingresos a gastos y totales de entrada y salida. */
@Composable
fun Pantalla16(nav: Nav) {
    val c = Stm.colors
    var period by remember { mutableIntStateOf(0) }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) {
                IconBtn(StmIcons.calendarMonth, null, contentDescription = "Elegir mes")
            }
            LargeTitle("Flujo de caja", "Noviembre")
        },
        bottomBar = { NavBar(Tab.Flujo, nav::tab) },
    ) {
        SegmentedWrap(listOf("Mes", "Trimestre", "Año"), period) { period = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("De dónde viene y a dónde va", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Sankey()
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FlowStat("Entra", "+3.200 €", c.success, Modifier.weight(1f)) { nav.go(5) }
            FlowStat("Sale", "−2.560 €", c.onSurface, Modifier.weight(1f)) { nav.go(5) }
        }
    }
}

/** 17 Patrimonio neto: cifra, variación, evolución por periodo y lista de activos y deudas. */
@Composable
fun Pantalla17(nav: Nav) {
    val c = Stm.colors
    var range by remember { mutableIntStateOf(1) }
    StmScreen(
        topBar = {
            TopBar("Patrimonio neto", onNav = nav::back) {
                IconBtn(StmIcons.add, { nav.go(18) }, contentDescription = "Añadir")
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("48.230 €", style = StmType.displayMedium, color = c.onSurface)
        Spacer(Modifier.height(4.dp))
        Pill("+1.130 € en 6 meses")
        Spacer(Modifier.height(20.dp))
        SegmentedWrap(listOf("1M", "6M", "1A", "Todo"), range) { range = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            // Alturas del diseño en una caja de 160: 156, 114,5, 129,6, 72,9, 42,7 y 0.
            LineChart(listOf(156f, 114.5f, 129.6f, 72.9f, 42.7f, 0f).map { 1f - it / 160f }, plotHeight = 160.dp)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Activos")
            ListItem("Cuentas", leading = { LeadIcon(StmIcons.accountBalance) }, trailingText = "18.420 €", onClick = { nav.go(6) })
            Divider()
            ListItem(
                "Inversiones", leading = { LeadIcon(StmIcons.candlestickChart, c.tertiaryContainer, c.onTertiaryContainer) },
                trailingText = "31.950 €", onClick = { nav.go(25) },
            )
            ListHeader("Deudas")
            ListItem(
                "Tarjetas", leading = { LeadIcon(StmIcons.creditCard, c.errorContainer, c.onErrorContainer) },
                trailingText = "−2.140 €", onClick = { nav.go(10) },
            )
        }
    }
}

/** 18 Informes: filtros, barras de ingresos y gastos de los últimos 6 meses y resumen. */
@Composable
fun Pantalla18(nav: Nav) {
    val c = Stm.colors
    var filter by remember { mutableIntStateOf(0) }
    StmScreen(
        topBar = {
            TopBar("Informes", onNav = nav::back) {
                IconBtn(StmIcons.iosShare, { nav.go(19) }, contentDescription = "Compartir")
            }
        },
    ) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Ingresos y gastos", "Por categoría", "Por persona", "2026").forEachIndexed { i, label ->
                Chip(label, selected = i == filter, onClick = { filter = i })
            }
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Row(Modifier.fillMaxWidth()) {
                Text("Ingresos y gastos", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text("últimos 6 meses", Modifier.padding(top = 5.dp), style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            GroupedBars(
                income = listOf(131.76f, 131.76f, 135.88f, 131.76f, 133.82f, 131.76f),
                spending = listOf(111.18f, 125.59f, 140f, 107.06f, 115.29f, 52.71f),
            )
            Spacer(Modifier.height(4.dp))
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.5.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("jun", "jul", "ago", "sep", "oct", "nov").forEach {
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
                trailingText = "+452 €", onClick = { nav.go(19) },
            )
            Divider()
            ListItem(
                "Categoría que más sube", "Ocio, +18 % vs. octubre",
                leading = { LeadIcon(StmIcons.trendingUp, c.errorContainer, c.onErrorContainer) },
                trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(14) },
            )
        }
    }
}

/** 19 Score crediticio: indicador de 742 «Bueno» e historial de puntuaciones apuntadas a mano. */
@Composable
fun Pantalla19(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            TopBar("Score crediticio", onNav = nav::back) {
                IconBtn(StmIcons.add, null, contentDescription = "Añadir puntuación")
            }
        },
    ) {
        StmCard {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                // El tramo del diseño barre 129,6° de 180°.
                SemicircleGauge(listOf(Slice(0.72f, c.success)), width = 280.dp, thickness = 20.dp, gapDegrees = 0f)
                Column(Modifier.padding(top = 92.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("742", style = StmType.displaySmall, color = c.onSurface)
                    Text("Bueno", style = StmType.labelMedium, color = c.success)
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
        }
    }
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
private fun CategoryLine(
    icon: ImageVector,
    name: String,
    detail: String,
    percent: String,
    fraction: Float,
    over: Boolean = false,
    onClick: () -> Unit,
) {
    val c = Stm.colors
    Column(Modifier.fillMaxWidth().tap(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().height(40.dp), verticalAlignment = Alignment.CenterVertically) {
            if (over) LeadIcon(icon, c.errorContainer, c.onErrorContainer) else LeadIcon(icon)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = StmType.bodyLarge, color = c.onSurface)
                Text(detail, style = StmType.bodySmall, color = if (over) c.error else c.onSurfaceVariant)
            }
            Text(percent, style = StmType.labelLarge, color = c.onSurface)
        }
        Spacer(Modifier.height(8.dp))
        if (over) Progress(fraction, color = c.error, track = c.errorContainer) else Progress(fraction)
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

/** Banda del diagrama: de [x0] a [x0] + 151, de la franja [s0]–[s1] a [d0]–[d1] (dp). */
private class SankeyBand(val x0: Float, val s0: Float, val s1: Float, val d0: Float, val d1: Float, val color: Color)

/** Nodo del diagrama: barra de 10 dp con esquinas de 2 (dp). */
private class SankeyNode(val x: Float, val y: Float, val h: Float, val color: Color)

/** «Sankey» de 300 dp: ingresos → grupos 50/30/20 → categorías, con las medidas del diseño. */
@Composable
private fun Sankey() {
    val c = Stm.colors
    val bands = listOf(
        SankeyBand(18f, 16f, 150f, 2f, 136f, c.primary),
        SankeyBand(18f, 150f, 230.4f, 150f, 230.4f, c.tertiary),
        SankeyBand(18f, 230.4f, 284f, 244.4f, 298f, c.secondary),
        SankeyBand(179f, 2f, 77.375f, 2f, 69.5f, c.primary),
        SankeyBand(179f, 77.38f, 115.068f, 77.505f, 111.255f, c.primary),
        SankeyBand(179f, 115.06f, 135.998f, 119.248f, 137.998f, c.primary),
        SankeyBand(179f, 150f, 185.175f, 146f, 177.5f, c.tertiary),
        SankeyBand(179f, 185.18f, 213.655f, 185.505f, 211.005f, c.tertiary),
        SankeyBand(179f, 213.65f, 230.4f, 219f, 234f, c.tertiary),
        SankeyBand(179f, 244.4f, 277.9f, 242f, 272f, c.secondary),
        SankeyBand(179f, 277.9f, 298f, 280f, 298f, c.secondary),
    )
    val nodes = listOf(
        SankeyNode(169f, 2f, 134f, c.primary), SankeyNode(169f, 150f, 80.4f, c.tertiary), SankeyNode(169f, 244.4f, 53.6f, c.secondary),
        SankeyNode(330f, 2f, 67.5f, c.primary), SankeyNode(330f, 77.5f, 33.75f, c.primary), SankeyNode(330f, 119.25f, 18.75f, c.primary),
        SankeyNode(330f, 146f, 31.5f, c.tertiary), SankeyNode(330f, 185.5f, 25.5f, c.tertiary), SankeyNode(330f, 219f, 15f, c.tertiary),
        SankeyNode(330f, 242f, 30f, c.secondary), SankeyNode(330f, 280f, 18f, c.secondary),
    )
    Box(Modifier.fillMaxWidth().height(300.dp)) {
        Canvas(Modifier.matchParentSize()) {
            val u = 1.dp.toPx()
            fun node(n: SankeyNode) = drawRoundRect(n.color, Offset(n.x * u, n.y * u), Size(10 * u, n.h * u), CornerRadius(2 * u))
            node(SankeyNode(8f, 16f, 268f, c.success))
            bands.forEach { b ->
                val x0 = b.x0 * u
                val x1 = (b.x0 + 151f) * u
                val mid = (x0 + x1) / 2
                val path = Path().apply {
                    moveTo(x0, b.s0 * u)
                    cubicTo(mid, b.s0 * u, mid, b.d0 * u, x1, b.d0 * u)
                    lineTo(x1, b.d1 * u)
                    cubicTo(mid, b.d1 * u, mid, b.s1 * u, x0, b.s1 * u)
                    close()
                }
                drawPath(path, b.color.copy(alpha = 0.28f))
            }
            nodes.forEach { node(it) }
        }
        Column(Modifier.offset(22.dp, 22.dp).clip(RoundedCornerShape(4.dp)).background(c.surfaceContainerLowest).padding(horizontal = 4.dp)) {
            Text("Ingresos", style = StmType.labelSmall, color = c.onSurface)
            Text("3.200 €", style = StmType.labelSmall, color = c.onSurface)
        }
        // Las etiquetas de grupo acaban en x = 165; las de categoría, en x = 326.
        SankeyLabel("Necesidades · 1.600 €", 165f, 61f, chip = true)
        SankeyLabel("Deseos · 960 €", 165f, 182.19f, chip = true)
        SankeyLabel("Ahorro · 640 €", 165f, 263.19f, chip = true)
        SankeyLabel("Vivienda", 326f, 27.25f)
        SankeyLabel("Comida", 326f, 85.88f)
        SankeyLabel("Transporte", 326f, 120.12f)
        SankeyLabel("Ocio", 326f, 153.25f)
        SankeyLabel("Compras", 326f, 189.75f)
        SankeyLabel("Suscripciones", 326f, 218f)
        SankeyLabel("Fondo de emergencia", 326f, 248.5f)
        SankeyLabel("Inversión", 326f, 280.5f)
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
