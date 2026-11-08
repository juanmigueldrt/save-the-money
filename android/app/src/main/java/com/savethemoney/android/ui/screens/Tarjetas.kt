package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CardPayment
import com.savethemoney.android.data.CardPaymentMode
import com.savethemoney.android.data.CreditCardCalculator
import com.savethemoney.android.data.CreditCardSummary
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.MovementForm
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.SectionHeader
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate


private fun euros(minor: Long) = Money.format(minor, decimals = minor % 100 != 0L)
private fun fechaLarga(d: LocalDate) = "${d.dayOfMonth} de ${Fechas.mes(d)}"

/** "14" o "21,5", para los campos y los textos. */
private fun tasa(valor: Double) = BigDecimal(valor).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString().replace('.', ',')
private fun leerTasa(texto: String) = texto.trim().replace(',', '.').toDoubleOrNull()

/** Los intereses ya van dentro de las cuotas: se dicen aparte para que no se sumen dos veces. */
private fun desglose(p: CardPayment, modo: CardPaymentMode): String {
    val partes = buildList {
        if (p.purchases > 0) add((if (modo.isRevolving) "cuota " else "compras ") + Money.format(p.purchases))
        if (p.installments > 0) add("aplazados ${Money.format(p.installments)}")
    }
    if (partes.isEmpty()) return "Sin cargos"
    val texto = partes.joinToString(" · ")
    return if (p.interest > 0) "$texto (incluye ${Money.format(p.interest)} de intereses)" else texto
}

private fun Double.barra() = toFloat().coerceIn(0f, 1f)

private class Vista10(
    val nombre: String, val usado: String, val nota: String, val limite: String, val fraccion: Float, val alerta: Boolean,
    val disponible: String, val proximoTitulo: String, val proximo: String, val desglose: String,
)

private class Otra(val nombre: String, val detalle: String, val onClick: () -> Unit)

private val MAQUETA_10 = Vista10(
    "Visa compartida", "1.140 €", "•••• 4821", "1.140 de 3.000 €", 0.38f, false, "1.860 €", "Próximo cargo · 1 de diciembre", "312,40 €",
    "Pago total del extracto + 2 cuotas de aplazados (incluye 4,10 € de intereses). Sale de Cuenta principal.",
)

private fun vista10(cuenta: Account, s: CreditCardSummary, finance: FinanceModel): Vista10 {
    val prox = s.next
    val origen = finance.account(s.terms.payFromAccountId)?.name?.let { " Sale de $it." }.orEmpty()
    val estimado = if (prox?.isEstimate == true) " De momento; puede subir con nuevas compras." else ""
    val texto = prox?.let { desglose(it, s.terms.paymentMode).replaceFirstChar(Char::uppercase) + "." }.orEmpty() + estimado + origen
    return Vista10(
        cuenta.name, euros(s.used), s.terms.paymentMode.title, "${Money.format(s.used, decimals = s.used % 100 != 0L, symbol = false)} de ${euros(s.terms.creditLimit)}",
        s.usedFraction.barra(), s.isOverAlert, euros(s.available), "Próximo cargo" + (prox?.let { " · ${fechaLarga(it.due)}" } ?: ""),
        Money.format(prox?.amount ?: 0), texto,
    )
}

