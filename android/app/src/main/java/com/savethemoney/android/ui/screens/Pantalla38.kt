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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
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

    fun guardar() = action.run {
        val valor = score.trim().toIntOrNull() ?: throw AppError.InvalidInput("Escribe el score con números.")
        tracking.add(CreditScore("", valor, escala, proveedor, fecha.toString(), nota))
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Apuntar score", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeEscala) {
            { SelectorSheet("Escala", listOf(850, 900, 999, 1000, 100).map { e -> "Sobre $e" to { escala = e } }) { eligeEscala = false } }
        } else {
            null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Score", score, { score = it }, keyboard = KeyboardType.Number, autoFocus = true)
            FilledField("Escala", "Sobre $escala", trailing = StmIcons.arrowDropDown, onClick = { eligeEscala = true })
            FilledField("Proveedor (opcional)", proveedor, { proveedor = it })
            FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField("Nota (opcional)", nota, { nota = it })
            Text("Sólo lo ves tú. No se comparte con el hogar.", style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(finance.today())) fecha = it }) { eligeFecha = false }
}
