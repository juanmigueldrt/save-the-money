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
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.TradeCash
import com.savethemoney.android.data.TradeSide
import com.savethemoney.android.data.parseDecimal
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

/** Apuntar una venta. */
@Composable
fun Pantalla41(nav: Nav, holdingId: String) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val h = inv.holding(holdingId) ?: return NoEncontrado(nav)
    val hoy = finance.today()
    val tienes = inv.position(h).quantity
    var cantidad by rememberSaveable { mutableStateOf("") }
    var precio by rememberSaveable { mutableStateOf(InvestmentText.plain(h.price)) }
    var comision by rememberSaveable { mutableStateOf("") }
    var fecha by rememberSaveable { mutableStateOf(hoy) }
    var cuenta by rememberSaveable { mutableStateOf(h.accountId) }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeCuenta by remember { mutableStateOf(false) }
    // Uno por formulario: reintentar tras un fallo no duplica la venta.
    val idVenta = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val action = rememberAction()

    fun guardar() = action.run {
        val unidades = parseDecimal(cantidad)
        val valor = parseDecimal(precio, maxFractionDigits = 6)
        if (unidades == null || valor == null) throw AppError.InvalidInput("Escribe las participaciones y el precio con coma para los decimales, p. ej. 0,125.")
        val fee = if (comision.isBlank()) 0L else Money.entered(comision)?.takeIf { it >= 0 } ?: throw AppError.InvalidInput("Escribe la comisión con números.")
        val trade = InvestmentTrade(idVenta, h.householdId, h.id, fecha.toString(), TradeSide.Sell, unidades, valor, fee)
        finance.addTrade(trade, cuenta?.let { TradeCash(it, null, trade.cashImpact, "Venta de ${h.trimmedName}") })
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Vender", navIcon = StmIcons.close, onNav = nav::back) { Btn("Guardar", ::guardar, kind = BtnKind.Text) }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeCuenta) {
            {
                SelectorSheet(
                    "Ingresar en",
                    listOf<Pair<String, () -> Unit>>(SIN_CUENTA to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                ) { eligeCuenta = false }
            }
        } else {
            null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Participaciones (tienes ${InvestmentText.quantity(tienes)})", cantidad, { cantidad = it }, keyboard = KeyboardType.Decimal, autoFocus = true)
            FilledField("Precio por participación", precio, { precio = it }, keyboard = KeyboardType.Decimal)
            FilledField("Comisión en € (opcional)", comision, { comision = it }, keyboard = KeyboardType.Decimal)
            FilledField("Fecha", Fechas.largo(fecha, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
            FilledField("Ingresar en", finance.account(cuenta)?.name ?: SIN_CUENTA, trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true })
            Aviso("Si eliges una cuenta, se apunta allí lo que recibes.")
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(hoy)) fecha = it }) { eligeFecha = false }
}
