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
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction

/** Apuntar el precio de un día. */
@Composable
fun Pantalla40(nav: Nav, holdingId: String) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val h = inv.holding(holdingId) ?: return NoEncontrado(nav)
    val hoy = finance.today()
    var precio by rememberSaveable { mutableStateOf(h.price.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var fecha by rememberSaveable { mutableStateOf(hoy) }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()

    fun guardar() = action.run {
        val valor = parseDecimal(precio, maxFractionDigits = 6)?.takeIf { it.signum() > 0 } ?: throw AppError.InvalidInput("Escribe el precio con coma para los decimales, p. ej. 12,50.")
        inv.recordPrice(valor, fecha, h)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Apuntar precio", navIcon = StmIcons.close, onNav = nav::back) { Btn("Guardar", ::guardar, kind = BtnKind.Text) }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Precio por participación", precio, { precio = it }, keyboard = KeyboardType.Decimal, autoFocus = true)
            FilledField("Fecha", Fechas.largo(fecha, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
            Aviso("Si ya habías apuntado un precio ese día, se sustituye.")
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(hoy)) fecha = it }) { eligeFecha = false }
}
