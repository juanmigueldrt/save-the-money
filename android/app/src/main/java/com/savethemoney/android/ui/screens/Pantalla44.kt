package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.PayFrequency
import com.savethemoney.android.data.PaySchedule
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo

/** 44 Día de cobro: de ahí salen los periodos del presupuesto. Sólo lo ve quien lo guarda. */
@Composable
fun Pantalla44(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val actual = budgets.schedule
    val hoy = finance.today()
    var frecuencia by rememberSaveable { mutableStateOf(actual.frequency) }
    var dia1 by rememberSaveable { mutableStateOf(actual.day1) }
    var dia2 by rememberSaveable { mutableStateOf(actual.day2 ?: maxOf(15, actual.day1 + 1)) }
    var ancla by rememberSaveable { mutableStateOf(actual.anchor ?: hoy) }
    var eligiendo by remember { mutableStateOf(false) }
    var eligeFecha by remember { mutableStateOf(false) }
    val schedule = PaySchedule(
        frecuencia, dia1, if (frecuencia == PayFrequency.TwiceMonthly) dia2 else null, if (frecuencia.usesAnchor) ancla else null,
    )
    val guardar = {
        action.run {
            schedule.issue?.let { throw AppError.InvalidInput(it) }
            budgets.save(schedule)
            nav.back()
        }
    }
    StmScreen(
        topBar = {
            TopBar(stringResource(R.string.dia_de_cobro_dia_de_cobro), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            { SelectorSheet(stringResource(R.string.dia_de_cobro_cobro), PayFrequency.entries.map { f -> stringResource(f.titulo) to { frecuencia = f } }, { eligiendo = false }) }
        } else null,
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.dia_de_cobro_cobro), stringResource(frecuencia.titulo), trailing = StmIcons.arrowDropDown, onClick = { eligiendo = true })
            when (frecuencia) {
                PayFrequency.Monthly -> FilaDia(stringResource(R.string.dia_de_cobro_el_dia, dia1), { dia1 = (dia1 - 1).coerceAtLeast(1) }, { dia1 = (dia1 + 1).coerceAtMost(31) })
                PayFrequency.TwiceMonthly -> {
                    FilaDia(stringResource(R.string.dia_de_cobro_primer_dia, dia1), { dia1 = (dia1 - 1).coerceAtLeast(1) }, { dia1 = (dia1 + 1).coerceAtMost(30) })
                    FilaDia(stringResource(R.string.dia_de_cobro_segundo_dia, dia2), { dia2 = (dia2 - 1).coerceAtLeast(2) }, { dia2 = (dia2 + 1).coerceAtMost(31) })
                }
                else -> FilledField(
                    stringResource(R.string.dia_de_cobro_un_dia_que_cobraste), Fechas.largo(ancla, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true },
                )
            }
            Text(
                stringResource(R.string.dia_de_cobro_el_presupuesto_va_de_un_cobro),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            val issue = schedule.issue
            if (issue != null) {
                Text(issue, style = StmType.bodySmall, color = c.error)
            } else {
                val periodo = schedule.period(hoy)
                ListCard {
                    ListHeader(stringResource(R.string.dia_de_cobro_periodo_de_hoy))
                    ListItem(stringResource(R.string.dia_de_cobro_del), trailingText = Fechas.largo(periodo.start, hoy))
                    Divider()
                    ListItem(stringResource(R.string.dia_de_cobro_al), trailingText = Fechas.largo(periodo.end, hoy))
                }
            }
        }
    }
    if (eligeFecha) SelectorFecha(ancla, { ancla = it }) { eligeFecha = false }
}

@Composable
private fun FilaDia(texto: String, menos: () -> Unit, mas: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.dia_de_cobro_dia_de_cobro), Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
        Stepper(texto, menos, mas)
    }
}
