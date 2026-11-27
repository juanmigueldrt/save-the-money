package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 13 Aplazar compra: hoja inferior con plazos, TIN y cuota resultante sobre el detalle de la tarjeta. */
@Composable
fun Pantalla13(nav: Nav, cardId: String?, movementId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val cards = finance.cards
    val c = Stm.colors
    val cuenta = cards.card(cardId)
    if (cardId != null && cuenta == null) return NoEncontrado(nav)
    val resumen = cuenta?.let(cards::summary)
    var compraId by rememberSaveable { mutableStateOf(movementId) }
    val compra = cuenta?.let(cards::movements).orEmpty().firstOrNull { it.id == compraId }
    val plan = compra?.let(cards::installment)
    val candidatas = cuenta?.let(cards::deferrable).orEmpty()
    val meses = CardInstallment.commonMonths
    var plazo by rememberSaveable(compraId) { mutableIntStateOf(plan?.let { meses.indexOf(it.months).coerceAtLeast(0) } ?: 0) }
    var tin by rememberSaveable(compraId) { mutableStateOf(tasa(plan?.rate ?: resumen?.terms?.installmentRate ?: 14.0)) }
    val action = rememberAction()
    val resources = LocalResources.current
    val valida = compra != null && (plan != null || candidatas.any { it.id == compra.id })
    StmScreen(
        topBar = { DetalleBar(nav, cuenta, cuenta?.name ?: stringResource(R.string.aplazar_compra_tarjeta)) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = {
            when {
                valida -> {
                    val total = -compra!!.amountMinor
                    val rate = leerTasa(tin)
                    val cuota = rate?.let { CardInstallment.payment(total, meses[plazo], it) }
                    HojaAplazar(
                        stringResource(R.string.aplazar_compra_aplazar, MovementText.display(compra.description)), "${Money.format(total)} · ${Fechas.corto(compra.day)}", plazo, { plazo = it }, tin, { tin = it },
                        cuota?.let { stringResource(R.string.aplazar_compra_mes, Money.format(it)) } ?: "—", cuota?.let { Money.format(it * meses[plazo] - total) } ?: "—", nav::back,
                        {
                            action.run {
                                cards.deferPurchase(compra, meses[plazo], cuenta!!, rate ?: throw AppError.InvalidInput(resources.getString(R.string.aplazar_compra_revisa_el_interes)))
                                nav.back()
                            }
                        },
                        plan?.let { p -> { action.run { cards.remove(p); nav.back() } } },
                    )
                }
                compraId == null && candidatas.isNotEmpty() -> SelectorSheet(
                    stringResource(R.string.aplazar_compra_elige_una_compra), candidatas.map { m -> "${MovementText.display(m.description)} · ${Money.format(-m.amountMinor)}" to { compraId = m.id } },
                ) { if (compraId == null) nav.back() }
                else -> BottomSheet(stringResource(R.string.aplazar_compra_no_se_puede_aplazar), null, onDismiss = nav::back) {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        Text(
                            stringResource(R.string.aplazar_compra_solo_compras_de_50_o_mas),
                            style = StmType.bodyMedium, color = c.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(16.dp))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Btn(stringResource(R.string.comun_entendido), nav::back, kind = BtnKind.Text) }
                    }
                }
            }
        },
    ) {
        // Bajo la hoja, el diseño solo muestra el próximo cargo de la tarjeta.
        StmCard {
            Text(stringResource(R.string.comun_proximo_cargo), style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.5.dp))
            Text(Money.format(resumen?.next?.amount ?: 0), style = StmType.displaySmall, color = c.onSurface)
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
            Segmented(listOf("3", "6", "9", stringResource(R.string.aplazar_compra_12_meses)), plazo, onPlazo)
            Spacer(Modifier.height(16.dp))
            SuffixOutlinedField(stringResource(R.string.aplazar_compra_tin_anual), tin, onTin, "%", c.surfaceContainerLow)
            Spacer(Modifier.height(16.dp))
            StmCard(color = c.surfaceContainerHighest) {
                Row(Modifier.fillMaxWidth().height(28.dp)) {
                    Text(stringResource(R.string.aplazar_compra_cuota), Modifier.weight(1f).alignByBaseline(), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                    Text(cuota, Modifier.alignByBaseline(), style = StmType.titleLarge, color = c.onSurface)
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.aplazar_compra_intereses_en_total), Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                    Text(intereses, style = StmType.labelLarge, color = c.onSurface)
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                if (onQuitar != null) Btn(stringResource(R.string.aplazar_compra_quitar_aplazado), onQuitar, kind = BtnKind.Text, color = c.error)
                Btn(stringResource(R.string.comun_cancelar), onCancelar, kind = BtnKind.Text)
                Btn(stringResource(R.string.aplazar_compra_aplazar_2), onAplazar)
            }
        }
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
