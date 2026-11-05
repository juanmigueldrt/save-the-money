package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.SectionHeader
import com.savethemoney.android.ui.components.Segmented
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


/** 10 Tarjetas: tarjeta principal, límite, próximo cargo y resto de tarjetas. */
@Composable
fun Pantalla10(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            // La fila de la barra grande mide 60 dp, no 64.
            Box(Modifier.height(60.dp)) {
                TopBar(null, onNav = nav::back) {
                    IconBtn(StmIcons.add, { nav.go(9) }, contentDescription = "Añadir tarjeta")
                }
            }
            Text("Tarjetas", Modifier.padding(start = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
            Spacer(Modifier.height(16.dp))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
    ) {
        // «Tarjeta visual» en inverse-surface: en oscuro sale clara.
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.inverseSurface)
                .tap { nav.go(11) }.padding(20.dp),
        ) {
            Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Visa compartida", Modifier.weight(1f), style = StmType.titleMedium, color = c.inverseOnSurface)
                Box(Modifier.size(40.dp, 28.dp).clip(RoundedCornerShape(6.dp)).background(c.primaryContainer))
            }
            Spacer(Modifier.height(37.dp))
            val soft = c.inverseOnSurface.copy(alpha = 0.8f)
            Text("Usado", style = StmType.labelMedium, color = soft)
            Spacer(Modifier.height(4.dp))
            Text("1.140 €", style = StmType.headlineMedium, color = c.inverseOnSurface)
            Spacer(Modifier.height(4.dp))
            Text("•••• 4821", style = StmType.bodyMedium, color = soft)
        }
        Spacer(Modifier.height(16.dp))
        StmCard(onClick = { nav.go(12) }) {
            Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Límite", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text("1.140 de 3.000 €", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            Progress(0.38f)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth().height(20.dp)) {
                Text("Disponible", Modifier.weight(1f).alignByBaseline(), style = StmType.bodySmall, color = c.onSurfaceVariant)
                Text("1.860 €", Modifier.alignByBaseline(), style = StmType.labelLarge, color = c.onSurface)
            }
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Próximo cargo · 1 de diciembre", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.5.dp))
            Text("312,40 €", style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(4.5.dp))
            Text(
                "Pago total del extracto + 2 cuotas de aplazados (incluye 4,10 € de intereses). Sale de Cuenta principal.",
                style = StmType.bodyMedium, color = c.onSurfaceVariant, minLines = 3,
            )
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Btn("Ver calendario", { nav.go(11) }, kind = BtnKind.Text)
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Mastercard", "Usado 240 de 1.500 € · cuota fija",
                leading = { LeadIcon(StmIcons.creditCard, c.surfaceContainerHighest, c.onSurfaceVariant) },
                trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) },
                onClick = { nav.go(11) },
            )
        }
    }
}