/** 10 Tarjetas: tarjeta principal, límite, próximo cargo y resto de tarjetas. */
@Composable
fun Pantalla10(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val cuentas = cards.cardAccounts
    val principal = cuentas.firstOrNull { cards.summary(it) != null }
    fun abrir(cuenta: Account?, pantalla: Int) {
        cards.selectedId = cuenta?.id
        nav.go(pantalla)
    }
    fun nueva() {
        finance.accountToEdit = null
        finance.newAccountKind = AccountKind.CreditCard
        nav.go(9)
    }
    val vista = if (session.capture) MAQUETA_10 else principal?.let { vista10(it, cards.summary(it)!!, finance) }
    val otras = if (session.capture) {
        listOf(Otra("Mastercard", "Usado 240 de 1.500 € · cuota fija") { nav.go(11) })
    } else {
        cuentas.filter { it.id != principal?.id }.map { cuenta ->
            val s = cards.summary(cuenta)
            if (s == null) {
                Otra(cuenta.name, "Falta poner el límite y cómo la pagas") { abrir(cuenta, 12) }
            } else {
                Otra(cuenta.name, "Usado ${Money.format(s.used, decimals = false, symbol = false)} de ${Money.format(s.terms.creditLimit, decimals = false)} · ${s.terms.paymentMode.title.lowercase()}") { abrir(cuenta, 11) }
            }
        }
    }
    StmScreen(
        topBar = {
            // La fila de la barra grande mide 60 dp, no 64.
            Box(Modifier.height(60.dp)) {
                TopBar(null, onNav = nav::back) {
                    IconBtn(StmIcons.add, ::nueva, contentDescription = "Añadir tarjeta")
                }
            }
            Text("Tarjetas", Modifier.padding(start = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
            Spacer(Modifier.height(16.dp))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        snackbar = cards.error?.let { e -> { Snackbar(e) } },
    ) {
        if (!session.capture && cuentas.isEmpty()) {
            StmCard {
                Text("Aún no hay tarjetas", style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Añade tu tarjeta de crédito y sus condiciones (límite, día del extracto y forma de pago) para saber cuánto te cobrarán cada mes.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                Btn("Añadir tarjeta", ::nueva)
            }
        }
        if (!session.capture && cuentas.size > 1 && cards.nextPaymentsTotal > 0) {
            StmCard {
                Text("Próximos cargos de todas las tarjetas", style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(cards.nextPaymentsTotal), style = StmType.displaySmall, color = c.onSurface)
            }
            Spacer(Modifier.height(16.dp))
        }
        if (vista != null) {
            // «Tarjeta visual» en inverse-surface: en oscuro sale clara.
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.inverseSurface)
                    .tap { abrir(principal, 11) }.padding(20.dp),
            ) {
                Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(vista.nombre, Modifier.weight(1f), style = StmType.titleMedium, color = c.inverseOnSurface)
                    Box(Modifier.size(40.dp, 28.dp).clip(RoundedCornerShape(6.dp)).background(c.primaryContainer))
                }
                Spacer(Modifier.height(37.dp))
                val soft = c.inverseOnSurface.copy(alpha = 0.8f)
                Text("Usado", style = StmType.labelMedium, color = soft)
                Spacer(Modifier.height(4.dp))
                Text(vista.usado, style = StmType.headlineMedium, color = c.inverseOnSurface)
                Spacer(Modifier.height(4.dp))
                Text(vista.nota, style = StmType.bodyMedium, color = soft)
            }
            Spacer(Modifier.height(16.dp))
            StmCard(onClick = { abrir(principal, 12) }) {
                Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Límite", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                    Text(vista.limite, style = StmType.bodyMedium, color = if (vista.alerta) c.error else c.onSurfaceVariant)
                }
                Spacer(Modifier.height(12.dp))
                if (vista.alerta) Progress(vista.fraccion, color = c.error) else Progress(vista.fraccion)
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth().height(20.dp)) {
                    Text("Disponible", Modifier.weight(1f).alignByBaseline(), style = StmType.bodySmall, color = c.onSurfaceVariant)
                    Text(vista.disponible, Modifier.alignByBaseline(), style = StmType.labelLarge, color = c.onSurface)
                }
            }
            Spacer(Modifier.height(16.dp))
            StmCard {
                Text(vista.proximoTitulo, style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(3.5.dp))
                Text(vista.proximo, style = StmType.displaySmall, color = c.onSurface)
                Spacer(Modifier.height(4.5.dp))
                Text(vista.desglose, style = StmType.bodyMedium, color = c.onSurfaceVariant, minLines = 3)
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    Btn("Ver calendario", { abrir(principal, 11) }, kind = BtnKind.Text)
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        if (otras.isNotEmpty()) {
            ListCard {
                otras.forEachIndexed { i, otra ->
                    if (i > 0) Divider()
                    ListItem(
                        otra.nombre, otra.detalle,
                        leading = { LeadIcon(StmIcons.creditCard, c.surfaceContainerHighest, c.onSurfaceVariant) },
                        trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) },
                        onClick = otra.onClick,
                    )
                }
            }
        }
    }
}

