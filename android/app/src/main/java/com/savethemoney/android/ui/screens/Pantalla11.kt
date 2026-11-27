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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
@Composable private fun avisoAbonos(n: Int) =
    pluralStringResource(R.plurals.tarjeta_hay_abonos_sin_categoria_sin, n, n)

/** Aviso de aplazados cuya compra no se ha podido cargar: sin ella no se sabe la cuota ni el capital. */
@Composable private fun avisoAplazados(n: Int) =
    pluralStringResource(R.plurals.tarjeta_no_se_han_podido_cargar_las, n, n)

/** Aviso de que los extractos sin cobrar tienen más movimientos de los que se cargan de una vez. */
@Composable private fun avisoRecortados() =
    stringResource(R.string.tarjeta_los_extractos_sin_cobrar_tienen, CreditCardModel.CYCLE_LIMIT)

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
                Text(stringResource(R.string.tarjeta_extracto_abierto), Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                Text(rango, style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth().height(28.dp)) {
                Text(stringResource(R.string.tarjeta_gastado_este_ciclo), Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Text(gastado, Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
            }
            Spacer(Modifier.height(12.dp))
            if (alerta) Progress(fraccion, color = c.error) else Progress(fraccion)
        }
        trasExtracto()
        Spacer(Modifier.height(16.dp))
        SectionHeader(stringResource(R.string.tarjeta_calendario_de_cargos))
        ListCard {
            cargos.forEachIndexed { i, cargo ->
                if (i > 0) Divider()
                Cargo(cargo.fecha, cargo.detalle, cargo.importe, next = i == 0)
            }
        }
        trasCalendario()
        Spacer(Modifier.height(16.dp))
        SectionHeader(stringResource(R.string.tarjeta_compras_aplazadas), stringResource(R.string.tarjeta_aplazar), onAplazar)
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
                Text(stringResource(R.string.tarjeta_pon_el_limite_el_dia_del), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn(stringResource(R.string.tarjeta_configurar_tarjeta), { nav.go(Route.CondicionesTarjeta(cuenta.id)) })
            }
        }
        return
    }
    val inicio = s.terms.cycleStart(s.openStatement)
    val fin = s.openStatement.minusDays(1)
    val resources = LocalResources.current
    val rango = stringResource(R.string.tarjeta_del_al, (if (inicio.month == fin.month) "${inicio.dayOfMonth}" else Fechas.corto(inicio)), Fechas.corto(fin))
    val compras = cards.movements(cuenta)
    val aplazables = cards.deferrable(cuenta)
    val planes = cards.plans(cuenta)
    val plazos = planes.mapNotNull { plan ->
        val m = compras.firstOrNull { it.id == plan.movementId } ?: return@mapNotNull null
        val quedan = CreditCardCalculator.remainingInstallments(plan, m, s)
        Plazo11(
            iconoCategoria(finance.category(m.categoryId)), MovementText.display(m.description), stringResource(R.string.tarjeta_meses_tin, plan.months, tasa(plan.rate)),
            if (quedan == 0) stringResource(R.string.tarjeta_pagada) else pluralStringResource(R.plurals.tarjeta_quedan_cuotas, quedan, quedan),
            Money.format(-m.amountMinor), stringResource(R.string.tarjeta_mes, Money.format(CardInstallment.payment(-m.amountMinor, plan.months, plan.rate))),
        ) {
            nav.go(Route.AplazarCompra(cuenta.id, m.id))
        }
    }
    val nota = @Composable { texto: String, color: Color ->
        Spacer(Modifier.height(8.dp))
        Text(texto, style = StmType.bodySmall, color = color)
    }
    val retraso = when (s.terms.paymentDelayMonths) {
        0 -> stringResource(R.string.tarjeta_extracto_se_cobra_ese_mes, s.terms.statementDay, s.terms.paymentDay)
        1 -> stringResource(R.string.tarjeta_extracto_se_cobra_mes_siguiente, s.terms.statementDay, s.terms.paymentDay)
        else -> stringResource(R.string.tarjeta_extracto_se_cobra_meses_despues, s.terms.statementDay, s.terms.paymentDay, s.terms.paymentDelayMonths)
    }
    Detalle11(
        nav, cuenta, cuenta.name, rango, Money.format(s.spentThisCycle), s.usedFraction.barra(), s.isOverAlert,
        s.payments.map { p ->
            Cargo11(fechaLarga(p.due, resources), desglose(p, s.terms.paymentMode, resources).replaceFirstChar(Char::uppercase).let { if (p.isEstimate) stringResource(R.string.tarjeta_cargo_estimado, it) else it }, Money.format(p.amount))
        },
        plazos,
        onAplazar = if (aplazables.isEmpty()) null else ({ nav.go(Route.AplazarCompra(cuenta.id)) }),
        snackbar = cards.error,
        trasExtracto = {
            val alerta = s.terms.alertPercent
            if (s.isOverAlert && alerta != null) nota(stringResource(R.string.tarjeta_has_pasado_del_del_limite_te, alerta, Money.format(s.available)), c.error)
            if (s.uncategorizedCredits.isNotEmpty()) nota(avisoAbonos(s.uncategorizedCredits.size), c.error)
            if (s.unresolvedInstallments.isNotEmpty()) nota(avisoAplazados(s.unresolvedInstallments.size), c.error)
            if (s.movementsTruncated) nota(avisoRecortados(), c.error)
        },
        trasCalendario = {
            nota(retraso, c.onSurfaceVariant)
            if (s.terms.paymentMode.isRevolving) {
                Spacer(Modifier.height(16.dp))
                SectionHeader(stringResource(R.string.tarjeta_lo_que_cuesta_aplazar))
                StmCard {
                    Fila(stringResource(R.string.tarjeta_deuda_con_intereses_tin, tasa(s.terms.revolvingRate)), Money.format(s.revolvingBalance))
                    Spacer(Modifier.height(8.dp))
                    Fila(stringResource(R.string.tarjeta_intereses_en_cargos, s.payments.size), Money.format(s.interestInPayments))
                    val fin = s.payoff
                    if (fin != null) {
                        nota(
                            pluralStringResource(R.plurals.tarjeta_terminarias_de_pagar, fin.months, fin.months, Money.format(fin.interest)),
                            c.onSurface,
                        )
                    } else if (s.revolvingBalance > 0) {
                        nota(stringResource(R.string.tarjeta_la_cuota_no_llega_a_cubrir), c.error)
                    }
                }
            }
        },
        trasAplazados = {
            if (planes.isEmpty()) {
                nota(stringResource(R.string.tarjeta_las_compras_de_50_o_mas, tasa(s.terms.installmentRate)), c.onSurfaceVariant)
            } else if (aplazables.isEmpty()) {
                nota(stringResource(R.string.tarjeta_para_aplazar_otra_compra_tiene_que), c.onSurfaceVariant)
            }
            Spacer(Modifier.height(16.dp))
            StmCard {
                val origen = finance.account(s.terms.payFromAccountId)
                if (origen != null) {
                    val saldo = finance.balance(origen)
                    Fila(stringResource(R.string.tarjeta_se_paga_desde, origen.name), Money.format(saldo))
                    val prox = s.next
                    if (prox != null && saldo < prox.amount) nota(stringResource(R.string.tarjeta_no_llega_para_el_proximo_cargo, Money.format(prox.amount)), c.error)
                } else {
                    Text(stringResource(R.string.tarjeta_elige_en_condiciones_la_cuenta), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                }
                Spacer(Modifier.height(16.dp))
                Btn(stringResource(R.string.tarjeta_apuntar_el_pago_de_la_tarjeta), {
                    // El importe y el concepto los pone el formulario con los datos de la tarjeta al abrirse.
                    nav.go(
                        Route.FormMovimiento(
                            accountId = origen?.id ?: finance.activeAccounts.firstOrNull { !it.kind.isLiability }?.id, transfer = true, toAccountId = cuenta.id,
                            cardPayment = true,
                        ),
                    )
                }, kind = BtnKind.Outlined)
                nota(stringResource(R.string.tarjeta_el_pago_se_apunta_como), c.onSurfaceVariant)
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
