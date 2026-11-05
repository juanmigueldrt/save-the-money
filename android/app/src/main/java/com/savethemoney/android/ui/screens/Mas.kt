package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Donut
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 25 Inversiones: cartera con evolución, reparto y posiciones. */
@Composable
fun Pantalla25(nav: Nav) {
    val c = Stm.colors
    var range by remember { mutableIntStateOf(2) }
    StmScreen(
        topBar = {
            MediumTopBar("Cartera", onBack = nav::back) {
                IconBtn(StmIcons.eventRepeat, { nav.go(27) }, contentDescription = "Inversiones recurrentes")
                IconBtn(StmIcons.add, { nav.go(26) }, contentDescription = "Comprar")
            }
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
    ) {
        Spacer(Modifier.height(7.5.dp))
        Text("31.950 €", style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Pill("+3.420 € (+12,0 %)")
            Spacer(Modifier.width(8.dp))
            Text("desde el inicio", style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(20.dp))
        HugSegmented(listOf("1S", "1M", "1A", "Todo"), range) { range = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            LineChart(listOf(116f, 100.4f, 108.2f, 73.1f, 45.8f, 55.6f, 22.4f, 0f).map { 1f - it / 120f })
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Donut(listOf(Slice(0.62f, c.primary), Slice(0.24f, c.tertiary), Slice(0.14f, c.secondaryContainer)), 112.dp, 16.dp)
                Spacer(Modifier.width(16.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Legend(c.primary, "Fondos indexados 62 %")
                    Legend(c.tertiary, "Acciones 24 %")
                    Legend(c.secondaryContainer, "Efectivo 14 %")
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Fondo indexado mundial", "112,4 participaciones",
                leading = { LeadIcon(StmIcons.public, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("19.810 €", style = StmType.labelLarge, color = c.onSurface)
                        Text("+14,2 %", style = StmType.bodySmall, color = c.onSurfaceVariant)
                    }
                },
                onClick = { nav.go(26) },
            )
        }
    }
}

/** 26 Comprar activo: precio, evolución, posición y compra por importe o participaciones. */
@Composable
fun Pantalla26(nav: Nav) {
    val c = Stm.colors
    var mode by remember { mutableIntStateOf(0) }
    var amount by remember { mutableStateOf("300,00") }
    var fee by remember { mutableStateOf("0,10") }
    StmScreen(
        topBar = {
            TopBar("Fondo indexado mundial", onNav = nav::back) {
                IconBtn(StmIcons.edit, null, contentDescription = "Editar")
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Precio · apuntado hoy", style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.5.dp))
        Text("176,25 €", style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Pill("+0,8 % hoy")
        Spacer(Modifier.height(20.dp))
        StmCard {
            LineChart(listOf(96f, 80.2f, 85.5f, 53.9f, 32.9f, 43.4f, 17.1f, 0f).map { 1f - it / 100f }, plotHeight = 100.dp)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Tu posición", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            DataRow("Participaciones", "112,40")
            Spacer(Modifier.height(8.dp))
            DataRow("Valor", "19.810 €")
            Spacer(Modifier.height(8.dp))
            DataRow("Rentabilidad", "+2.462 € (+14,2 %)", c.success)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Comprar", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Segmented(listOf("Por importe", "Por participaciones"), mode, { mode = it })
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SuffixField("Importe", amount, { amount = it }, "€", Modifier.weight(1f))
                SuffixField("Comisión", fee, { fee = it }, "%", Modifier.weight(1f))
            }
            Spacer(Modifier.height(12.dp))
            Text("≈ 1,70 participaciones · comisión 0,30 €", style = StmType.bodySmall, color = c.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Btn("Comprar", nav::back, Modifier.fillMaxWidth())
        }
    }
}

/** 27 Inversiones recurrentes: calendario del mes con los días de aportación y planes activos. */
@Composable
fun Pantalla27(nav: Nav) {
    val c = Stm.colors
    var world by remember { mutableStateOf(true) }
    var bonds by remember { mutableStateOf(false) }
    StmScreen(
        topBar = {
            TopBar("Inversiones recurrentes", onNav = nav::back) {
                IconBtn(StmIcons.add, null, contentDescription = "Añadir")
            }
        },
    ) {
        StmCard {
            Text("Noviembre", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                    Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) {
                        Text(it, style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            // Noviembre de 2026 empieza en domingo en el calendario real; el diseño lo pinta en sábado.
            val days = List(5) { null } + (1..30).toList()
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                days.chunked(7).forEach { week ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        week.forEach { day ->
                            val (bg, fg) = when (day) {
                                5 -> c.primary to c.onPrimary
                                1, 20 -> c.secondaryContainer to c.onSecondaryContainer
                                else -> Color.Transparent to c.onSurface
                            }
                            Box(Modifier.size(40.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
                                if (day != null) Text("$day", style = StmType.bodyMedium, color = fg)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Fondo indexado mundial", "300 € el día 1 de cada mes",
                leading = { LeadIcon(StmIcons.public, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = { StmSwitch(world) { world = it } },
                onClick = { nav.go(26) },
            )
            Divider()
            ListItem(
                "Fondo de bonos", "100 € el día 20 · en pausa",
                leading = { LeadIcon(StmIcons.accountBalance, c.surfaceContainerHighest, c.onSurfaceVariant) },
                trailing = { StmSwitch(bonds) { bonds = it } },
            )
        }
    }
}

/** 30 Más opciones: menú de secciones, datos y preferencias. */
@Composable
fun Pantalla30(nav: Nav) {
    var dark by remember { mutableStateOf(false) }
    var alerts by remember { mutableStateOf(true) }
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
    ) {
        ListCard {
            MenuRow(StmIcons.creditCard, "Tarjetas") { nav.go(10) }
            MenuRow(StmIcons.eventRepeat, "Pagos fijos", count = "9") { nav.go(20) }
            MenuRow(StmIcons.monitoring, "Patrimonio, informes y score") { nav.go(17) }
            MenuRow(StmIcons.candlestickChart, "Inversiones") { nav.go(25) }
            MenuRow(StmIcons.group, "Hogar") { nav.go(28) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Datos")
            MenuRow(StmIcons.uploadFile, "Importar CSV") { nav.go(32) }
            MenuRow(StmIcons.pictureAsPdf, "PDF de pagos del mes", onClick = null)
            MenuRow(StmIcons.tableView, "CSV para Excel", onClick = null)
            MenuRow(StmIcons.category, "Categorías", count = "20") { nav.go(31) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Preferencias")
            ListItem(
                "Tema oscuro", "Igual que el sistema",
                leading = { StmIcon(StmIcons.darkMode, Stm.colors.onSurfaceVariant) },
                trailing = { StmSwitch(dark) { dark = it } },
            )
            ListItem(
                "Avisos de cobros y límites",
                leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                trailing = { StmSwitch(alerts) { alerts = it } },
            )
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false) { nav.go(33) }
        }
    }
}

/** 31 Categorías: gastos o ingresos agrupados, con asa para reordenar. */
@Composable
fun Pantalla31(nav: Nav) {
    val c = Stm.colors
    var income by remember { mutableStateOf(false) }
    StmScreen(
        topBar = {
            TopBar("Categorías", onNav = nav::back) {
                IconBtn(StmIcons.add, null, contentDescription = "Añadir categoría")
            }
        },
    ) {
        ChipRow {
            Chip("Gastos", selected = !income, onClick = { income = false })
            Chip("Ingresos", selected = income, onClick = { income = true })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Necesidades")
            CategoryRow(StmIcons.home, "Vivienda")
            CategoryRow(StmIcons.shoppingCart, "Comida")
            CategoryRow(StmIcons.accountBalance, "Impuestos")
            CategoryRow(StmIcons.gavel, "Multas y sanciones")
            ListHeader("Deseos")
            CategoryRow(StmIcons.theaterComedy, "Ocio", c.tertiaryContainer, c.onTertiaryContainer)
            CategoryRow(StmIcons.subscriptions, "Suscripciones", c.tertiaryContainer, c.onTertiaryContainer)
        }
    }
}

/** 32 Importar CSV: archivo elegido, columnas, vista previa e importación. */
@Composable
fun Pantalla32(nav: Nav) {
    val c = Stm.colors
    val cardShape = RoundedCornerShape(12.dp)
    StmScreen(
        topBar = { TopBar("Importar CSV", navIcon = StmIcons.close, onNav = nav::back) },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn("Importar 148 movimientos", { nav.go(5) }, Modifier.fillMaxWidth(), large = true)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().height(72.dp).clip(cardShape).background(c.surface)
                .border(1.dp, c.outlineVariant, cardShape).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LeadIcon(StmIcons.description, c.tertiaryContainer, c.onTertiaryContainer)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("movimientos-octubre.csv", style = StmType.titleMedium, color = c.onSurface, maxLines = 1)
                Text("148 filas · separador ;", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            IconBtn(StmIcons.close, null, contentDescription = "Quitar archivo")
        }
        Spacer(Modifier.height(16.dp))
        Text("Qué columna es cada dato", style = StmType.titleSmall, color = c.onSurfaceVariant)
        listOf(
            "Fecha" to "Columna A · dd/mm/aaaa",
            "Concepto" to "Columna B",
            "Importe" to "Columna D · coma decimal",
            "Cuenta de destino" to "Cuenta principal",
        ).forEach { (label, value) ->
            Spacer(Modifier.height(16.dp))
            FilledField(label, value, trailing = StmIcons.arrowDropDown)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Vista previa")
            ListItem("Supermercado Día", "03/10/2026", trailingText = "−64,20 €")
            Divider(inset = 16.dp)
            ListItem("Nómina", "01/10/2026", trailingText = "+2.150,00 €")
        }
    }
}

/** 33 Borrar datos: diálogo de confirmación sobre Más opciones. */
@Composable
fun Pantalla33(nav: Nav) {
    val c = Stm.colors
    var confirm by remember { mutableStateOf("borrar") }
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        overlay = {
            StmDialog(
                "¿Borrar todos los datos?",
                "Se borrarán las cuentas, movimientos, presupuestos, metas, tarjetas e inversiones del hogar. Esta acción no se puede deshacer.",
                icon = StmIcons.deleteForever,
                onDismiss = nav::back,
                actions = {
                    Btn("Cancelar", nav::back, kind = BtnKind.Text)
                    Btn("Borrar", { nav.reset(1) }, kind = BtnKind.Error, enabled = confirm.trim() == "borrar")
                },
            ) {
                Spacer(Modifier.height(16.dp))
                OutlinedField("Escribe «borrar» para confirmar", confirm, { confirm = it }, labelBackground = c.surfaceContainerHigh, autoFocus = true)
            }
        },
    ) {
        ListCard {
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false, onClick = null)
        }
    }
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

/** Cabecera de Más opciones: barra vacía de 64 y título grande (152 dp en total). */
@Composable
private fun MasHeader() {
    Spacer(Modifier.height(88.dp))
    Text("Más opciones", Modifier.padding(start = 16.dp), style = StmType.headlineLarge, color = Stm.colors.onSurface)
    Spacer(Modifier.height(24.dp))
}

/** Barra superior mediana (112 dp): fila de 60 con atrás y acciones, y título de 28 debajo. */
@Composable
private fun MediumTopBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconBtn(StmIcons.arrowBack, onBack, contentDescription = "Atrás")
        Spacer(Modifier.weight(1f))
        actions()
    }
    Text(title, Modifier.padding(start = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = Stm.colors.onSurface)
}

/**
 * Botón segmentado que se ajusta al texto: 12 dp a cada lado, mínimo 48 y 4 dp más en los extremos
 * redondeados (el compartido reparte el ancho a partes iguales).
 */
@Composable
private fun HugSegmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            val outer = if (i == 0 || i == options.lastIndex) 4.dp else 0.dp
            Row(
                Modifier.fillMaxHeight().let { if (on) it.background(c.secondaryContainer) else it }
                    .drawBehind { if (i > 0) drawRect(c.outline, Offset.Zero, Size(1.dp.toPx(), size.height)) }
                    .tap(role = Role.RadioButton) { onSelect(i) }
                    .padding(start = if (i == 0) outer else 0.dp, end = if (i == options.lastIndex) outer else 0.dp)
                    .widthIn(min = 48.dp - outer).padding(horizontal = 12.dp),
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

/** Elemento de leyenda: punto de 8 y texto. */
@Composable
private fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

/** Dato de la posición: etiqueta a la izquierda y valor a la derecha. */
@Composable
private fun DataRow(label: String, value: String, valueColor: Color = Stm.colors.onSurface) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        Text(value, style = StmType.labelLarge, color = valueColor)
    }
}

/** Campo con borde y sufijo de unidad (€, %); etiqueta sobre el borde en el color de la tarjeta. */
@Composable
private fun SuffixField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, modifier: Modifier) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(4.dp)
    Box(modifier.height(56.dp)) {
        Row(
            Modifier.fillMaxSize().border(if (focused) 2.dp else 1.dp, if (focused) c.primary else c.outline, shape)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value, onValueChange, Modifier.weight(1f).onFocusChanged { focused = it.isFocused }, singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            Spacer(Modifier.width(12.dp))
            Text(suffix, style = StmType.bodyLarge, color = c.onSurfaceVariant)
        }
        Text(
            label, style = StmType.bodySmall, color = if (focused) c.primary else c.onSurfaceVariant,
            modifier = Modifier.offset(12.dp, (-8).dp).background(c.surfaceContainerLowest).padding(horizontal = 4.dp),
        )
    }
}

/** Fila del menú de Más: icono de 24, texto, contador opcional y chevron. */
@Composable
private fun MenuRow(icon: ImageVector, label: String, count: String? = null, chevron: Boolean = true, onClick: (() -> Unit)?) {
    val c = Stm.colors
    ListItem(
        label,
        leading = { StmIcon(icon, c.onSurfaceVariant) },
        trailing = if (!chevron) null else {
            {
                Row {
                    if (count != null) {
                        Text(count, style = StmType.bodyMedium, color = c.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                    }
                    StmIcon(StmIcons.chevronRight, c.onSurfaceVariant)
                }
            }
        },
        onClick = onClick,
    )
}

/** Categoría: icono en círculo, nombre y asa para arrastrar. */
@Composable
private fun CategoryRow(
    icon: ImageVector,
    label: String,
    container: Color = Stm.colors.secondaryContainer,
    tint: Color = Stm.colors.onSecondaryContainer,
) {
    ListItem(
        label,
        leading = { LeadIcon(icon, container, tint) },
        trailing = { StmIcon(StmIcons.dragIndicator, Stm.colors.onSurfaceVariant, contentDescription = "Reordenar") },
    )
}
