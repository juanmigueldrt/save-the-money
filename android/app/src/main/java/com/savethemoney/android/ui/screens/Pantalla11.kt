package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CreditCardCalculator
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.CreditCardModel
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.SectionHeader
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** Aviso de abonos sin categoría: no se sabe si son un pago de la tarjeta o una devolución. */
private fun avisoAbonos(n: Int) =
    (if (n == 1) "Hay 1 abono sin categoría" else "Hay $n abonos sin categoría") +
        ". Sin categoría no bajan los cargos: si es una devolución, ponle la suya; si es un pago de la tarjeta, una de transferencia."

/** Aviso de aplazados cuya compra no se ha podido cargar: sin ella no se sabe la cuota ni el capital. */
private fun avisoAplazados(n: Int) =
    (if (n == 1) "No se ha podido cargar la compra de 1 aplazado" else "No se han podido cargar las compras de $n aplazados") +
        ". Hasta que se carguen, los cargos y la deuda de la tarjeta no son de fiar: vuelve a abrirla en un rato."

/** Aviso de que los extractos sin cobrar tienen más movimientos de los que se cargan de una vez. */
private val avisoRecortados =
    "Los extractos sin cobrar tienen ${CreditCardModel.CYCLE_LIMIT} movimientos o más y puede que no se hayan cargado todos: " +
        "los cargos y lo gastado pueden salir más bajos de lo que son."

private class Cargo11(val fecha: String, val detalle: String, val importe: String)

private class Plazo11(val icono: ImageVector, val titulo: String, val plazo: String, val quedan: String, val importe: String, val cuota: String, val onClick: () -> Unit)

/** Lo común del detalle. Los huecos llevan lo que iOS tiene y el diseño no dibuja. */
@Composable
private fun Detalle11(
    nav: Nav, cuenta: Account?, nombre: String, rango: String, gastado: String, fraccion: Float, alerta: Boolean, cargos: List<Cargo11>, plazos: List<Plazo11>,
    onAplazar: (() -> Unit)?, snackbar: String? = null, trasExtracto: @Composable ColumnScope.() -> Unit = {},
    trasCalendario: @Composable ColumnScope.() -> Unit = {}, trasAplazados: @Composable ColumnScope.() -> Unit = {},
) {
    val c = Stm.colors
    StmScreen(topBar = { DetalleBar(nav, cuenta, nombre) }, snackbar = snackbar?.let { e -> { Snackbar(e) } }) {
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
fun Pantalla11(nav: Nav, cardId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val cuenta = cards.card(cardId) ?: return NoEncontrado(nav)
    val s = cards.summary(cuenta)
    if (s == null) {
        StmScreen(topBar = { DetalleBar(nav, cuenta, cuenta.name) }) {
            StmCard {
                Text("Pon el límite, el día del extracto y cómo la pagas para calcular tus cargos.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn("Configurar tarjeta", { nav.go(Route.CondicionesTarjeta(cuenta.id)) })
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
            iconoCategoria(finance.category(m.categoryId)), MovementText.display(m.description), "${plan.months} meses · TIN ${tasa(plan.rate)} %",
            when (quedan) { 0 -> "Pagada"; 1 -> "Queda 1 cuota"; else -> "Quedan $quedan cuotas" },
            Money.format(-m.amountMinor), "${Money.format(CardInstallment.payment(-m.amountMinor, plan.months, plan.rate))}/mes",
        ) {
            nav.go(Route.AplazarCompra(cuenta.id, m.id))
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
        nav, cuenta, cuenta.name, rango, Money.format(s.spentThisCycle), s.usedFraction.barra(), s.isOverAlert,
        s.payments.map { p ->
            Cargo11(fechaLarga(p.due), desglose(p, s.terms.paymentMode).replaceFirstChar(Char::uppercase) + if (p.isEstimate) " · estimado" else "", Money.format(p.amount))
        },
        plazos,
        onAplazar = if (aplazables.isEmpty()) null else ({ nav.go(Route.AplazarCompra(cuenta.id)) }),
        snackbar = cards.error,
        trasExtracto = {
            val alerta = s.terms.alertPercent
            if (s.isOverAlert && alerta != null) nota("Has pasado del $alerta % del límite. Te quedan ${Money.format(s.available)}.", c.error)
            if (s.uncategorizedCredits.isNotEmpty()) nota(avisoAbonos(s.uncategorizedCredits.size), c.error)
            if (s.unresolvedInstallments.isNotEmpty()) nota(avisoAplazados(s.unresolvedInstallments.size), c.error)
            if (s.movementsTruncated) nota(avisoRecortados, c.error)
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
                    // El importe y el concepto los pone el formulario con los datos de la tarjeta al abrirse.
                    nav.go(
                        Route.FormMovimiento(
                            accountId = origen?.id ?: finance.activeAccounts.firstOrNull { !it.kind.isLiability }?.id, transfer = true, toAccountId = cuenta.id,
                            cardPayment = true,
                        ),
                    )
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