private class Cargo11(val fecha: String, val detalle: String, val importe: String)
private class Plazo11(val icono: ImageVector, val titulo: String, val plazo: String, val quedan: String, val importe: String, val cuota: String, val onClick: () -> Unit)

/** Lo común del detalle. Los huecos llevan lo que iOS tiene y el diseño no dibuja. */
@Composable
private fun Detalle11(
    nav: Nav, nombre: String, rango: String, gastado: String, fraccion: Float, alerta: Boolean, cargos: List<Cargo11>, plazos: List<Plazo11>,
    onAplazar: (() -> Unit)?, snackbar: String? = null, trasExtracto: @Composable ColumnScope.() -> Unit = {},
    trasCalendario: @Composable ColumnScope.() -> Unit = {}, trasAplazados: @Composable ColumnScope.() -> Unit = {},
) {
    val c = Stm.colors
    StmScreen(topBar = { DetalleBar(nav, nombre) }, snackbar = snackbar?.let { e -> { Snackbar(e) } }) {
        StmCard {
            Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Extracto abierto", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text(rango, style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth().height(28.dp)) {
                Text("Gastado este ciclo", Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Text(gastado, Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
            }
            Spacer(Modifier.height(12.dp))
            if (alerta) Progress(fraccion, color = c.error) else Progress(fraccion)
        }
        trasExtracto()
        Spacer(Modifier.height(16.dp))
        SectionHeader("Calendario de cargos")
        ListCard {
            cargos.forEachIndexed { i, cargo ->
                if (i > 0) Divider()
                Cargo(cargo.fecha, cargo.detalle, cargo.importe, next = i == 0)
            }
        }
        trasCalendario()
        Spacer(Modifier.height(16.dp))
        SectionHeader("Compras aplazadas", "Aplazar", onAplazar)
        if (plazos.isNotEmpty()) {
            ListCard {
                plazos.forEachIndexed { i, plazo ->
                    if (i > 0) Divider()
                    // Elemento de tres líneas: el icono y el importe van arriba, no centrados.
                    Row(Modifier.fillMaxWidth().tap(onClick = plazo.onClick).padding(start = 16.dp, end = 24.dp, top = 12.dp, bottom = 12.dp)) {
                        LeadIcon(plazo.icono)
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Text(plazo.titulo, style = StmType.bodyLarge, color = c.onSurface)
                            Text(plazo.plazo, style = StmType.bodyMedium, color = c.onSurfaceVariant)
                            Text(plazo.quedan, style = StmType.bodyMedium, color = c.onSurfaceVariant)
                        }
                        Spacer(Modifier.width(16.dp))
                        Column(horizontalAlignment = Alignment.End) {
                            Text(plazo.importe, style = StmType.labelLarge, color = c.onSurface)
                            Text(plazo.cuota, style = StmType.bodySmall, color = c.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        trasAplazados()
    }
}

/** 11 Detalle de tarjeta: extracto abierto, calendario de cargos y compras aplazadas. */
@Composable
fun Pantalla11(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    if (session.capture) {
        Detalle11(
            nav, "Visa compartida", "del 1 al 30 nov", "828,40 €", 0.38f, false,
            listOf(
                Cargo11("1 de diciembre", "Extracto de noviembre + cuotas", "312,40 €"),
                Cargo11("1 de enero", "Cuotas de aplazados", "38,42 €"),
                Cargo11("1 de febrero", "Última cuota del restaurante", "19,21 €"),
            ),
            listOf(Plazo11(StmIcons.restaurant, "Restaurante Sol", "3 meses · TIN 14 %", "Quedan 2 cuotas", "56,00 €", "19,21 €/mes") { nav.go(13) }),
            onAplazar = { nav.go(13) },
        )
        return
    }
    val cuenta = cards.selected ?: return
    val s = cards.summary(cuenta)
    if (s == null) {
        StmScreen(topBar = { DetalleBar(nav, cuenta.name) }) {
            StmCard {
                Text("Pon el límite, el día del extracto y cómo la pagas para calcular tus cargos.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn("Configurar tarjeta", { nav.go(12) })
            }
        }
        return
    }
    val inicio = s.terms.cycleStart(s.openStatement)
    val fin = s.openStatement.minusDays(1)
    val rango = "del " + (if (inicio.month == fin.month) "${inicio.dayOfMonth}" else Fechas.corto(inicio)) + " al ${Fechas.corto(fin)}"
    val compras = cards.movements(cuenta)
    val aplazables = cards.deferrable(cuenta)
    val planes = cards.plans(cuenta)
    val plazos = planes.mapNotNull { plan ->
        val m = compras.firstOrNull { it.id == plan.movementId } ?: return@mapNotNull null
        val quedan = CreditCardCalculator.remainingInstallments(plan, m, s)
        Plazo11(
            iconoCategoria(finance.category(m.categoryId)), m.description, "${plan.months} meses · TIN ${tasa(plan.rate)} %",
            when (quedan) { 0 -> "Pagada"; 1 -> "Queda 1 cuota"; else -> "Quedan $quedan cuotas" },
            Money.format(-m.amountMinor), "${Money.format(CardInstallment.payment(-m.amountMinor, plan.months, plan.rate))}/mes",
        ) {
            cards.purchaseId = m.id
            nav.go(13)
        }
    }
    val nota = @Composable { texto: String, color: Color ->
        Spacer(Modifier.height(8.dp))
        Text(texto, style = StmType.bodySmall, color = color)
    }
    val retraso = when (s.terms.paymentDelayMonths) {
        0 -> "el día ${s.terms.paymentDay} de ese mes"
        1 -> "el día ${s.terms.paymentDay} del mes siguiente"
        else -> "el día ${s.terms.paymentDay}, ${s.terms.paymentDelayMonths} meses después"
    }
    Detalle11(
        nav, cuenta.name, rango, Money.format(s.spentThisCycle), s.usedFraction.barra(), s.isOverAlert,
        s.payments.map { p ->
            Cargo11(fechaLarga(p.due), desglose(p, s.terms.paymentMode).replaceFirstChar(Char::uppercase) + if (p.isEstimate) " · estimado" else "", Money.format(p.amount))
        },
        plazos,
        onAplazar = if (aplazables.isEmpty()) null else ({ cards.purchaseId = null; nav.go(13) }),
        snackbar = cards.error,
        trasExtracto = {
            val alerta = s.terms.alertPercent
            if (s.isOverAlert && alerta != null) nota("Has pasado del $alerta % del límite. Te quedan ${Money.format(s.available)}.", c.error)
        },
        trasCalendario = {
            nota("Lo que gastas entra en el extracto del día ${s.terms.statementDay}, que se cobra $retraso.", c.onSurfaceVariant)
            if (s.terms.paymentMode.isRevolving) {
                Spacer(Modifier.height(16.dp))
                SectionHeader("Lo que cuesta aplazar")
                StmCard {
                    Fila("Deuda con intereses · TIN ${tasa(s.terms.revolvingRate)} %", Money.format(s.revolvingBalance))
                    Spacer(Modifier.height(8.dp))
                    Fila("Intereses en ${s.payments.size} cargos", Money.format(s.interestInPayments))
                    val fin = s.payoff
                    if (fin != null) {
                        nota(
                            "Sin compras nuevas, terminarías de pagar en ${fin.months} ${if (fin.months == 1) "mes" else "meses"} y pagarías ${Money.format(fin.interest)} de intereses. Pagando todo a fin de mes no pagarías ninguno.",
                            c.onSurface,
                        )
                    } else if (s.revolvingBalance > 0) {
                        nota("La cuota no llega a cubrir los intereses: la deuda no baja. Sube la cuota o paga todo a fin de mes.", c.error)
                    }
                }
            }
        },
        trasAplazados = {
            if (planes.isEmpty()) {
                nota("Las compras de 50 € o más del extracto abierto se pueden pagar en 3, 6, 9 o 12 meses al ${tasa(s.terms.installmentRate)} % TIN. La cuota se suma a cada cargo.", c.onSurfaceVariant)
            } else if (aplazables.isEmpty()) {
                nota("Para aplazar otra compra tiene que ser de 50 € o más y del extracto abierto.", c.onSurfaceVariant)
            }
            Spacer(Modifier.height(16.dp))
            StmCard {
                val origen = finance.account(s.terms.payFromAccountId)
                if (origen != null) {
                    val saldo = finance.balance(origen)
                    Fila("Se paga desde ${origen.name}", Money.format(saldo))
                    val prox = s.next
                    if (prox != null && saldo < prox.amount) nota("No llega para el próximo cargo de ${Money.format(prox.amount)}.", c.error)
                } else {
                    Text("Elige en Condiciones la cuenta desde la que se paga la tarjeta para saber si hay saldo.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                }
                Spacer(Modifier.height(16.dp))
                Btn("Apuntar el pago de la tarjeta", {
                    finance.movementForm = MovementForm(
                        accountId = origen?.id ?: finance.activeAccounts.firstOrNull { !it.kind.isLiability }?.id, transfer = true, toAccountId = cuenta.id,
                        amountMinor = s.next?.amount?.takeIf { it > 0 }, description = "Pago de ${cuenta.name}",
                    )
                    nav.go(7)
                }, kind = BtnKind.Outlined)
                nota("El pago se apunta como transferencia de la cuenta a la tarjeta, así el gasto no cuenta dos veces.", c.onSurfaceVariant)
            }
        },
    )
}

@Composable
private fun Fila(texto: String, importe: String) {
    val c = Stm.colors
    Row(Modifier.fillMaxWidth()) {
        Text(texto, Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.width(8.dp))
        Text(importe, Modifier.alignByBaseline(), style = StmType.labelLarge, color = c.onSurface)
    }
}

/** 12 Condiciones de tarjeta: límite, días de extracto y cargo, forma de pago, intereses y avisos. */
@Composable
fun Pantalla12(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val demo = session.capture
    val cuenta = cards.selected
    val base = cuenta?.let { cards.terms[it.id] }
    var limite by remember(base) { mutableStateOf(if (demo) "3.000,00" else base?.creditLimit?.let(Money::input).orEmpty()) }
    var diaExtracto by remember(base) { mutableStateOf("${base?.statementDay ?: 1}") }
    var diaCargo by remember(base) { mutableStateOf("${base?.paymentDay ?: 1}") }
    var retraso by remember(base) { mutableIntStateOf(base?.paymentDelayMonths ?: 1) }
    var forma by remember(base) { mutableIntStateOf(base?.paymentMode?.ordinal ?: 0) }
    var cuota by remember(base) { mutableStateOf(base?.fixedPayment?.let(Money::input).orEmpty()) }
    var minimoPct by remember(base) { mutableStateOf(tasa(base?.minPaymentPercent ?: 3.0)) }
    var minimo by remember(base) { mutableStateOf(Money.input(base?.minPayment ?: 1_500)) }
    var tinAplazado by remember(base) { mutableStateOf(if (demo) "20,00" else tasa(base?.revolvingRate ?: 20.0)) }
    var tinPlazos by remember(base) { mutableStateOf(if (demo) "14,00" else tasa(base?.installmentRate ?: 14.0)) }
    var pagaDesde by remember(base) { mutableStateOf(base?.payFromAccountId) }
    var recordar by remember(base) { mutableStateOf(base == null || base.remindDaysBefore != null) }
    var dias by remember(base) { mutableIntStateOf(base?.remindDaysBefore ?: 2) }
    var avisar by remember(base) { mutableStateOf(base == null || base.alertPercent != null) }
    var aviso by remember(base) { mutableIntStateOf(base?.alertPercent ?: 80) }
    var eligeCuenta by remember { mutableStateOf(false) }
    val action = rememberAction()
    val modo = CardPaymentMode.entries[forma]

    fun guardar() = action.run {
        if (cuenta == null) {
            nav.back()
            return@run
        }
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val limiteMinor = Money.parse(limite)?.takeIf { it > 0 } ?: falla("El límite no es un importe válido.")
        val revolving = leerTasa(tinAplazado) ?: falla("Revisa los intereses y el pago mínimo.")
        val plazos = leerTasa(tinPlazos) ?: falla("Revisa los intereses y el pago mínimo.")
        val pct = leerTasa(minimoPct) ?: falla("Revisa los intereses y el pago mínimo.")
        val suelo = Money.parse(minimo.ifBlank { "0" }) ?: falla("El pago mínimo no es un importe válido.")
        val fija = if (modo == CardPaymentMode.Fixed) Money.parse(cuota)?.takeIf { it > 0 } ?: falla("La cuota no es un importe válido.") else null
        cards.save(
            CreditCardTerms(
                cuenta.id, cuenta.householdId, limiteMinor, diaExtracto.toIntOrNull() ?: 0, diaCargo.toIntOrNull() ?: 0, retraso, modo, fija,
                pct, suelo, revolving, plazos, pagaDesde, if (recordar) dias else null, if (avisar) aviso else null,
            ),
        )
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar("Condiciones", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeCuenta) {
            {
                SelectorSheet(
                    "Se paga desde",
                    listOf<Pair<String, () -> Unit>>("Sin elegir" to { pagaDesde = null }) +
                        finance.activeAccounts.filter { it.id != cuenta?.id && !it.kind.isLiability }.map { a -> a.name to { pagaDesde = a.id } },
                ) { eligeCuenta = false }
            }
        } else {
            null
        },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField("Límite de crédito", limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("Día del extracto", diaExtracto, { diaExtracto = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
            FilledField("Día del cargo", diaCargo, { diaCargo = it }, Modifier.weight(1f), keyboard = KeyboardType.Number)
        }
        Spacer(Modifier.height(16.dp))
        Text("Forma de pago", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Todo", "Cuota fija", "Mínimo"), forma, { forma = it })
        // Solo aparecen al cambiar la forma de pago, así que el diseño no se mueve.
        if (modo == CardPaymentMode.Fixed) {
            Spacer(Modifier.height(16.dp))
            FilledField("Cuota al mes", cuota, { cuota = it }, suffix = "€", keyboard = KeyboardType.Decimal)
        }
        if (modo.isRevolving) {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField("Mínimo: % deuda", minimoPct, { minimoPct = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
                FilledField("Mínimo: al menos", minimo, { minimo = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                modo.detail + " El pago mínimo es el % de la deuda más los intereses, y nunca menos del importe mínimo.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FilledField("TIN aplazado", tinAplazado, { tinAplazado = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
            FilledField("TIN a plazos", tinPlazos, { tinPlazos = it }, Modifier.weight(1f), suffix = "%", keyboard = KeyboardType.Decimal)
        }
        Spacer(Modifier.height(16.dp))
        FilledField(
            "Paga desde", if (demo) "Cuenta principal" else finance.account(pagaDesde)?.name ?: "Sin elegir",
            trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true },
        )
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem("Recordar el cargo", textoAviso(dias).replaceFirstChar(Char::uppercase), trailing = { SwitchSlot(recordar) { recordar = it } })
            Divider(inset = 16.dp)
            ListItem("Avisar al $aviso % del límite", trailing = { SwitchSlot(avisar) { avisar = it } })
        }
        // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
        if (!demo) {
            Spacer(Modifier.height(16.dp))
            if (recordar) {
                FilaStepper("Cuándo recordar", textoAviso(dias), { dias = (dias - 1).coerceAtLeast(0) }, { dias = (dias + 1).coerceAtMost(14) })
                Spacer(Modifier.height(12.dp))
            }
            if (avisar) {
                FilaStepper("Avisar al pasar del", "$aviso %", { aviso = (aviso - 5).coerceAtLeast(50) }, { aviso = (aviso + 5).coerceAtMost(100) })
                Spacer(Modifier.height(16.dp))
            }
            Text("Se cobra", style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Segmented(listOf("Mismo mes", "Mes siguiente", "2 meses"), retraso, { retraso = it })
            Spacer(Modifier.height(8.dp))
            Text(
                "Míralo en tu contrato. Por ejemplo: extracto el día 1 y cargo el día 1 del mes siguiente quiere decir que lo gastado en enero se cobra el 1 de marzo.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun FilaStepper(titulo: String, valor: String, onMenos: () -> Unit, onMas: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(titulo, Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
        Stepper(valor, onMenos, onMas)
    }
}

/** 13 Aplazar compra: hoja inferior con plazos, TIN y cuota resultante sobre el detalle de la tarjeta. */
@Composable
fun Pantalla13(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val cuenta = cards.selected
    val resumen = cuenta?.let(cards::summary)
    var compraId by remember { mutableStateOf(cards.takePurchase()) }
    val compra = cuenta?.let(cards::movements).orEmpty().firstOrNull { it.id == compraId }
    val plan = compra?.let(cards::installment)
    val candidatas = cuenta?.let(cards::deferrable).orEmpty()
    val meses = CardInstallment.commonMonths
    var plazo by remember(compraId) { mutableIntStateOf(plan?.let { meses.indexOf(it.months).coerceAtLeast(0) } ?: 0) }
    var tin by remember(compraId) { mutableStateOf(if (session.capture) "14,00" else tasa(plan?.rate ?: resumen?.terms?.installmentRate ?: 14.0)) }
    val action = rememberAction()
    val valida = compra != null && (plan != null || candidatas.any { it.id == compra.id })
    StmScreen(
        topBar = { DetalleBar(nav, if (session.capture) "Visa compartida" else cuenta?.name ?: "Tarjeta") },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = {
            when {
                session.capture -> HojaAplazar("Aplazar Restaurante Sol", "56,00 € · 3 nov", plazo, { plazo = it }, tin, { tin = it }, "19,21 €/mes", "1,63 €", nav::back, nav::back, null)
                valida -> {
                    val total = -compra!!.amountMinor
                    val rate = leerTasa(tin)
                    val cuota = rate?.let { CardInstallment.payment(total, meses[plazo], it) }
                    HojaAplazar(
                        "Aplazar ${compra.description}", "${Money.format(total)} · ${Fechas.corto(compra.day)}", plazo, { plazo = it }, tin, { tin = it },
                        cuota?.let { "${Money.format(it)}/mes" } ?: "—", cuota?.let { Money.format(it * meses[plazo] - total) } ?: "—", nav::back,
                        {
                            action.run {
                                cards.deferPurchase(compra, meses[plazo], cuenta!!, rate ?: throw AppError.InvalidInput("Revisa el interés."))
                                nav.back()
                            }
                        },
                        plan?.let { p -> { action.run { cards.remove(p); nav.back() } } },
                    )
                }
                compraId == null && candidatas.isNotEmpty() -> SelectorSheet(
                    "Elige una compra", candidatas.map { m -> "${m.description} · ${Money.format(-m.amountMinor)}" to { compraId = m.id } },
                ) { if (compraId == null) nav.back() }
                else -> BottomSheet("No se puede aplazar", null, onDismiss = nav::back) {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        Text(
                            "Sólo compras de 50 € o más del extracto que aún está abierto, en una tarjeta con sus condiciones puestas.",
                            style = StmType.bodyMedium, color = c.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(16.dp))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Btn("Entendido", nav::back, kind = BtnKind.Text) }
                    }
                }
            }
        },
    ) {
        // Bajo la hoja, el diseño solo muestra el próximo cargo de la tarjeta.
        StmCard {
            Text("Próximo cargo", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.5.dp))
            Text(if (session.capture) "312,40 €" else Money.format(resumen?.next?.amount ?: 0), style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(0.5.dp))
        }
    }
}

@Composable
private fun BoxScope.HojaAplazar(
    titulo: String, subtitulo: String, plazo: Int, onPlazo: (Int) -> Unit, tin: String, onTin: (String) -> Unit, cuota: String, intereses: String,
    onCancelar: () -> Unit, onAplazar: () -> Unit, onQuitar: (() -> Unit)?,
) {
    val c = Stm.colors
    BottomSheet(titulo, subtitulo, onDismiss = onCancelar) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            // La cabecera del diseño mide 56 dp; la de la hoja compartida, 54.
            Spacer(Modifier.height(2.dp))
            Segmented(listOf("3", "6", "9", "12 meses"), plazo, onPlazo)
            Spacer(Modifier.height(16.dp))
            SuffixOutlinedField("TIN anual", tin, onTin, "%", c.surfaceContainerLow)
            Spacer(Modifier.height(16.dp))
            StmCard(color = c.surfaceContainerHighest) {
                Row(Modifier.fillMaxWidth().height(28.dp)) {
                    Text("Cuota", Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                    Text(cuota, Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Intereses en total", Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                    Text(intereses, style = StmType.labelLarge, color = c.onSurface)
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                if (onQuitar != null) Btn("Quitar aplazado", onQuitar, kind = BtnKind.Text, color = c.error)
                Btn("Cancelar", onCancelar, kind = BtnKind.Text)
                Btn("Aplazar", onAplazar)
            }
        }
    }
}

/** Barra con el nombre de la tarjeta que comparten el detalle (11) y el aplazamiento (13). */
@Composable
private fun DetalleBar(nav: Nav, nombre: String) {
    TopBar(nombre, onNav = nav::back) {
        IconBtn(StmIcons.edit, { nav.go(12) }, contentDescription = "Editar condiciones")
        IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
    }
}

/** Fila del calendario de cargos; el próximo va resaltado en secondary-container. */
@Composable
private fun Cargo(date: String, detail: String, amount: String, next: Boolean = false) {
    val c = Stm.colors
    ListItem(
        date, detail, trailingText = amount, supportingLines = 2,
        leading = {
            if (next) LeadIcon(StmIcons.event) else LeadIcon(StmIcons.event, c.surfaceContainerHighest, c.onSurfaceVariant)
        },
    )
}

/** «Final» de 40 dp del diseño: el interruptor de 52 sobresale por la derecha, como en FigCraft. */
@Composable
private fun SwitchSlot(checked: Boolean, onChange: (Boolean) -> Unit) {
    Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) {
        StmSwitch(checked, onChange)
    }
}

/** «Campo de texto» con borde y sufijo (p. ej. «%»), que el OutlinedField compartido no tiene. */
@Composable
private fun SuffixOutlinedField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, labelBackground: Color) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().height(56.dp)) {
        Row(
            Modifier.fillMaxSize().border(if (focused) 2.dp else 1.dp, if (focused) c.primary else c.outline, RoundedCornerShape(4.dp))
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value, onValueChange, Modifier.weight(1f).onFocusChanged { focused = it.isFocused }, singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            Spacer(Modifier.width(12.dp))
            Text(suffix, style = StmType.bodyLarge, color = c.onSurfaceVariant)
        }
        Text(
            label, style = StmType.bodySmall, color = if (focused) c.primary else c.onSurfaceVariant,
            modifier = Modifier.offset(x = 12.dp, y = (-8).dp).background(labelBackground).padding(horizontal = 4.dp),
        )
    }
}
