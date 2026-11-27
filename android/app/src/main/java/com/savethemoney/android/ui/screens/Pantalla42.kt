package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** Crear o editar un plan de aportación. */
@Composable
fun Pantalla42(nav: Nav, planId: String?) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val hoy = finance.today()
    val editando = rememberRow(planId) { id -> inv.plans.firstOrNull { it.id == id } }
    if (planId != null && editando == null) return NoEncontrado(nav)
    var activo by rememberSaveable { mutableStateOf(editando?.holdingId ?: inv.activeHoldings.firstOrNull()?.id) }
    var importe by rememberSaveable { mutableStateOf(editando?.let { Money.format(it.amountMinor, symbol = false) }.orEmpty()) }
    var recurrencia by remember { mutableStateOf(editando?.recurrence ?: Recurrence.Monthly) }
    var cuenta by rememberSaveable { mutableStateOf(editando?.accountId) }
    var inicio by rememberSaveable { mutableStateOf(editando?.startDay ?: hoy) }
    var rentabilidad by rememberSaveable { mutableStateOf(editando?.let { InvestmentText.plain(it.expectedAnnualReturn) } ?: "5") }
    var aviso by rememberSaveable { mutableStateOf(if (editando != null) editando.remindDaysBefore else 1) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    var borrando by remember { mutableStateOf(false) }
    // Identificador del plan nuevo, uno por formulario: reintentar el alta con el mismo no crea otro.
    val idPlan = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val action = rememberAction()

    val borrador = run {
        val id = activo
        val money = Money.entered(importe)
        val rate = parseDecimal(rentabilidad, maxFractionDigits = 2)
        if (id == null || money == null || rate == null) null
        else (editando ?: InvestmentPlan(idPlan, inv.householdId, id, amountMinor = money, startsOn = inicio.toString())).copy(
            amountMinor = money, every = recurrencia.every, unit = recurrencia.unit, accountId = cuenta, startsOn = inicio.toString(),
            expectedAnnualReturn = rate, remindDaysBefore = aviso,
        )
    }
    val resources = LocalResources.current

    fun guardar() = action.run {
        if (activo == null) throw AppError.InvalidInput(resources.getString(R.string.form_plan_elige_un_activo))
        val item = borrador ?: throw AppError.InvalidInput(resources.getString(R.string.form_plan_escribe_el_importe_y_la))
        item.issue?.let { throw AppError.InvalidInput(it) }
        inv.save(item)
        nav.back()
    }

    val avisos = listOf(null to stringResource(R.string.form_plan_sin_aviso), 0 to stringResource(R.string.form_plan_el_mismo_dia), 1 to stringResource(R.string.form_plan_1_dia_antes), 3 to stringResource(R.string.form_plan_3_dias_antes))
    StmScreen(
        topBar = {
            TopBar(if (editando == null) stringResource(R.string.form_plan_nuevo_plan) else stringResource(R.string.form_plan_editar_plan), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(if (editando == null) stringResource(R.string.form_plan_crear) else stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            borrando -> {
                {
                    BottomSheet(stringResource(R.string.form_plan_borrar_este_plan), stringResource(R.string.form_plan_las_compras_que_ya_apuntaste_no), onDismiss = { borrando = false }) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn(stringResource(R.string.comun_cancelar), { borrando = false }, kind = BtnKind.Text)
                            Btn(stringResource(R.string.form_plan_borrar_plan), {
                                action.run {
                                    inv.delete(editando!!)
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        }
                    }
                }
            }
            selector != null -> {
                {
                    val cerrar = { selector = null }
                    when (selector) {
                        "activo" -> SelectorSheet(stringResource(R.string.form_plan_activo), inv.activeHoldings.map { h -> h.trimmedName to { activo = h.id } }, cerrar)
                        "cada" -> SelectorSheet(stringResource(R.string.comun_cada), Recurrence.Common.map { r -> r.title to { recurrencia = r } }, cerrar)
                        "aviso" -> SelectorSheet(stringResource(R.string.form_plan_aviso), avisos.map { (d, t) -> t to { aviso = d } }, cerrar)
                        else -> SelectorSheet(stringResource(R.string.form_plan_sale_de), listOf<Pair<String, () -> Unit>>(stringResource(R.string.form_activo_ninguna_cuenta) to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (editando != null) {
                StmCard {
                    val posicion = inv.holding(editando.holdingId)?.let(inv::position)
                    DataRow(if (editando.isPaused) stringResource(R.string.form_plan_estado) else stringResource(R.string.form_plan_proxima), if (editando.isPaused) stringResource(R.string.form_plan_en_pausa) else editando.nextDue(hoy)?.let { Fechas.dia(it, hoy) } ?: stringResource(R.string.form_plan_terminado))
                    Spacer(Modifier.height(8.dp))
                    DataRow(stringResource(R.string.form_plan_invertido_con_el_plan), Money.format(editando.invested(inv.trades, hoy)))
                    Spacer(Modifier.height(8.dp))
                    DataRow(stringResource(R.string.form_plan_rentabilidad_del_activo), posicion?.gainFraction?.let(InvestmentText::percent) ?: "—")
                }
            }
            if (editando != null) {
                FilledField(stringResource(R.string.form_plan_activo), inv.holding(activo)?.trimmedName.orEmpty())
            } else {
                FilledField(stringResource(R.string.form_plan_activo), inv.holding(activo)?.trimmedName ?: stringResource(R.string.form_plan_elige_uno), trailing = StmIcons.arrowDropDown, onClick = { selector = "activo" })
            }
            FilledField(stringResource(R.string.comun_importe), importe, { importe = it }, keyboard = KeyboardType.Decimal, suffix = "€", autoFocus = editando == null, calculator = true)
            FilledField(stringResource(R.string.comun_cada), recurrencia.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "cada" })
            FilledField(stringResource(R.string.form_plan_sale_de), finance.account(cuenta)?.name ?: stringResource(R.string.form_activo_ninguna_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField(stringResource(R.string.form_plan_primera_aportacion), Fechas.largo(inicio, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
            FilledField(stringResource(R.string.form_plan_aviso), avisos.first { it.first == aviso }.second, trailing = StmIcons.arrowDropDown, onClick = { selector = "aviso" })
            FilledField(stringResource(R.string.form_plan_rentabilidad_anual_supuesta), rentabilidad, { rentabilidad = it }, keyboard = KeyboardType.Decimal, suffix = "%")
            val proyeccion = borrador?.takeIf { it.issue == null }?.let {
                stringResource(R.string.form_plan_si_rinde_un_al_ano_lo, rentabilidad, Money.format(it.projectedValue(12)), Money.format(it.projectedValue(60)))
            } ?: stringResource(R.string.form_plan_la_rentabilidad_supuesta_solo)
            Text(proyeccion, style = StmType.bodySmall, color = c.onSurfaceVariant)
            if (editando != null) Btn(stringResource(R.string.form_plan_borrar_plan), { borrando = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
        }
    }
    if (eligeFecha) SelectorFecha(inicio, { inicio = it }) { eligeFecha = false }
}
