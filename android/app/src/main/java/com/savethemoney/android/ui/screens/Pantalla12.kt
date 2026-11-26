package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CardPaymentMode
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 12 Condiciones de tarjeta: límite, días de extracto y cargo, forma de pago, intereses y avisos. */
@Composable
fun Pantalla12(nav: Nav, cardId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val cuenta = cards.card(cardId)
    if (cardId != null && cuenta == null) return NoEncontrado(nav)
    val base = cuenta?.let { cards.terms[it.id] }
    var limite by rememberSaveable(base) { mutableStateOf(base?.creditLimit?.let(Money::input).orEmpty()) }
    var diaExtracto by rememberSaveable(base) { mutableStateOf("${base?.statementDay ?: 1}") }
    var diaCargo by rememberSaveable(base) { mutableStateOf("${base?.paymentDay ?: 1}") }
    var retraso by rememberSaveable(base) { mutableIntStateOf(base?.paymentDelayMonths ?: 1) }
    var forma by rememberSaveable(base) { mutableIntStateOf(base?.paymentMode?.ordinal ?: 0) }
    var cuota by rememberSaveable(base) { mutableStateOf(base?.fixedPayment?.let(Money::input).orEmpty()) }
    var minimoPct by rememberSaveable(base) { mutableStateOf(tasa(base?.minPaymentPercent ?: 3.0)) }
    var minimo by rememberSaveable(base) { mutableStateOf(Money.input(base?.minPayment ?: 1_500)) }
    var tinAplazado by rememberSaveable(base) { mutableStateOf(tasa(base?.revolvingRate ?: 20.0)) }
    var tinPlazos by rememberSaveable(base) { mutableStateOf(tasa(base?.installmentRate ?: 14.0)) }
    var pagaDesde by rememberSaveable(base) { mutableStateOf(base?.payFromAccountId) }
    var recordar by rememberSaveable(base) { mutableStateOf(base == null || base.remindDaysBefore != null) }
    var dias by rememberSaveable(base) { mutableIntStateOf(base?.remindDaysBefore ?: 2) }
    var avisar by rememberSaveable(base) { mutableStateOf(base == null || base.alertPercent != null) }
    var aviso by rememberSaveable(base) { mutableIntStateOf(base?.alertPercent ?: 80) }
    var eligeCuenta by remember { mutableStateOf(false) }
    val action = rememberAction()
    val modo = CardPaymentMode.entries[forma]

    fun guardar() = action.run {
        if (cuenta == null) {
            nav.back()
            return@run
        }
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val limiteMinor = Money.entered(limite)?.takeIf { it > 0 } ?: falla("El límite no es un importe válido.")
        val revolving = leerTasa(tinAplazado) ?: falla("Revisa los intereses y el pago mínimo.")
        val plazos = leerTasa(tinPlazos) ?: falla("Revisa los intereses y el pago mínimo.")
        val pct = leerTasa(minimoPct) ?: falla("Revisa los intereses y el pago mínimo.")
        val suelo = Money.entered(minimo.ifBlank { "0" }) ?: falla("El pago mínimo no es un importe válido.")
        val fija = if (modo == CardPaymentMode.Fixed) Money.entered(cuota)?.takeIf { it > 0 } ?: falla("La cuota no es un importe válido.") else null
        cards.save(
            CreditCardTerms(
                cuenta.id, cuenta.householdId, limiteMinor, diaExtracto.toIntOrNull() ?: 0, diaCargo.toIntOrNull() ?: 0, retraso, modo, fija,
                pct, suelo, revolving, plazos, pagaDesde, if (recordar) dias else null, if (avisar) aviso else null,
                // La versión que se cargó con estos campos (nula: aún no había condiciones): se guarda sobre ella.
                updatedAt = base?.updatedAt,
            ),
        )
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Condiciones", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeCuenta) {
            {
                SelectorSheet(
                    "Se paga desde",
                    listOf<Pair<String, () -> Unit>>("Sin elegir" to { pagaDesde = null }) +
                        finance.activeAccounts.filter { it.id != cuenta?.id && !it.kind.isLiability }.map { a -> a.name to { pagaDesde = a.id } },
                ) { eligeCuenta = false }
            }
        } else {
            null
        },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField("Límite de crédito", limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("Día del extracto", diaExtracto, { diaExtracto = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
            FilledField("Día del cargo", diaCargo, { diaCargo = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
        }
        Spacer(Modifier.height(16.dp))
        Text("Forma de pago", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Todo", "Cuota fija", "Mínimo"), forma, { forma = it })
        // Solo aparecen al cambiar la forma de pago, así que el diseño no se mueve.
        if (modo == CardPaymentMode.Fixed) {
            Spacer(Modifier.height(16.dp))
            FilledField("Cuota al mes", cuota, { cuota = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        }
        if (modo.isRevolving) {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField("Mínimo: % deuda", minimoPct, { minimoPct = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
                FilledField("Mínimo: al menos", minimo, { minimo = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                modo.detail + " El pago mínimo es el % de la deuda más los intereses, y nunca menos del importe mínimo.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("TIN aplazado", tinAplazado, { tinAplazado = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
            FilledField("TIN a plazos", tinPlazos, { tinPlazos = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
        }
        Spacer(Modifier.height(16.dp))
        FilledField(
            "Paga desde", finance.account(pagaDesde)?.name ?: "Sin elegir",
            trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true },
        )
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem("Recordar el cargo", textoAviso(dias).replaceFirstChar(Char::uppercase), trailing = { SwitchSlot(recordar) { recordar = it } })
            Divider(inset = 16.dp)
            ListItem("Avisar al $aviso % del límite", trailing = { SwitchSlot(avisar) { avisar = it } })
        }
        // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
        Spacer(Modifier.height(16.dp))
        if (recordar) {
            FilaStepper("Cuándo recordar", textoAviso(dias), { dias = (dias - 1).coerceAtLeast(0) }, { dias = (dias + 1).coerceAtMost(14) })
            Spacer(Modifier.height(12.dp))
        }
        if (avisar) {
            FilaStepper("Avisar al pasar del", "$aviso %", { aviso = (aviso - 5).coerceAtLeast(50) }, { aviso = (aviso + 5).coerceAtMost(100) })
            Spacer(Modifier.height(16.dp))
        }
        Text("Se cobra", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Mismo mes", "Mes siguiente", "2 meses"), retraso, { retraso = it })
        Spacer(Modifier.height(8.dp))
        Text(
            "Míralo en tu contrato. Por ejemplo: extracto el día 1 y cargo el día 1 del mes siguiente quiere decir que lo gastado en enero se cobra el 1 de marzo.",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun FilaStepper(titulo: String, valor: String, onMenos: () -> Unit, onMas: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(titulo, Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
        Stepper(valor, onMenos, onMas)
    }
}

/** «Final» de 40 dp del diseño: el interruptor de 52 sobresale por la derecha, como en FigCraft. */
@Composable
private fun SwitchSlot(checked: Boolean, onChange: (Boolean) -> Unit) {
    Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) {
        StmSwitch(checked, onChange)
    }
}
