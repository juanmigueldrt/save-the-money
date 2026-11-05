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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
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
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlin.math.roundToInt

/** 20 Pagos fijos: total del mes y cargos recurrentes agrupados en próximos e ingresos. */
@Composable
fun Pantalla20(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            // En el diseño la fila mide 60 (no 64) y el título va justo debajo, sin subtítulo.
            Box(Modifier.fillMaxWidth().height(60.dp)) {
                TopBar(null, onNav = nav::back) { IconBtn(StmIcons.search, null, contentDescription = "Buscar") }
            }
            Text("Pagos fijos", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        fab = { Fab("Nuevo pago") { nav.go(21) } },
    ) {
        StmCard {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f).padding(top = 4.dp)) {
                    Text("Este mes", style = StmType.labelMedium, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    Text("1.142,98 €", style = StmType.titleLarge, color = c.onSurface)
                }
                Tag("9 pagos")
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Próximos")
            ListItem(
                "Alquiler", "1 dic · Esencial · compartido", trailingText = "850,00 €",
                leading = { LeadIcon(StmIcons.home) }, onClick = { nav.go(21) },
            )
            Divider()
            ListItem(
                "Streaming", "8 dic · oferta 3 meses",
                leading = { LeadIcon(StmIcons.liveTv, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("5,99 €", style = StmType.labelLarge, color = c.onSurface)
                        Text("luego 12,99 €", style = StmType.bodySmall, color = c.onSurfaceVariant)
                    }
                },
                onClick = { nav.go(21) },
            )
            Divider()
            ListItem(
                "Gimnasio", "10 dic · Suscripción", trailingText = "39,90 €",
                leading = { LeadIcon(StmIcons.fitnessCenter, c.tertiaryContainer, c.onTertiaryContainer) },
            )
            Divider()
            ListItem("Agua", "15 dic · Esencial · cada 2 meses", trailingText = "42,10 €", leading = { LeadIcon(StmIcons.waterDrop) })
            ListHeader("Ingresos")
            ListItem(
                "Nómina", "1 dic", trailingText = "+2.150,00 €",
                leading = { LeadIcon(StmIcons.work, c.successContainer, c.onSuccessContainer) },
            )
        }
    }
}

/** 21 Nuevo pago fijo: tipo, importe, periodicidad, precio de oferta con contador de cargos y avisos. */
@Composable
fun Pantalla21(nav: Nav) {
    var kind by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("Streaming") }
    var amount by remember { mutableStateOf("12,99") }
    var offer by remember { mutableStateOf(true) }
    var offerPrice by remember { mutableStateOf("5,99") }
    var charges by remember { mutableIntStateOf(3) }
    var shared by remember { mutableStateOf(false) }
    var remind by remember { mutableStateOf(true) }
    StmScreen(
        topBar = {
            TopBar("Nuevo pago fijo", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("Suscripción", "Esencial", "Ingreso"), kind, { kind = it })
            FilledField("Nombre", name, { name = it })
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField("Importe", amount, { amount = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal)
                FilledField("Cada", "1 mes", modifier = Modifier.weight(1f), trailing = StmIcons.arrowDropDown)
            }
            FilledField("Próximo cargo", "8 dic 2026", trailing = StmIcons.calendarToday)
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
                        suffix = "€", keyboard = KeyboardType.Decimal, autoFocus = true,
                    )
                    Stepper(if (charges == 1) "1 cargo" else "$charges cargos", { charges = (charges - 1).coerceAtLeast(1) }, { charges++ })
                }
            }
            ListCard {
                ListItem("Compartir con el hogar", trailing = { StmSwitch(shared) { shared = it } })
                Divider(inset = 16.dp)
                ListItem("Avisarme 2 días antes", trailing = { StmSwitch(remind) { remind = it } })
            }
        }
    }
}

