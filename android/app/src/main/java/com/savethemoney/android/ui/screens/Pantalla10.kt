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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.CreditCardSummary
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo

private fun euros(minor: Long) = Money.format(minor, decimals = minor % 100 != 0L)

private class Vista10(
    val nombre: String, val usado: String, val nota: String, val limite: String, val fraccion: Float, val alerta: Boolean,
    val disponible: String, val proximoTitulo: String, val proximo: String, val desglose: String,
)

private class Otra(val nombre: String, val detalle: String, val onClick: () -> Unit)

private fun vista10(cuenta: Account, s: CreditCardSummary, finance: FinanceModel, resources: android.content.res.Resources): Vista10 {
    val prox = s.next
    val origen = finance.account(s.terms.payFromAccountId)?.name?.let { resources.getString(R.string.tarjetas_sale_de, it) }.orEmpty()
    val estimado = if (prox?.isEstimate == true) resources.getString(R.string.tarjetas_de_momento_puede_subir_con_nuevas) else ""
    val texto = prox?.let { desglose(it, s.terms.paymentMode, resources).replaceFirstChar(Char::uppercase) + "." }.orEmpty() + estimado + origen
    return Vista10(
        cuenta.name, euros(s.used), resources.getString(s.terms.paymentMode.titulo), resources.getString(R.string.tarjetas_de, Money.format(s.used, decimals = s.used % 100 != 0L, symbol = false), euros(s.terms.creditLimit)),
        s.usedFraction.barra(), s.isOverAlert, euros(s.available), prox?.let { resources.getString(R.string.tarjetas_proximo_cargo_fecha, fechaLarga(it.due, resources)) } ?: resources.getString(R.string.comun_proximo_cargo),
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
    val resources = LocalResources.current
    val cuentas = cards.cardAccounts
    val principal = cuentas.firstOrNull { cards.summary(it) != null }
    fun abrir(cuenta: Account?, pantalla: (String?) -> Route) {
        nav.go(pantalla(cuenta?.id))
    }
    fun nueva() {
        nav.go(Route.FormCuenta(kind = AccountKind.CreditCard))
    }
    val vista = principal?.let { vista10(it, cards.summary(it)!!, finance, resources) }
    val otras = cuentas.filter { it.id != principal?.id }.map { cuenta ->
        val s = cards.summary(cuenta)
        if (s == null) {
            Otra(cuenta.name, stringResource(R.string.tarjetas_falta_poner_el_limite_y_como)) { abrir(cuenta, Route::CondicionesTarjeta) }
        } else {
            Otra(cuenta.name, stringResource(R.string.tarjetas_usado_de, Money.format(s.used, decimals = false, symbol = false), Money.format(s.terms.creditLimit, decimals = false), stringResource(s.terms.paymentMode.titulo).lowercase())) { abrir(cuenta, Route::Tarjeta) }
        }
    }
    StmScreen(
        topBar = {
            // La fila de la barra grande mide 60 dp, no 64.
            Box(Modifier.height(60.dp)) {
                TopBar(null, onNav = nav::back) {
                    IconBtn(StmIcons.add, ::nueva, contentDescription = stringResource(R.string.tarjetas_anadir_tarjeta))
                }
            }
            Text(stringResource(R.string.tarjetas_tarjetas), Modifier.padding(start = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
            Spacer(Modifier.height(16.dp))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        snackbar = cards.error?.let { e -> { Snackbar(e) } },
    ) {
        if (cuentas.isEmpty()) {
            StmCard {
                Text(stringResource(R.string.tarjetas_aun_no_hay_tarjetas), style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.tarjetas_anade_tu_tarjeta_de_credito_y),
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                Btn(stringResource(R.string.tarjetas_anadir_tarjeta), ::nueva)
            }
        }
        if (cuentas.size > 1 && cards.nextPaymentsTotal > 0) {
            StmCard {
                Text(stringResource(R.string.tarjetas_proximos_cargos_de_todas_las), style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(cards.nextPaymentsTotal), style = StmType.displaySmall, color = c.onSurface)
            }
            Spacer(Modifier.height(16.dp))
        }
        if (vista != null) {
            // «Tarjeta visual» en inverse-surface: en oscuro sale clara.
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.inverseSurface)
                    .tap { abrir(principal, Route::Tarjeta) }.padding(20.dp),
            ) {
                Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(vista.nombre, Modifier.weight(1f), style = StmType.titleMedium, color = c.inverseOnSurface)
                    Box(Modifier.size(40.dp, 28.dp).clip(RoundedCornerShape(6.dp)).background(c.primaryContainer))
                }
                Spacer(Modifier.height(37.dp))
                val soft = c.inverseOnSurface.copy(alpha = 0.8f)
                Text(stringResource(R.string.tarjetas_usado), style = StmType.labelMedium, color = soft)
                Spacer(Modifier.height(4.dp))
                Text(vista.usado, style = StmType.headlineMedium, color = c.inverseOnSurface)
                Spacer(Modifier.height(4.dp))
                Text(vista.nota, style = StmType.bodyMedium, color = soft)
            }
            Spacer(Modifier.height(16.dp))
            StmCard(onClick = { abrir(principal, Route::CondicionesTarjeta) }) {
                Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.tarjetas_limite), Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                    Text(vista.limite, style = StmType.bodyMedium, color = if (vista.alerta) c.error else c.onSurfaceVariant)
                }
                Spacer(Modifier.height(12.dp))
                if (vista.alerta) Progress(vista.fraccion, color = c.error) else Progress(vista.fraccion)
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth().height(20.dp)) {
                    Text(stringResource(R.string.tarjetas_disponible), Modifier.weight(1f).alignByBaseline(), style = StmType.bodySmall, color = c.onSurfaceVariant)
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
                    Btn(stringResource(R.string.tarjetas_ver_calendario), { abrir(principal, Route::Tarjeta) }, kind = BtnKind.Text)
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
