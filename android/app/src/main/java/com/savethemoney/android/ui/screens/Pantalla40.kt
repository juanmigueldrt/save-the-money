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
    val resources = LocalResources.current

    fun guardar() = action.run {
        val valor = parseDecimal(precio, maxFractionDigits = 6)?.takeIf { it.signum() > 0 } ?: throw AppError.InvalidInput(resources.getString(R.string.form_activo_escribe_el_precio_con_coma_para))
        inv.recordPrice(valor, fecha, h)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(stringResource(R.string.apuntar_precio_apuntar_precio), navIcon = StmIcons.close, onNav = nav::back) { Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text) }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.apuntar_precio_precio_por_participacion), precio, { precio = it }, keyboard = KeyboardType.Decimal, autoFocus = true)
            FilledField(stringResource(R.string.comun_fecha), Fechas.largo(fecha, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
            Aviso(stringResource(R.string.apuntar_precio_si_ya_habias_apuntado_un_precio))
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(hoy)) fecha = it }) { eligeFecha = false }
}
