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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
import com.savethemoney.android.ui.detalle
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
    val resources = LocalResources.current

    fun guardar() = action.run {
        if (cuenta == null) {
            nav.back()
            return@run
        }
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val limiteMinor = Money.entered(limite)?.takeIf { it > 0 } ?: falla(resources.getString(R.string.condiciones_tarjeta_el_limite_no_es_un_importe))
        val revolving = leerTasa(tinAplazado) ?: falla(resources.getString(R.string.condiciones_tarjeta_revisa_los_intereses_y_el_pago))
        val plazos = leerTasa(tinPlazos) ?: falla(resources.getString(R.string.condiciones_tarjeta_revisa_los_intereses_y_el_pago))
        val pct = leerTasa(minimoPct) ?: falla(resources.getString(R.string.condiciones_tarjeta_revisa_los_intereses_y_el_pago))
        val suelo = Money.entered(minimo.ifBlank { "0" }) ?: falla(resources.getString(R.string.condiciones_tarjeta_el_pago_minimo_no_es_un))
        val fija = if (modo == CardPaymentMode.Fixed) Money.entered(cuota)?.takeIf { it > 0 } ?: falla(resources.getString(R.string.condiciones_tarjeta_la_cuota_no_es_un_importe)) else null
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
            TopBar(stringResource(R.string.condiciones_tarjeta_condiciones), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeCuenta) {
            {
                SelectorSheet(
                    stringResource(R.string.condiciones_tarjeta_se_paga_desde),
                    listOf<Pair<String, () -> Unit>>(stringResource(R.string.condiciones_tarjeta_sin_elegir) to { pagaDesde = null }) +
                        finance.activeAccounts.filter { it.id != cuenta?.id && !it.kind.isLiability }.map { a -> a.name to { pagaDesde = a.id } },
                ) { eligeCuenta = false }
            }
        } else {
            null
        },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField(stringResource(R.string.condiciones_tarjeta_limite_de_credito), limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField(stringResource(R.string.condiciones_tarjeta_dia_del_extracto), diaExtracto, { diaExtracto = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
            FilledField(stringResource(R.string.condiciones_tarjeta_dia_del_cargo), diaCargo, { diaCargo = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
        }
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.condiciones_tarjeta_forma_de_pago), style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf(stringResource(R.string.condiciones_tarjeta_todo), stringResource(R.string.condiciones_tarjeta_cuota_fija), stringResource(R.string.condiciones_tarjeta_minimo)), forma, { forma = it })
        // Solo aparecen al cambiar la forma de pago, así que el diseño no se mueve.
        if (modo == CardPaymentMode.Fixed) {
            Spacer(Modifier.height(16.dp))
            FilledField(stringResource(R.string.condiciones_tarjeta_cuota_al_mes), cuota, { cuota = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        }
        if (modo.isRevolving) {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField(stringResource(R.string.condiciones_tarjeta_minimo_deuda), minimoPct, { minimoPct = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
                FilledField(stringResource(R.string.condiciones_tarjeta_minimo_al_menos), minimo, { minimo = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.condiciones_tarjeta_el_pago_minimo_es_el_de, stringResource(modo.detalle)),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField(stringResource(R.string.condiciones_tarjeta_tin_aplazado), tinAplazado, { tinAplazado = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
            FilledField(stringResource(R.string.condiciones_tarjeta_tin_a_plazos), tinPlazos, { tinPlazos = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
        }
        Spacer(Modifier.height(16.dp))
        FilledField(
            stringResource(R.string.condiciones_tarjeta_paga_desde), finance.account(pagaDesde)?.name ?: stringResource(R.string.condiciones_tarjeta_sin_elegir),
            trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true },
        )
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(stringResource(R.string.condiciones_tarjeta_recordar_el_cargo), textoAviso(dias).replaceFirstChar(Char::uppercase), trailing = { SwitchSlot(recordar) { recordar = it } })
            Divider(inset = 16.dp)
            ListItem(stringResource(R.string.condiciones_tarjeta_avisar_al_del_limite, aviso), trailing = { SwitchSlot(avisar) { avisar = it } })
        }
        // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
        Spacer(Modifier.height(16.dp))
        if (recordar) {
            FilaStepper(stringResource(R.string.condiciones_tarjeta_cuando_recordar), textoAviso(dias), { dias = (dias - 1).coerceAtLeast(0) }, { dias = (dias + 1).coerceAtMost(14) })
            Spacer(Modifier.height(12.dp))
        }
        if (avisar) {
            FilaStepper(stringResource(R.string.condiciones_tarjeta_avisar_al_pasar_del), "$aviso %", { aviso = (aviso - 5).coerceAtLeast(50) }, { aviso = (aviso + 5).coerceAtMost(100) })
            Spacer(Modifier.height(16.dp))
        }
        Text(stringResource(R.string.condiciones_tarjeta_se_cobra), style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf(stringResource(R.string.condiciones_tarjeta_mismo_mes), stringResource(R.string.condiciones_tarjeta_mes_siguiente), stringResource(R.string.condiciones_tarjeta_2_meses)), retraso, { retraso = it })
        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.condiciones_tarjeta_miralo_en_tu_contrato_por_ejemplo),
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
