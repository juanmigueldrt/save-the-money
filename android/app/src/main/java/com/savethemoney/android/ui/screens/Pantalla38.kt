package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** Apuntar un score. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla38(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val tracking = finance.tracking
    val ultimo = remember { tracking.latestScore }
    var score by rememberSaveable { mutableStateOf("") }
    var escala by rememberSaveable { mutableIntStateOf(ultimo?.maxScore ?: 850) }
    var proveedor by rememberSaveable { mutableStateOf(ultimo?.trimmedProvider.orEmpty()) }
    var fecha by rememberSaveable { mutableStateOf(finance.today()) }
    var nota by rememberSaveable { mutableStateOf("") }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeEscala by remember { mutableStateOf(false) }
    val action = rememberAction()
    val resources = LocalResources.current

    fun guardar() = action.run {
        val valor = score.trim().toIntOrNull() ?: throw AppError.InvalidInput(resources.getString(R.string.apuntar_score_escribe_el_score_con_numeros))
        tracking.add(CreditScore("", valor, escala, proveedor, fecha.toString(), nota))
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(stringResource(R.string.apuntar_score_apuntar_score), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeEscala) {
            { SelectorSheet(stringResource(R.string.apuntar_score_escala), listOf(850, 900, 999, 1000, 100).map { e -> stringResource(R.string.apuntar_score_sobre, e) to { escala = e } }) { eligeEscala = false } }
        } else {
            null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.apuntar_score_score), score, { score = it }, keyboard = KeyboardType.Number, autoFocus = true)
            FilledField(stringResource(R.string.apuntar_score_escala), stringResource(R.string.apuntar_score_sobre, escala), trailing = StmIcons.arrowDropDown, onClick = { eligeEscala = true })
            FilledField(stringResource(R.string.apuntar_score_proveedor_opcional), proveedor, { proveedor = it })
            FilledField(stringResource(R.string.comun_fecha), Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField(stringResource(R.string.comun_nota_opcional), nota, { nota = it })
            Text(stringResource(R.string.apuntar_score_solo_lo_ves_tu_no_se), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(finance.today())) fecha = it }) { eligeFecha = false }
}
