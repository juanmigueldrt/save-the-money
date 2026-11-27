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
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.PendingCharge
import com.savethemoney.android.data.RecurringKind
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
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlin.math.abs

/** 46 Confirmar un cargo: se puede cambiar el importe, el día, la cuenta y la categoría antes de apuntarlo. */
@Composable
fun Pantalla46(nav: Nav, chargeId: String) {
    val c = Stm.colors
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    // Si ya se confirmó o saltó (aquí o en otro dispositivo), deja de estar pendiente: se dice y se vuelve.
    val item: PendingCharge = rememberRow(chargeId) { id -> planning.pending.firstOrNull { it.id == id } } ?: return NoEncontrado(nav)
    val esIngreso = item.series.kind == RecurringKind.Income
    var importe by rememberSaveable { mutableStateOf(Money.format(kotlin.math.abs(item.charge.amountMinor), symbol = false)) }
    var dia by rememberSaveable { mutableStateOf(item.charge.due) }
    var cuenta by rememberSaveable { mutableStateOf(item.series.accountId ?: finance.activeAccounts.firstOrNull { it.isDefault }?.id) }
    var categoria by rememberSaveable { mutableStateOf(item.series.categoryId) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()
    val resources = LocalResources.current
    val confirmar = {
        action.run {
            val dinero = Money.entered(importe)?.takeIf { it > 0 } ?: throw AppError.InvalidInput(resources.getString(R.string.confirmar_cargo_escribe_el_importe_por_ejemplo_12))
            val id = cuenta ?: throw AppError.InvalidInput(resources.getString(R.string.confirmar_cargo_elige_la_cuenta_del_cargo))
            finance.confirm(item, MovementDraft(id, categoria, dia, if (esIngreso) dinero else -dinero, item.series.trimmedName))
            nav.back()
        }
    }
    StmScreen(
        topBar = {
            TopBar(item.series.trimmedName, navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_confirmar), confirmar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = selector?.let { campo ->
            {
                val cerrar = { selector = null }
                if (campo == "cuenta") {
                    SelectorSheet(stringResource(R.string.comun_cuenta), finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                } else {
                    SelectorSheet(
                        stringResource(R.string.comun_categoria),
                        listOf<Pair<String, () -> Unit>>(stringResource(R.string.comun_sin_categoria) to { categoria = null }) +
                            finance.categories(if (esIngreso) CategoryKind.Income else CategoryKind.Expense).map { x -> x.name to { categoria = x.id } },
                        cerrar,
                    )
                }
            }
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.comun_importe), importe, { importe = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            FilledField(stringResource(R.string.confirmar_cargo_dia), Fechas.largo(dia, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField(stringResource(R.string.comun_cuenta), finance.account(cuenta)?.name ?: stringResource(R.string.comun_elige_una_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField(stringResource(R.string.comun_categoria), finance.category(categoria)?.name ?: stringResource(R.string.comun_sin_categoria), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
            Text(
                stringResource(R.string.confirmar_cargo_se_apunta_como_un_movimiento),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
    if (eligeFecha) SelectorFecha(dia, { dia = it }) { eligeFecha = false }
}
