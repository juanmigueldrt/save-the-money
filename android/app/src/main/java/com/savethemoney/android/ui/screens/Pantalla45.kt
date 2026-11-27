package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
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
import com.savethemoney.android.data.ExtraBudget
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.util.UUID

/** 45 Crear o editar un presupuesto extra. */
@Composable
fun Pantalla45(nav: Nav, extraId: String?) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val hoy = finance.today()
    val editando = rememberRow(extraId) { id -> budgets.extraBudgets.firstOrNull { it.id == id } }
    if (extraId != null && editando == null) return NoEncontrado(nav)
    // Identificador del extra nuevo, uno por formulario y guardado al girar: reintentar el alta con el mismo no crea otro.
    val idExtra = rememberSaveable { UUID.randomUUID().toString() }
    val extra = remember { editando ?: ExtraBudget(idExtra, budgets.household.id, startsOn = budgets.period.start) }
    var nombre by rememberSaveable { mutableStateOf(extra.name) }
    var limite by rememberSaveable { mutableStateOf(if (extra.limit == 0L) "" else Money.input(extra.limit)) }
    var desde by rememberSaveable { mutableStateOf(extra.startsOn) }
    var conFin by rememberSaveable { mutableStateOf(extra.endsOn != null) }
    var hasta by rememberSaveable { mutableStateOf(extra.endsOn ?: extra.startsOn.plusDays(30)) }
    val categorias = remember { mutableStateListOf<String>().apply { addAll(extra.categoryIds) } }
    val cuentas = remember { mutableStateListOf<String>().apply { addAll(extra.accountIds) } }
    var favorito by rememberSaveable { mutableStateOf(extra.isFavorite) }
    var eligeFecha by remember { mutableStateOf<String?>(null) }
    var confirmar by remember { mutableStateOf(false) }
    val resources = LocalResources.current
    val guardar = {
        action.run {
            val amount = Money.entered(limite)?.takeIf { it > 0 } ?: throw AppError.InvalidInput(resources.getString(R.string.form_extra_escribe_un_limite_por_ejemplo_800))
            val updated = extra.copy(
                name = nombre, limit = amount, startsOn = desde, endsOn = if (conFin) hasta else null,
                categoryIds = categorias.sorted(), accountIds = cuentas.sorted(), isFavorite = favorito,
            )
            updated.issue?.let { throw AppError.InvalidInput(it) }
            budgets.save(updated)
            nav.back()
        }
    }
    StmScreen(
        topBar = {
            TopBar(if (editando == null) stringResource(R.string.form_extra_nuevo_presupuesto_extra) else editando.name, navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (confirmar && editando != null) {
            {
                StmDialog(
                    stringResource(R.string.form_extra_borrar, editando.name), stringResource(R.string.form_extra_los_movimientos_no_se_borran), icon = StmIcons.deleteForever,
                    onDismiss = { confirmar = false },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { confirmar = false }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_borrar), {
                            action.run {
                                budgets.delete(editando)
                                nav.back()
                            }
                        }, kind = BtnKind.Error)
                    },
                )
            }
        } else null,
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.form_extra_nombre_p_ej_vacaciones), nombre, { nombre = it })
            FilledField(stringResource(R.string.form_extra_limite_p_ej_800_00), limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            ListCard {
                ListItem(stringResource(R.string.form_extra_favorito_sale_en_resumen), trailing = { StmSwitch(favorito) { favorito = it } })
                Divider(inset = 16.dp)
                ListItem(stringResource(R.string.form_extra_con_fecha_de_fin), trailing = { StmSwitch(conFin) { conFin = it } })
            }
            FilledField(stringResource(R.string.form_extra_desde), Fechas.largo(desde, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "desde" })
            if (conFin) FilledField(stringResource(R.string.form_extra_hasta), Fechas.largo(hasta, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "hasta" })
            ListCard {
                ListHeader(stringResource(R.string.categorias_categorias))
                finance.categories(CategoryKind.Expense).forEachIndexed { i, category ->
                    if (i > 0) Divider(inset = 16.dp)
                    ListItem(category.name, trailing = {
                        StmSwitch(category.id in categorias) { on -> if (on) categorias += category.id else categorias -= category.id }
                    })
                }
            }
            Text(
                if (categorias.isEmpty()) stringResource(R.string.form_extra_si_no_eliges_ninguna_cuenta_todo) else stringResource(R.string.form_extra_elegidas, categorias.size),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            ListCard {
                ListHeader(stringResource(R.string.form_extra_cuentas))
                finance.activeAccounts.forEachIndexed { i, account ->
                    if (i > 0) Divider(inset = 16.dp)
                    ListItem(account.name, trailing = {
                        StmSwitch(account.id in cuentas) { on -> if (on) cuentas += account.id else cuentas -= account.id }
                    })
                }
            }
            Text(
                if (cuentas.isEmpty()) stringResource(R.string.form_extra_si_no_eliges_ninguna_cuentan_todas) else stringResource(R.string.form_extra_elegidas, cuentas.size),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            if (editando != null) Btn(stringResource(R.string.form_extra_borrar_presupuesto_extra), { confirmar = true }, kind = BtnKind.Text, color = c.error)
            Spacer(Modifier.height(8.dp))
        }
    }
    eligeFecha?.let { campo ->
        SelectorFecha(if (campo == "hasta") hasta else desde, { if (campo == "hasta") hasta = it else desde = it }) { eligeFecha = null }
    }
}
