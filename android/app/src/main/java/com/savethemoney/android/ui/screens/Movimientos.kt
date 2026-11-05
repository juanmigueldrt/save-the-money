package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 05 Movimientos: búsqueda, filtros, lista agrupada por día y aviso de borrado. */
@Composable
fun Pantalla05(nav: Nav) {
    var busqueda by remember { mutableStateOf("") }
    var filtros by remember { mutableStateOf(setOf("Comida")) }
    var eliminado by remember { mutableStateOf(true) }
    StmScreen(
        topBar = {
            MovimientosTopBar(nav)
            CampoBusqueda(busqueda, { busqueda = it }, "Comercio o categoría")
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listOf("Comida", "Ocio", "Pagos fijos", "Transporte", "Hogar").forEach { f ->
                    Chip(f, selected = f in filtros, onClick = { filtros = if (f in filtros) filtros - f else filtros + f })
                }
            }
            Spacer(Modifier.height(12.dp))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        fab = { Fab("Añadir") { nav.go(7) } },
        snackbar = if (eliminado) {
            {
                // El diseño deja 16 dp entre FAB y snackbar; StmScreen pone 12.
                Spacer(Modifier.height(4.dp))
                Snackbar("Movimiento eliminado", "Deshacer") { eliminado = false }
            }
        } else null,
    ) {
        ListaMovimientos(nav)
    }
}

/** 06 Cuenta corriente: saldo, acciones, evolución en 6 meses y movimientos del mes. */
@Composable
fun Pantalla06(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            TopBar("Cuenta principal", onNav = nav::back) {
                IconBtn(StmIcons.edit, null, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
            }
        },
    ) {
        CifraCuenta("Saldo", "3.412,58 €", "Banco de ejemplo · actualizado hoy")
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Btn("Importar CSV", { nav.go(32) }, kind = BtnKind.Tonal, icon = StmIcons.uploadFile)
            Btn("Transferir", null, kind = BtnKind.Outlined, icon = StmIcons.syncAlt)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Saldo en 6 meses", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            // Puntos del «Área» del diseño: y en una caja de 120 → 1 − y/120.
            LineChart(listOf(83.4f, 50.8f, 116f, 18.2f, 59f, 0f).map { 1f - it / 120f })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Noviembre")
            ListItem(
                "Nómina", "1 nov", trailingText = "+2.150,00 €",
                leading = { LeadIcon(StmIcons.work, c.successContainer, c.onSuccessContainer) },
            )
            Divider()
            ListItem("Alquiler", "1 nov · pago fijo", trailingText = "−850,00 €", leading = { LeadIcon(StmIcons.home) })
            Divider()
            ListItem("Luz", "3 nov · pago fijo", trailingText = "−61,20 €", leading = { LeadIcon(StmIcons.bolt) })
        }
    }
}

