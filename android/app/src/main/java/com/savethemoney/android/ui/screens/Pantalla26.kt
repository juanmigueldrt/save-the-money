package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.BuyQuote
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.ChartRange
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.TradeCash
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.math.BigDecimal

/** 26 Activo: precio, evolución, posición, compra y operaciones. */
@Composable
fun Pantalla26(nav: Nav, holdingId: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val inv = finance.investments
    val h = inv.holding(holdingId) ?: return run {
        StmScreen(topBar = { TopBar("Activo", onNav = nav::back) }) { Aviso("Este activo ya no existe.") }
    }
    val c = Stm.colors
    val hoy = finance.today()
    val p = inv.position(h)
    var mode by rememberSaveable { mutableIntStateOf(0) }
    var amount by rememberSaveable { mutableStateOf("") }
    var fee by rememberSaveable(h.id) { mutableStateOf(InvestmentText.plain(h.feeRate)) }
    var cuenta by rememberSaveable(h.id) { mutableStateOf(h.accountId) }
    var fecha by rememberSaveable { mutableStateOf(hoy) }
    var repetir by rememberSaveable { mutableStateOf(false) }
    // Uno por compra: reintentar tras un fallo no la duplica. Se cambia al guardarla.
    var idCompra by rememberSaveable { mutableStateOf(java.util.UUID.randomUUID().toString()) }
    var hecho by remember { mutableStateOf<String?>(null) }
    var eligeCuenta by remember { mutableStateOf(false) }
    var eligeFecha by remember { mutableStateOf(false) }
    var borrando by remember { mutableStateOf<InvestmentTrade?>(null) }
    val action = rememberAction()
    val tasa = if (fee.isBlank()) BigDecimal.ZERO else parseDecimal(fee, maxFractionDigits = 3)
    val quote = tasa?.let { t ->
        if (mode == 0) Money.entered(amount)?.let { BuyQuote.byAmount(it, h.price, t) } else parseDecimal(amount)?.let { BuyQuote.byQuantity(it, h.price, t) }
    }

    fun comprar(q: BuyQuote) = action.run {
        hecho = null
        val ahorro = finance.categories.firstOrNull { it.kind == CategoryKind.Expense && it.budgetGroup == BudgetGroup.Savings }
        val cargo = cuenta?.let { TradeCash(it, ahorro?.id, -q.total, "Compra de ${h.trimmedName}") }
        val compra = q.trade(h, h.price, fecha, id = idCompra)
        finance.addTrade(compra, cargo)
        val mensual = repetir
        idCompra = java.util.UUID.randomUUID().toString()
        amount = ""
        repetir = false
        hecho = "Compra apuntada: ${InvestmentText.quantity(q.quantity)} participaciones."
        // El plan va aparte: la compra ya está guardada entera, y si el plan falla se dice solo eso.
        if (mensual) {
            try {
                // Con el id de la compra (uno por cada vez que se pulsa «Comprar»): el plan no se crea dos veces.
                inv.save(InvestmentPlan(compra.id, h.householdId, h.id, cuenta, q.amount, startsOn = fecha.plusMonths(1).toString()))
            } catch (_: AppError) {
                throw AppError.InvalidInput("La compra está apuntada, pero no se pudo crear la aportación mensual. Créala en Aportaciones automáticas.")
            }
        }
    }

    StmScreen(
        topBar = {
            TopBar(h.trimmedName, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    nav.go(Route.FormActivo(h.id))
                }, contentDescription = "Editar")
            }
        },
        snackbar = (action.error ?: inv.error)?.let { e -> { Snackbar(e) } },
        overlay = when {
            eligeCuenta -> {
                {
                    SelectorSheet(
                        "Desde",
                        listOf<Pair<String, () -> Unit>>(SIN_CUENTA to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                    ) { eligeCuenta = false }
                }
            }
            borrando != null -> {
                {
                    val t = borrando!!
                    BottomSheet("¿Borrar esta operación?", "No borra el movimiento de la cuenta, si lo había.", onDismiss = { borrando = null }) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn("Cancelar", { borrando = null }, kind = BtnKind.Text)
                            Btn("Borrar", {
                                action.run {
                                    inv.delete(t)
                                    borrando = null
                                }
                            }, kind = BtnKind.Error)
                        }
                    }
                }
            }
            else -> null
        },
    ) {
        val historia = inv.priceHistory(h, ChartRange.Year)
        val previo = historia.dropLast(1).lastOrNull()?.second
        Spacer(Modifier.height(8.dp))
        val apuntado = h.priceDay?.let { if (it == hoy) "Precio · apuntado hoy" else "Precio · apuntado el ${Fechas.corto(it)}" } ?: "Aún no has apuntado ningún precio"
        Text(apuntado, style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.5.dp))
        Text(InvestmentText.price(h.price, h.currency), style = StmType.displaySmall, color = c.onSurface)
        if (previo != null && previo.signum() > 0) {
            val cambio = h.price.toDouble() / previo.toDouble() - 1
            Spacer(Modifier.height(4.5.dp))
            Pill("${InvestmentText.percent(cambio)} desde el precio anterior", positive = cambio >= 0, icon = if (cambio >= 0) StmIcons.arrowUpward else null)
        }
        Spacer(Modifier.height(20.dp))
        if (historia.size >= 2) {
            StmCard { LineChart(normalizar(historia.map { it.second.movePointRight(6).toLong() }), plotHeight = 100.dp) }
            Spacer(Modifier.height(16.dp))
        }
        StmCard {
            Text("Tu posición", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            if (p.quantity.signum() > 0) {
                DataRow("Participaciones", InvestmentText.quantity(p.quantity))
                Spacer(Modifier.height(8.dp))
                DataRow("Precio medio", InvestmentText.price(p.averagePrice, h.currency))
                Spacer(Modifier.height(8.dp))
                DataRow("Valor", euros(p.value))
                Spacer(Modifier.height(8.dp))
                val rentabilidad = euros(p.gain, signed = true) + (p.gainFraction?.let { " (${InvestmentText.percent(it)})" } ?: "")
                DataRow("Rentabilidad", rentabilidad, if (p.gain < 0) c.error else c.success)
            } else {
                Text("Todavía no tienes participaciones. Apunta tu primera compra.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            if (p.realized != 0L) {
                Spacer(Modifier.height(8.dp))
                Aviso("Ganancia ya hecha con ventas: ${euros(p.realized, signed = true)}")
            }
            inv.yearRange(h)?.let { (min, max) ->
                Spacer(Modifier.height(8.dp))
                DataRow("Mín. 1 año", InvestmentText.price(min, h.currency))
                Spacer(Modifier.height(8.dp))
                DataRow("Máx. 1 año", InvestmentText.price(max, h.currency))
            }
            Spacer(Modifier.height(12.dp))
            Btn("Apuntar precio", { nav.go(Route.ApuntarPrecio(h.id)) }, Modifier.fillMaxWidth(), kind = BtnKind.Outlined)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Comprar", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            if (h.price.signum() <= 0) {
                Text("Apunta primero el precio de hoy para calcular la compra.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            } else {
                Segmented(listOf("Por importe", "Por participaciones"), mode, {
                    mode = it
                    amount = ""
                })
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SuffixField(if (mode == 0) "Importe" else "Participaciones", amount, { amount = it }, if (mode == 0) "€" else "uds.", Modifier.weight(1f))
                    SuffixField("Comisión", fee, { fee = it }, "%", Modifier.weight(1f))
                }
                if (quote != null) {
                    Spacer(Modifier.height(12.dp))
                    val cifra = if (mode == 0) "≈ ${InvestmentText.quantity(quote.quantity)} participaciones" else Money.format(quote.amount)
                    Aviso("$cifra · comisión ${Money.format(quote.fee)}")
                } else if (mode == 1 && amount.isNotBlank() && parseDecimal(amount) == null) {
                    Spacer(Modifier.height(12.dp))
                    Text("Escribe las participaciones con coma para los decimales, p. ej. 0,125.", style = StmType.bodySmall, color = c.error)
                }
                Spacer(Modifier.height(12.dp))
                FilledField("Desde", finance.account(cuenta)?.name ?: SIN_CUENTA, trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true })
                Spacer(Modifier.height(12.dp))
                FilledField("Fecha", Fechas.largo(fecha, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Repetir cada mes", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    StmSwitch(repetir) { repetir = it }
                }
                Spacer(Modifier.height(12.dp))
                Btn(quote?.let { "Comprar ${Money.format(it.total)}" } ?: "Comprar", { quote?.let(::comprar) }, Modifier.fillMaxWidth())
                hecho?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, style = StmType.bodyMedium, color = c.success)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        val lista = inv.trades(h)
        if (lista.isNotEmpty()) {
            ListCard {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { ListHeader("Operaciones") }
                    if (p.quantity.signum() > 0) Btn("Vender", { nav.go(Route.Vender(h.id)) }, kind = BtnKind.Text)
                }
                lista.forEachIndexed { i, t ->
                    if (i > 0) Divider()
                    val cantidad = "${t.side.title} · ${InvestmentText.quantity(t.quantity)} a ${InvestmentText.price(t.price, h.currency)}"
                    val detalle = Fechas.largo(t.day, hoy) + if (t.feeMinor > 0) " · comisión ${Money.format(t.feeMinor)}" else ""
                    ListItem(cantidad, detalle, trailingText = Money.format(t.cashImpact), onClick = { borrando = t })
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        Aviso("Esto no es asesoramiento de inversión. La compra se apunta en la app; tu bróker no recibe ninguna orden.")
    }
    if (eligeFecha) SelectorFecha(fecha, { if (!it.isAfter(hoy)) fecha = it }) { eligeFecha = false }
}
