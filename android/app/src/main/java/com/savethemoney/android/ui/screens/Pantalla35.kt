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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
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

    fun guardar() = action.run {
        val dinero = Money.entered(amount)?.takeIf { it > 0 } ?: throw AppError.InvalidInput("El importe no es válido.")
        planning.contribute(if (sacar) -dinero else dinero, goal, fecha, nota, idAportacion)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (ahorro) "Aportación" else "Pago de la deuda", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Importe", amount, { amount = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            if (ahorro) {
                ListCard {
                    ListItem("Sacar dinero de la meta", trailing = { StmSwitch(sacar) { sacar = it } })
                }
            }
            FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField("Nota (opcional)", nota, { nota = it })
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}