/** 07 Nuevo movimiento: tipo, importe, concepto, categoría, cuenta, fecha y extras. */
@Composable
fun Pantalla07(nav: Nav) {
    val c = Stm.colors
    var tipo by remember { mutableIntStateOf(0) }
    var importe by remember { mutableStateOf("64,20 €") }
    var concepto by remember { mutableStateOf("Supermercado Día") }
    StmScreen(
        topBar = {
            TopBar("Nuevo movimiento", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Gasto", "Ingreso", "Transferencia"), tipo, { tipo = it })
        Spacer(Modifier.height(16.dp))
        Column(
            Modifier.fillMaxWidth().height(116.dp).padding(top = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Importe", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            BasicTextField(
                importe, { importe = it }, Modifier.fillMaxWidth(), singleLine = true,
                textStyle = StmType.displayLarge.copy(color = c.onSurface, textAlign = TextAlign.Center),
                cursorBrush = SolidColor(c.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Concepto", concepto, { concepto = it })
        Spacer(Modifier.height(16.dp))
        FilledField("Categoría", "Comida", leading = StmIcons.shoppingCart, trailing = StmIcons.arrowDropDown)
        Spacer(Modifier.height(16.dp))
        FilledField("Cuenta", "Tarjeta compartida", trailing = StmIcons.arrowDropDown)
        Spacer(Modifier.height(16.dp))
        FilledField("Fecha", "Hoy, 5 nov 2026", trailing = StmIcons.calendarToday)
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento()
    }
}

/** 08 Acciones del movimiento: la lista de 05 con la hoja de acciones abierta. */
@Composable
fun Pantalla08(nav: Nav) {
    StmScreen(
        topBar = { MovimientosTopBar(nav) },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        overlay = {
            BottomSheet("Supermercado Día", "−64,20 € · Hoy", onDismiss = nav::back) {
                SheetItem(StmIcons.category, "Cambiar categoría") { nav.go(31) }
                SheetItem(StmIcons.callSplit, "Dividir gasto") { nav.go(7) }
                SheetItem(StmIcons.eventRepeat, "Aplazar con la tarjeta") { nav.go(13) }
                SheetItem(StmIcons.visibilityOff, "Ocultar de informes", onClick = nav::back)
                SheetItem(StmIcons.delete, "Eliminar", onClick = nav::back)
            }
        },
    ) {
        ListaMovimientos(nav, completa = false)
    }
}

/** 09 Nueva cuenta: nombre, tipo, saldo inicial y si se comparte con el hogar. */
@Composable
fun Pantalla09(nav: Nav) {
    val c = Stm.colors
    val tipos = listOf("Corriente", "Ahorro", "Tarjeta de crédito", "Efectivo", "Inversión")
    var nombre by remember { mutableStateOf("Cuenta ahorro") }
    var tipo by remember { mutableIntStateOf(1) }
    var saldo by remember { mutableStateOf("1.500,00") }
    var compartir by remember { mutableStateOf(true) }
    StmScreen(
        topBar = {
            TopBar("Nueva cuenta", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField("Nombre", nombre, { nombre = it }, autoFocus = true)
        Spacer(Modifier.height(16.dp))
        Text("Tipo", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        ChipRow(Modifier.fillMaxWidth()) {
            tipos.forEachIndexed { i, t -> Chip(t, selected = i == tipo, onClick = { tipo = i }) }
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Saldo inicial", saldo, { saldo = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Compartir con el hogar", "Tu pareja verá el saldo y los movimientos",
                trailing = {
                    // El diseño reserva 40 dp al final y deja que el interruptor de 52 sobresalga.
                    Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) {
                        StmSwitch(compartir) { compartir = it }
                    }
                },
            )
        }
    }
}

/** 34 Menú de movimiento: detalle de «Supermercado Día» con el menú de acciones abierto. */
@Composable
fun Pantalla34(nav: Nav) {
    var menu by remember { mutableStateOf(true) }
    StmScreen(
        topBar = {
            TopBar("Supermercado Día", onNav = nav::back) {
                IconBtn(StmIcons.edit, { nav.go(7) }, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, { menu = !menu }, contentDescription = "Más opciones")
            }
        },
        overlay = if (menu) {
            {
                Box(
                    Modifier.matchParentSize()
                        .clickable(remember { MutableInteractionSource() }, indication = null) { menu = false },
                )
                // Barra superior (64) + 96 del diseño, a 12 dp del borde derecho.
                MenuDesplegable(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 160.dp, end = 12.dp)) {
                    ElementoMenu(StmIcons.edit, "Editar") { nav.go(7) }
                    ElementoMenu(StmIcons.contentCopy, "Duplicar", onClick = nav::back)
                    ElementoMenu(StmIcons.eventRepeat, "Aplazar") { nav.go(13) }
                    Spacer(Modifier.height(8.dp))
                    Divider(inset = 0.dp, endInset = 0.dp)
                    Spacer(Modifier.height(8.dp))
                    ElementoMenu(StmIcons.delete, "Eliminar", Stm.colors.error, Stm.colors.error, onClick = nav::back)
                }
            }
        } else null,
    ) {
        CifraCuenta("Comida · Tarjeta compartida", "−64,20 €", "Hoy, 5 nov 2026")
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento()
    }
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

/** Barra de 05 y 08: atrás, título, filtros y más opciones. */
@Composable
private fun MovimientosTopBar(nav: Nav) {
    TopBar("Movimientos", onNav = nav::back) {
        IconBtn(StmIcons.tune, null, contentDescription = "Filtros")
        IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
    }
}

/** Lista agrupada por día de 05; en 08 ([completa] falso) solo se ve el primer movimiento. */
@Composable
private fun ListaMovimientos(nav: Nav, completa: Boolean = true) {
    ListCard {
        ListHeader("Hoy")
        FilaMovimiento("Supermercado Día", "Comida · Tarjeta compartida", "−64,20 €", StmIcons.shoppingCart) { nav.go(8) }
        if (completa) {
            Divider()
            FilaMovimiento("Panadería La Espiga", "Comida · Efectivo", "−3,80 €", StmIcons.bakeryDining) { nav.go(8) }
            ListHeader("Ayer")
            FilaMovimiento("Mercadona", "Comida · Visa", "−82,35 €", StmIcons.shoppingCart) { nav.go(8) }
            Divider()
            FilaMovimiento("Frutería Lola", "Comida · Efectivo", "−12,40 €", StmIcons.nutrition) { nav.go(8) }
            ListHeader("3 de noviembre")
            ListItem(
                "Restaurante Sol", "Comida · Visa · a plazos",
                leading = { LeadIcon(StmIcons.restaurant) },
                trailing = {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("−56,00 €", style = StmType.labelLarge, color = Stm.colors.onSurface)
                        Text("3 × 19,21 €", style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
                    }
                },
                onClick = { nav.go(11) },
            )
        }
    }
}

@Composable
private fun FilaMovimiento(title: String, detail: String, amount: String, icon: ImageVector, onClick: () -> Unit) {
    ListItem(title, detail, trailingText = amount, leading = { LeadIcon(icon) }, onClick = onClick)
}

/** «Campo de texto» con borde, lupa y texto de ejemplo, sin etiqueta. */
@Composable
private fun CampoBusqueda(value: String, onValueChange: (String) -> Unit, placeholder: String) {
    val c = Stm.colors
    Row(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(56.dp)
            .border(1.dp, c.outline, RoundedCornerShape(4.dp)).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(StmIcons.search, c.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = StmType.bodyLarge, color = c.onSurfaceVariant)
            BasicTextField(
                value, onValueChange, Modifier.fillMaxWidth(), singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
            )
        }
    }
}

/** «Cifra principal» (100 dp): etiqueta, cifra serif y nota. */
@Composable
private fun CifraCuenta(label: String, value: String, note: String) {
    val c = Stm.colors
    Column(Modifier.fillMaxWidth().height(100.dp).padding(top = 8.dp)) {
        Text(label, style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.5.dp))
        Text(value, style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Text(note, style = StmType.bodyMedium, color = c.onSurfaceVariant)
    }
}

/** Chips de acción «Dividir gasto» y «Añadir nota» (07 y 34). */
@Composable
private fun ChipsMovimiento() {
    val c = Stm.colors
    ChipRow(Modifier.fillMaxWidth()) {
        Chip("Dividir gasto", icon = StmIcons.callSplit, labelColor = c.onSurface)
        Chip("Añadir nota", icon = StmIcons.stickyNote2, labelColor = c.onSurface)
    }
}

/** «Menú» desplegable de 200 dp en `surface-container`. */
@Composable
private fun MenuDesplegable(modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Column(
        modifier.width(200.dp).shadow(3.dp, shape).clip(shape).background(Stm.colors.surfaceContainer)
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .padding(vertical = 8.dp),
        content = content,
    )
}

/** «Elemento de menú» (48 dp): icono de 24 y texto. */
@Composable
private fun ElementoMenu(
    icon: ImageVector,
    label: String,
    color: Color = Stm.colors.onSurface,
    iconTint: Color = Stm.colors.onSurfaceVariant,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).tap(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(icon, iconTint)
        Spacer(Modifier.width(12.dp))
        Text(label, style = StmType.bodyMedium, color = color)
    }
}