/** 11 Detalle de tarjeta: extracto abierto, calendario de cargos y compras aplazadas. */
@Composable
fun Pantalla11(nav: Nav) {
    val c = Stm.colors
    StmScreen(topBar = { DetalleBar(nav) }) {
        StmCard {
            Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Extracto abierto", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text("del 1 al 30 nov", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth().height(28.dp)) {
                Text("Gastado este ciclo", Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Text("828,40 €", Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
            }
            Spacer(Modifier.height(12.dp))
            Progress(0.38f)
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader("Calendario de cargos")
        ListCard {
            Cargo("1 de diciembre", "Extracto de noviembre + cuotas", "312,40 €", next = true)
            Divider()
            Cargo("1 de enero", "Cuotas de aplazados", "38,42 €")
            Divider()
            Cargo("1 de febrero", "Última cuota del restaurante", "19,21 €")
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader("Compras aplazadas", "Aplazar") { nav.go(13) }
        ListCard {
            // Elemento de tres líneas: el icono y el importe van arriba, no centrados.
            Row(Modifier.fillMaxWidth().tap { nav.go(13) }.padding(start = 16.dp, end = 24.dp, top = 12.dp, bottom = 12.dp)) {
                LeadIcon(StmIcons.restaurant)
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text("Restaurante Sol", style = StmType.bodyLarge, color = c.onSurface)
                    Text("3 meses · TIN 14 %", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                    Text("Quedan 2 cuotas", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                }
                Spacer(Modifier.width(16.dp))
                Column(horizontalAlignment = Alignment.End) {
                    Text("56,00 €", style = StmType.labelLarge, color = c.onSurface)
                    Text("19,21 €/mes", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
        }
    }
}

/** 12 Condiciones de tarjeta: límite, días de extracto y cargo, forma de pago, intereses y avisos. */
@Composable
fun Pantalla12(nav: Nav) {
    val c = Stm.colors
    var limite by remember { mutableStateOf("3.000,00") }
    var diaExtracto by remember { mutableStateOf("1") }
    var diaCargo by remember { mutableStateOf("1") }
    var forma by remember { mutableIntStateOf(0) }
    var tinAplazado by remember { mutableStateOf("20,00") }
    var tinPlazos by remember { mutableStateOf("14,00") }
    var recordar by remember { mutableStateOf(true) }
    var avisar by remember { mutableStateOf(true) }
    StmScreen(
        topBar = {
            TopBar("Condiciones", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", nav::back, kind = BtnKind.Text)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField("Límite de crédito", limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("Día del extracto", diaExtracto, { diaExtracto = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
            FilledField("Día del cargo", diaCargo, { diaCargo = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
        }
        Spacer(Modifier.height(16.dp))
        Text("Forma de pago", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Todo", "Cuota fija", "Mínimo"), forma, { forma = it })
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("TIN aplazado", tinAplazado, { tinAplazado = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
            FilledField("TIN a plazos", tinPlazos, { tinPlazos = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Paga desde", "Cuenta principal", trailing = StmIcons.arrowDropDown)
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem("Recordar el cargo", "2 días antes", trailing = { SwitchSlot(recordar) { recordar = it } })
            Divider(inset = 16.dp)
            ListItem("Avisar al 80 % del límite", trailing = { SwitchSlot(avisar) { avisar = it } })
        }
    }
}

/** 13 Aplazar compra: hoja inferior con plazos, TIN y cuota resultante sobre el detalle de la tarjeta. */
@Composable
fun Pantalla13(nav: Nav) {
    val c = Stm.colors
    var plazo by remember { mutableIntStateOf(0) }
    var tin by remember { mutableStateOf("14,00") }
    StmScreen(
        topBar = { DetalleBar(nav) },
        overlay = {
            BottomSheet("Aplazar Restaurante Sol", "56,00 € · 3 nov", onDismiss = nav::back) {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    // La cabecera del diseño mide 56 dp; la de la hoja compartida, 54.
                    Spacer(Modifier.height(2.dp))
                    Segmented(listOf("3", "6", "9", "12 meses"), plazo, { plazo = it })
                    Spacer(Modifier.height(16.dp))
                    SuffixOutlinedField("TIN anual", tin, { tin = it }, "%", c.surfaceContainerLow)
                    Spacer(Modifier.height(16.dp))
                    StmCard(color = c.surfaceContainerHighest) {
                        Row(Modifier.fillMaxWidth().height(28.dp)) {
                            Text("Cuota", Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                            Text("19,21 €/mes", Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(Modifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("Intereses en total", Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                            Text("1,63 €", style = StmType.labelLarge, color = c.onSurface)
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn("Cancelar", nav::back, kind = BtnKind.Text)
                        Btn("Aplazar", nav::back)
                    }
                }
            }
        },
    ) {
        // Bajo la hoja, el diseño solo muestra el próximo cargo de la tarjeta.
        StmCard {
            Text("Próximo cargo", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.5.dp))
            Text("312,40 €", style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(0.5.dp))
        }
    }
}

/** Barra de «Visa compartida» que comparten el detalle (11) y el aplazamiento (13). */
@Composable
private fun DetalleBar(nav: Nav) {
    TopBar("Visa compartida", onNav = nav::back) {
        IconBtn(StmIcons.edit, { nav.go(12) }, contentDescription = "Editar condiciones")
        IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
    }
}

/** Fila del calendario de cargos; el próximo va resaltado en secondary-container. */
@Composable
private fun Cargo(date: String, detail: String, amount: String, next: Boolean = false) {
    val c = Stm.colors
    ListItem(
        date, detail, trailingText = amount,
        leading = {
            if (next) LeadIcon(StmIcons.event) else LeadIcon(StmIcons.event, c.surfaceContainerHighest, c.onSurfaceVariant)
        },
    )
}

/** «Final» de 40 dp del diseño: el interruptor de 52 sobresale por la derecha, como en FigCraft. */
@Composable
private fun SwitchSlot(checked: Boolean, onChange: (Boolean) -> Unit) {
    Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) {
        StmSwitch(checked, onChange)
    }
}

/** «Campo de texto» con borde y sufijo (p. ej. «%»), que el OutlinedField compartido no tiene. */
@Composable
private fun SuffixOutlinedField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, labelBackground: Color) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().height(56.dp)) {
        Row(
            Modifier.fillMaxSize().border(if (focused) 2.dp else 1.dp, if (focused) c.primary else c.outline, RoundedCornerShape(4.dp))
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
            modifier = Modifier.offset(x = 12.dp, y = (-8).dp).background(labelBackground).padding(horizontal = 4.dp),
        )
    }
}
