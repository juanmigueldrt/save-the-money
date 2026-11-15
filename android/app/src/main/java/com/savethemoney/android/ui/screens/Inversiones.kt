package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.AssetClass
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.BuyQuote
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.ChartRange
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurrenceUnit
import com.savethemoney.android.data.TradeSide
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Donut
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.math.BigDecimal
import java.time.Instant
import java.time.YearMonth

private const val SIN_CUENTA = "No apuntar en ninguna cuenta"

@Composable
private fun AssetClass.color(): Color {
    val c = Stm.colors
    return when (this) {
        AssetClass.Equity -> c.primary
        AssetClass.FixedIncome -> c.tertiary
        AssetClass.Crypto -> c.success
        AssetClass.Cash -> c.secondaryContainer
        AssetClass.Other -> c.outline
    }
}

private fun iconoActivo(kind: InvestmentKind) = if (kind == InvestmentKind.Bond) StmIcons.accountBalance else StmIcons.public

@Composable
private fun Aviso(text: String) = Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)

/** 25 Cartera: total, rentabilidad, evolución, reparto y activos. */
@Composable
fun Pantalla25(nav: Nav) {
    val session = LocalSession.current
    if (session.capture) return Diseno25(nav)
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    var range by remember { mutableIntStateOf(1) }
    var eligiendo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        inv.load()
        inv.loadMembers(session.backend)
    }
    val rangos = listOf(ChartRange.Week, ChartRange.Month, ChartRange.Year, ChartRange.All)
    val cartera = inv.portfolio
    val nuevo = {
        inv.holdingToEdit = null
        nav.go(39)
    }
    StmScreen(
        topBar = {
            MediumTopBar("Cartera", onBack = nav::back) {
                IconBtn(StmIcons.eventRepeat, { nav.go(27) }, contentDescription = "Inversiones recurrentes")
                IconBtn(StmIcons.add, { if (inv.activeHoldings.isEmpty()) nuevo() else eligiendo = true }, contentDescription = "Comprar")
            }
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = inv.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            {
                SelectorSheet(
                    "Comprar activo",
                    inv.activeHoldings.map { h ->
                        h.trimmedName to {
                            inv.selectedId = h.id
                            nav.go(26)
                        }
                    } + ("Añadir otro activo" to nuevo),
                ) { eligiendo = false }
            }
        } else {
            null
        },
    ) {
        Spacer(Modifier.height(7.5.dp))
        Text(euros(cartera.value), style = StmType.displaySmall, color = c.onSurface)
        if (cartera.cost > 0) {
            Spacer(Modifier.height(4.5.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val texto = euros(cartera.gain, signed = true) + (cartera.gainFraction?.let { " (${InvestmentText.percent(it)})" } ?: "")
                Pill(texto, positive = cartera.gain >= 0, icon = if (cartera.gain >= 0) StmIcons.arrowUpward else null)
                Spacer(Modifier.width(8.dp))
                Text("desde el inicio", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(20.dp))
        if (inv.activeHoldings.isEmpty()) {
            StmCard {
                Text("Sin inversiones todavía", style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Añade un fondo, un ETF o una acción y apunta tus compras. Los precios los apuntas tú cuando quieras; la app no se conecta a ningún bróker.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                Btn("Añadir un activo", nuevo)
            }
        } else {
            HugSegmented(rangos.map { it.title }, range) { range = it }
            Spacer(Modifier.height(16.dp))
            StmCard { LineChart(normalizar(inv.evolution(rangos[range]).map { it.value })) }
            if (cartera.allocation.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                val colores = cartera.allocation.map { it.assetClass.color() }
                StmCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Donut(cartera.allocation.mapIndexed { i, s -> Slice(s.fraction.toFloat(), colores[i]) }, 112.dp, 16.dp)
                        Spacer(Modifier.width(16.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            cartera.allocation.forEachIndexed { i, s -> Legend(colores[i], "${s.assetClass.title} ${Math.round(s.fraction * 100)} %") }
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            ListCard {
                inv.activeHoldings.forEachIndexed { i, h ->
                    if (i > 0) Divider()
                    val p = inv.position(h)
                    val base = if (p.quantity.signum() > 0) "${InvestmentText.quantity(p.quantity)} participaciones" else h.kind.title
                    ListItem(
                        h.trimmedName, if (h.ownerId != null) "$base · ${inv.ownerName(h.ownerId)}" else base,
                        leading = { LeadIcon(iconoActivo(h.kind), c.tertiaryContainer, c.onTertiaryContainer) },
                        trailing = {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(euros(p.value), style = StmType.labelLarge, color = c.onSurface)
                                p.gainFraction?.let { Text(InvestmentText.percent(it), style = StmType.bodySmall, color = c.onSurfaceVariant) }
                            }
                        },
                        onClick = {
                            inv.selectedId = h.id
                            nav.go(26)
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Aviso("Esto no es asesoramiento de inversión. Los valores salen de los precios que apuntas a mano.")
    }
}

/** 26 Activo: precio, evolución, posición, compra y operaciones. */
@Composable
fun Pantalla26(nav: Nav) {
    val session = LocalSession.current
    if (session.capture) return Diseno26(nav)
    val finance = session.finance ?: return
    val inv = finance.investments
    val h = inv.selected ?: return run {
        StmScreen(topBar = { TopBar("Activo", onNav = nav::back) }) { Aviso("Este activo ya no existe.") }
    }
    val c = Stm.colors
    val hoy = finance.today()
    val p = inv.position(h)
    var mode by remember { mutableIntStateOf(0) }
    var amount by remember { mutableStateOf("") }
    var fee by remember(h.id) { mutableStateOf(InvestmentText.plain(h.feeRate)) }
    var cuenta by remember(h.id) { mutableStateOf(h.accountId) }
    var fecha by remember { mutableStateOf(hoy) }
    var repetir by remember { mutableStateOf(false) }
    var hecho by remember { mutableStateOf<String?>(null) }
    var eligeCuenta by remember { mutableStateOf(false) }
    var eligeFecha by remember { mutableStateOf(false) }
    var borrando by remember { mutableStateOf<InvestmentTrade?>(null) }
    val action = rememberAction()
    val tasa = if (fee.isBlank()) BigDecimal.ZERO else parseDecimal(fee)
    val quote = tasa?.let { t ->
        if (mode == 0) Money.parse(amount)?.let { BuyQuote.byAmount(it, h.price, t) } else parseDecimal(amount)?.let { BuyQuote.byQuantity(it, h.price, t) }
    }

    fun comprar(q: BuyQuote) = action.run {
        hecho = null
        inv.add(q.trade(h, h.price, fecha))
        cuenta?.let { id ->
            val ahorro = finance.categories.firstOrNull { it.kind == CategoryKind.Expense && it.budgetGroup == BudgetGroup.Savings }
            finance.add(MovementDraft(id, ahorro?.id, fecha, -q.total, "Compra de ${h.trimmedName}"))
        }
        if (repetir) inv.save(InvestmentPlan("", h.householdId, h.id, cuenta, q.amount, startsOn = fecha.plusMonths(1).toString()))
        amount = ""
        repetir = false
        hecho = "Compra apuntada: ${InvestmentText.quantity(q.quantity)} participaciones."
    }

    StmScreen(
        topBar = {
            TopBar(h.trimmedName, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    inv.holdingToEdit = h
                    nav.go(39)
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
            Btn("Apuntar precio", { nav.go(40) }, Modifier.fillMaxWidth(), kind = BtnKind.Outlined)
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
                    if (p.quantity.signum() > 0) Btn("Vender", { nav.go(41) }, kind = BtnKind.Text)
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

/** 27 Inversiones recurrentes: calendario del mes con los días de aportación y planes. */
@Composable
fun Pantalla27(nav: Nav) {
    val session = LocalSession.current
    if (session.capture) return Diseno27(nav)
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val hoy = finance.today()
    val mes = YearMonth.from(hoy)
    val cargos = inv.charges(mes)
    val diasConCargo = cargos.map { it.due.dayOfMonth }.toSet()
    val action = rememberAction()
    val nuevo = {
        inv.planToEdit = null
        nav.go(42)
    }
    StmScreen(
        topBar = {
            TopBar("Inversiones recurrentes", onNav = nav::back) {
                if (inv.activeHoldings.isNotEmpty()) IconBtn(StmIcons.add, nuevo, contentDescription = "Añadir")
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        StmCard {
            Text(Fechas.mesTitulo(hoy), style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                    Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) {
                        Text(it, style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            val hueco = mes.atDay(1).dayOfWeek.value - 1
            val dias = List<Int?>(hueco) { null } + (1..mes.lengthOfMonth()).toList()
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                dias.chunked(7).forEach { semana ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        (semana + List(7 - semana.size) { null }).forEach { dia ->
                            val (bg, fg) = when (dia) {
                                hoy.dayOfMonth -> c.primary to c.onPrimary
                                in diasConCargo -> c.secondaryContainer to c.onSecondaryContainer
                                else -> Color.Transparent to c.onSurface
                            }
                            Box(Modifier.size(40.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
                                if (dia != null) Text("$dia", style = StmType.bodyMedium, color = fg)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        val (activos, pausados) = inv.planCounts
        val planes = (if (activos == 1) "1 plan activo" else "$activos planes activos") + if (pausados > 0) " y $pausados en pausa" else ""
        Aviso("${Money.format(inv.monthlyPlanned)} al mes en $planes")
        Spacer(Modifier.height(16.dp))
        if (inv.livePlans.isNotEmpty()) {
            ListCard {
                inv.livePlans.forEachIndexed { i, plan ->
                    if (i > 0) Divider()
                    val h = inv.holding(plan.holdingId)
                    val cuando = if (plan.unit == RecurrenceUnit.Month && plan.every == 1) "el día ${plan.startDay.dayOfMonth} de cada mes" else plan.recurrence.title.lowercase()
                    ListItem(
                        h?.trimmedName ?: "Activo", "${euros(plan.amountMinor)} $cuando" + if (plan.isPaused) " · en pausa" else "",
                        leading = {
                            if (plan.isPaused) LeadIcon(iconoActivo(h?.kind ?: InvestmentKind.Fund), c.surfaceContainerHighest, c.onSurfaceVariant)
                            else LeadIcon(iconoActivo(h?.kind ?: InvestmentKind.Fund), c.tertiaryContainer, c.onTertiaryContainer)
                        },
                        trailing = { StmSwitch(!plan.isPaused) { on -> action.run { inv.setPaused(!on, plan) } } },
                        onClick = {
                            inv.planToEdit = plan
                            nav.go(42)
                        },
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
        } else if (inv.activeHoldings.isEmpty()) {
            Aviso("Añade antes un activo en la cartera.")
            Spacer(Modifier.height(16.dp))
        } else {
            Btn("Nuevo plan", nuevo, Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
        }
        if (cargos.isNotEmpty()) {
            ListCard {
                ListHeader("Este mes")
                cargos.forEachIndexed { i, cargo ->
                    if (i > 0) Divider()
                    ListItem(Fechas.dia(cargo.due, hoy), inv.holding(cargo.plan.holdingId)?.trimmedName, trailingText = euros(cargo.plan.amountMinor))
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        Aviso("Un plan no compra nada solo: te avisa el día que toca y tú confirmas la compra en la app.")
    }
}

/** Crear o editar un activo. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla39(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val editando = remember { inv.takeHoldingToEdit() }
    var nombre by remember { mutableStateOf(editando?.name.orEmpty()) }
    var simbolo by remember { mutableStateOf(editando?.symbol.orEmpty()) }
    var tipo by remember { mutableStateOf(editando?.kind ?: InvestmentKind.Fund) }
    var clase by remember { mutableStateOf(editando?.assetClass ?: AssetClass.Equity) }
    var dueno by remember { mutableStateOf(editando?.ownerId) }
    var cuenta by remember { mutableStateOf(editando?.accountId) }
    var precio by remember { mutableStateOf(editando?.price?.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var comision by remember { mutableStateOf(editando?.feeRate?.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var nota by remember { mutableStateOf(editando?.note.orEmpty()) }
    var selector by remember { mutableStateOf<String?>(null) }
    var borrando by remember { mutableStateOf(false) }
    val action = rememberAction()

    fun guardar() = action.run {
        val valor = if (precio.isBlank()) BigDecimal.ZERO else parseDecimal(precio) ?: throw AppError.InvalidInput("Escribe el precio con números, p. ej. 12,50.")
        val tasa = if (comision.isBlank()) BigDecimal.ZERO else parseDecimal(comision) ?: throw AppError.InvalidInput("Escribe la comisión con números, p. ej. 0,2.")
        val hoy = finance.today()
        val cambiaPrecio = editando?.let { it.price.compareTo(valor) != 0 } ?: (valor.signum() > 0)
        val base = editando ?: Holding(
            "", inv.householdId, nombre, price = valor, priceOn = if (valor.signum() > 0) hoy.toString() else null,
        )
        val item = base.copy(
            name = nombre, symbol = simbolo, kind = tipo, assetClass = clase, ownerId = dueno, accountId = cuenta, feeRate = tasa,
            note = nota.trim().ifEmpty { null },
        )
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = inv.save(item)
        // Un precio nuevo también queda en el histórico, para el gráfico.
        if (cambiaPrecio && valor.signum() > 0) inv.recordPrice(valor, hoy, saved)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando == null) "Nuevo activo" else "Editar activo", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            borrando -> {
                {
                    BottomSheet(
                        "¿Borrar este activo?", "Se borran también sus precios, operaciones y aportaciones automáticas, para todo el hogar. No se puede deshacer.",
                        onDismiss = { borrando = false },
                    ) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn("Cancelar", { borrando = false }, kind = BtnKind.Text)
                            Btn("Borrar activo", {
                                action.run {
                                    inv.delete(editando!!)
                                    nav.back()
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
                        "tipo" -> SelectorSheet("Tipo", InvestmentKind.entries.map { k ->
                            k.title to {
                                tipo = k
                                if (editando == null) clase = k.defaultAssetClass
                            }
                        }, cerrar)
                        "clase" -> SelectorSheet("Clase", AssetClass.entries.map { a -> a.title to { clase = a } }, cerrar)
                        "dueno" -> SelectorSheet("De quién es", listOf<Pair<String, () -> Unit>>("Compartido" to { dueno = null }) + inv.members.map { m -> m.profile.name to { dueno = m.profile.id } }, cerrar)
                        else -> SelectorSheet("Dónde está", listOf<Pair<String, () -> Unit>>("Ninguna cuenta" to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Nombre", nombre, { nombre = it }, autoFocus = editando == null)
            FilledField("Ticker o ISIN (opcional)", simbolo, { simbolo = it })
            FilledField("Tipo", tipo.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "tipo" })
            FilledField("Clase", clase.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "clase" })
            FilledField("Precio actual por participación", precio, { precio = it }, keyboard = KeyboardType.Decimal)
            FilledField("Comisión de compra en %", comision, { comision = it }, keyboard = KeyboardType.Decimal)
            Text("El precio lo apuntas tú: búscalo en tu bróker o banco cuando quieras actualizarlo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            FilledField("De quién es", inv.ownerName(dueno), trailing = StmIcons.arrowDropDown, onClick = { selector = "dueno" })
            FilledField("Dónde está", finance.account(cuenta)?.name ?: "Ninguna cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField("Nota (opcional)", nota, { nota = it })
            Text("Todo el hogar ve las inversiones, como las cuentas.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            if (editando != null) {
                Btn(if (editando.isArchived) "Desarchivar" else "Archivar", {
                    action.run {
                        inv.save(editando.copy(archivedAt = if (editando.isArchived) null else Instant.now().toString()))
                        nav.back()
                    }
                }, Modifier.fillMaxWidth(), kind = BtnKind.Outlined)
                Btn("Borrar activo y sus operaciones", { borrando = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
            }
        }
    }
}

/** Apuntar el precio de un día. */
@Composable
fun Pantalla40(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val h = inv.selected ?: return
    val hoy = finance.today()
    var precio by remember { mutableStateOf(h.price.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var fecha by remember { mutableStateOf(hoy) }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()

    fun guardar() = action.run {
        val valor = parseDecimal(precio)?.takeIf { it.signum() > 0 } ?: throw AppError.InvalidInput("Escribe el precio con números, p. ej. 12,50.")
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

/** Apuntar una venta. */
@Composable
fun Pantalla41(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val h = inv.selected ?: return
    val hoy = finance.today()
    val tienes = inv.position(h).quantity
    var cantidad by remember { mutableStateOf("") }
    var precio by remember { mutableStateOf(InvestmentText.plain(h.price)) }
    var comision by remember { mutableStateOf("") }
    var fecha by remember { mutableStateOf(hoy) }
    var cuenta by remember { mutableStateOf(h.accountId) }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeCuenta by remember { mutableStateOf(false) }
    val action = rememberAction()

    fun guardar() = action.run {
        val unidades = parseDecimal(cantidad)
        val valor = parseDecimal(precio)
        if (unidades == null || valor == null) throw AppError.InvalidInput("Escribe las participaciones y el precio con números.")
        val fee = if (comision.isBlank()) 0L else Money.parse(comision)?.takeIf { it >= 0 } ?: throw AppError.InvalidInput("Escribe la comisión con números.")
        val trade = InvestmentTrade("", h.householdId, h.id, fecha.toString(), TradeSide.Sell, unidades, valor, fee)
        inv.add(trade)
        cuenta?.let { finance.add(MovementDraft(it, null, fecha, trade.cashImpact, "Venta de ${h.trimmedName}")) }
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

/** Crear o editar un plan de aportación. */
@Composable
fun Pantalla42(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val hoy = finance.today()
    val editando = remember { inv.takePlanToEdit() }
    var activo by remember { mutableStateOf(editando?.holdingId ?: inv.activeHoldings.firstOrNull()?.id) }
    var importe by remember { mutableStateOf(editando?.let { Money.format(it.amountMinor, symbol = false) }.orEmpty()) }
    var recurrencia by remember { mutableStateOf(editando?.recurrence ?: Recurrence.Monthly) }
    var cuenta by remember { mutableStateOf(editando?.accountId) }
    var inicio by remember { mutableStateOf(editando?.startDay ?: hoy) }
    var rentabilidad by remember { mutableStateOf(editando?.let { InvestmentText.plain(it.expectedAnnualReturn) } ?: "5") }
    var aviso by remember { mutableStateOf(if (editando != null) editando.remindDaysBefore else 1) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    var borrando by remember { mutableStateOf(false) }
    val action = rememberAction()

    val borrador = run {
        val id = activo
        val money = Money.parse(importe)
        val rate = parseDecimal(rentabilidad)
        if (id == null || money == null || rate == null) null
        else (editando ?: InvestmentPlan("", inv.householdId, id, amountMinor = money, startsOn = inicio.toString())).copy(
            amountMinor = money, every = recurrencia.every, unit = recurrencia.unit, accountId = cuenta, startsOn = inicio.toString(),
            expectedAnnualReturn = rate, remindDaysBefore = aviso,
        )
    }

    fun guardar() = action.run {
        if (activo == null) throw AppError.InvalidInput("Elige un activo.")
        val item = borrador ?: throw AppError.InvalidInput("Escribe el importe y la rentabilidad con números.")
        item.issue?.let { throw AppError.InvalidInput(it) }
        inv.save(item)
        nav.back()
    }

    val avisos = listOf(null to "Sin aviso", 0 to "El mismo día", 1 to "1 día antes", 3 to "3 días antes")
    StmScreen(
        topBar = {
            TopBar(if (editando == null) "Nuevo plan" else "Editar plan", navIcon = StmIcons.close, onNav = nav::back) {
                Btn(if (editando == null) "Crear" else "Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            borrando -> {
                {
                    BottomSheet("¿Borrar este plan?", "Las compras que ya apuntaste no se borran.", onDismiss = { borrando = false }) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn("Cancelar", { borrando = false }, kind = BtnKind.Text)
                            Btn("Borrar plan", {
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
                        "activo" -> SelectorSheet("Activo", inv.activeHoldings.map { h -> h.trimmedName to { activo = h.id } }, cerrar)
                        "cada" -> SelectorSheet("Cada", Recurrence.Common.map { r -> r.title to { recurrencia = r } }, cerrar)
                        "aviso" -> SelectorSheet("Aviso", avisos.map { (d, t) -> t to { aviso = d } }, cerrar)
                        else -> SelectorSheet("Sale de", listOf<Pair<String, () -> Unit>>("Ninguna cuenta" to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
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
                    DataRow(if (editando.isPaused) "Estado" else "Próxima", if (editando.isPaused) "En pausa" else editando.nextDue(hoy)?.let { Fechas.dia(it, hoy) } ?: "Terminado")
                    Spacer(Modifier.height(8.dp))
                    DataRow("Invertido con el plan", Money.format(editando.invested(inv.trades, hoy)))
                    Spacer(Modifier.height(8.dp))
                    DataRow("Rentabilidad del activo", posicion?.gainFraction?.let(InvestmentText::percent) ?: "—")
                }
            }
            if (editando != null) {
                FilledField("Activo", inv.holding(activo)?.trimmedName.orEmpty())
            } else {
                FilledField("Activo", inv.holding(activo)?.trimmedName ?: "Elige uno", trailing = StmIcons.arrowDropDown, onClick = { selector = "activo" })
            }
            FilledField("Importe", importe, { importe = it }, keyboard = KeyboardType.Decimal, suffix = "€", autoFocus = editando == null)
            FilledField("Cada", recurrencia.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "cada" })
            FilledField("Sale de", finance.account(cuenta)?.name ?: "Ninguna cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField("Primera aportación", Fechas.largo(inicio, hoy), trailing = StmIcons.arrowDropDown, onClick = { eligeFecha = true })
            FilledField("Aviso", avisos.first { it.first == aviso }.second, trailing = StmIcons.arrowDropDown, onClick = { selector = "aviso" })
            FilledField("Rentabilidad anual supuesta", rentabilidad, { rentabilidad = it }, keyboard = KeyboardType.Decimal, suffix = "%")
            val proyeccion = borrador?.takeIf { it.issue == null }?.let {
                "Si rinde un $rentabilidad % al año, lo aportado en 1 año valdría unos ${Money.format(it.projectedValue(12))} y en 5 años unos ${Money.format(it.projectedValue(60))}. Es una estimación, no una promesa."
            } ?: "La rentabilidad supuesta sólo sirve para la proyección."
            Text(proyeccion, style = StmType.bodySmall, color = c.onSurfaceVariant)
            if (editando != null) Btn("Borrar plan", { borrando = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
        }
    }
    if (eligeFecha) SelectorFecha(inicio, { inicio = it }) { eligeFecha = false }
}