/** 22 Metas: filtros y tarjetas de cada meta con su progreso. */
@Composable
fun Pantalla22(nav: Nav) {
    val c = Stm.colors
    var filter by remember { mutableIntStateOf(0) }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null) { IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones") }
            LargeTitle("Metas", "Fija metas (y cúmplelas)")
        },
        bottomBar = { NavBar(Tab.Metas, nav::tab) },
        fab = { Fab("Nueva meta") { nav.go(24) } },
    ) {
        ChipRow {
            listOf("Ahorro", "Deudas", "Completadas").forEachIndexed { i, label ->
                Chip(label, selected = i == filter, onClick = { filter = i })
            }
        }
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            GoalCard(StmIcons.savings, "Fondo de emergencia", "A este ritmo, en marzo", 0.6f, "3.600 €", "de 6.000 €") { nav.go(23) }
            GoalCard(StmIcons.flight, "Viaje a Lisboa", "Compartida · junio 2027", 0.65f, "780 €", "de 1.200 €") { nav.go(23) }
            GoalCard(
                StmIcons.directionsCar, "Préstamo del coche", "Deuda · 18 cuotas", 0.46f, "4.100 €", "de 9.000 €",
                c.errorContainer, c.onErrorContainer,
            ) { nav.go(23) }
        }
    }
}

/** 23 Detalle de meta: lo ahorrado, la proyección y las aportaciones. */
@Composable
fun Pantalla23(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            TopBar("Fondo de emergencia", onNav = nav::back) {
                IconBtn(StmIcons.edit, { nav.go(24) }, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
            }
        },
        fab = { Fab("Aportar", onClick = null) },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Ahorrado", style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text("3.600 €", style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.dp))
        Text("de 6.000 € · 60 %", style = StmType.bodyMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        GoalProgress(0.6f)
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Proyección", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            // Puntos del «Área» del diseño (y sobre 120) pasados a 0–1.
            LineChart(
                listOf(116f, 101.5f, 89.4f, 72.5f, 58f, 43.5f, 29f, 14.5f, 0f).map { 1f - it / 120f },
                plotHeight = 120.dp, color = c.tertiary,
            )
            Spacer(Modifier.height(8.dp))
            Text("Con 300 €/mes llegas en marzo de 2027. Con 400 €/mes, en enero.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Aportaciones")
            ListItem("+300 €", "1 nov · Ana", leading = { Avatar("A") }, trailing = { Note("Mensual") })
            Divider()
            ListItem("+150 €", "15 oct · Leo", leading = { Avatar("L") }, trailing = { Note("Extra") })
        }
    }
}

/** 24 Nueva meta: tipo, nombre, importe (con error), fecha, aporte necesario y si se comparte. */
@Composable
fun Pantalla24(nav: Nav) {
    val c = Stm.colors
    var kind by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("Viaje a Lisboa") }
    var target by remember { mutableStateOf("abc") }
    var shared by remember { mutableStateOf(true) }
    val invalid = target.replace(".", "").replace(',', '.').toDoubleOrNull() == null
    StmScreen(
        topBar = {
            TopBar("Nueva meta", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("Ahorro", "Pagar deuda"), kind, { kind = it })
            FilledField("Nombre de la meta", name, { name = it }, supporting = "Lo verás en tu lista de metas")
            FilledField(
                "Importe objetivo", target, { target = it }, keyboard = KeyboardType.Decimal,
                trailing = if (invalid) StmIcons.error else null,
                supporting = if (invalid) "Escribe un importe, por ejemplo 150" else null,
                error = invalid,
            )
            FilledField("Fecha límite", "Junio 2027", trailing = StmIcons.calendarToday)
            StmCard(color = c.surfaceContainerHighest) {
                Text("Aporte mensual necesario", style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Text("60 €/mes", style = StmType.titleLarge, color = c.onSurface)
                Spacer(Modifier.height(4.dp))
                Text("durante 20 meses", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            ListCard {
                ListItem("Compartir con el hogar", "Leo podrá ver y aportar", trailing = { StmSwitch(shared) { shared = it } })
            }
        }
    }
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
private fun Stepper(text: String, onMinus: () -> Unit, onPlus: () -> Unit) {
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
    Text(text, style = StmType.bodyMediumTight, color = Stm.colors.onSurfaceVariant)
}
