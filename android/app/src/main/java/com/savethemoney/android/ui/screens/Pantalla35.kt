package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction

/** Aportación o pago de una deuda. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla35(nav: Nav, goalId: String) {
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val goal = planning.goal(goalId) ?: return NoEncontrado(nav)
    var amount by rememberSaveable { mutableStateOf("") }
    var sacar by rememberSaveable { mutableStateOf(false) }
    var fecha by rememberSaveable { mutableStateOf(finance.today()) }
    var nota by rememberSaveable { mutableStateOf("") }
    var eligeFecha by remember { mutableStateOf(false) }
    // Identificador de la aportación, uno por formulario: reintentarla con el mismo no la apunta dos veces.
    val idAportacion = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val action = rememberAction()
    val ahorro = goal.kind == GoalKind.Savings
    val resources = LocalResources.current

    fun guardar() = action.run {
        val dinero = Money.entered(amount)?.takeIf { it > 0 } ?: throw AppError.InvalidInput(resources.getString(R.string.comun_el_importe_no_es_valido))
        planning.contribute(if (sacar) -dinero else dinero, goal, fecha, nota, idAportacion)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (ahorro) stringResource(R.string.aportar_aportacion) else stringResource(R.string.aportar_pago_de_la_deuda), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.comun_importe), amount, { amount = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            if (ahorro) {
                ListCard {
                    ListItem(stringResource(R.string.aportar_sacar_dinero_de_la_meta), trailing = { StmSwitch(sacar) { sacar = it } })
                }
            }
            FilledField(stringResource(R.string.comun_fecha), Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField(stringResource(R.string.comun_nota_opcional), nota, { nota = it })
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}
