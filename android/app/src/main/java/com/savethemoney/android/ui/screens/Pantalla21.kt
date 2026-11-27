package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 21 Nuevo o editar pago fijo: tipo, importe, periodicidad, precio de oferta con contador de cargos y avisos. */
@Composable
fun Pantalla21(nav: Nav, seriesId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val editando = rememberRow(seriesId) { id -> planning.series.firstOrNull { it.id == id } }
    if (seriesId != null && editando == null) return NoEncontrado(nav)
    val base = editando
    val tipos = RecurringKind.entries
    var kind by rememberSaveable(base) { mutableIntStateOf(tipos.indexOf(base?.kind ?: RecurringKind.Subscription)) }
    var name by rememberSaveable(base) { mutableStateOf(base?.name ?: "") }
    var amount by rememberSaveable(base) { mutableStateOf(base?.let { Money.format(it.amountMinor, symbol = false) } ?: "") }
    var cada by remember(base) { mutableStateOf(base?.recurrence ?: Recurrence.Monthly) }
    var fecha by rememberSaveable(base) { mutableStateOf(base?.startDay ?: finance.today()) }
    var conFin by rememberSaveable(base) { mutableStateOf(base?.endDay != null) }
    var fin by rememberSaveable(base) { mutableStateOf(base?.endDay ?: finance.today()) }
    var cuenta by rememberSaveable(base) { mutableStateOf(base?.accountId) }
    var categoria by rememberSaveable(base) { mutableStateOf(base?.categoryId) }
    var offer by rememberSaveable(base) { mutableStateOf(base?.hasIntro ?: false) }
    var offerPrice by rememberSaveable(base) { mutableStateOf(base?.introMinor?.let { Money.format(it, symbol = false) } ?: "") }
    var charges by rememberSaveable(base) { mutableIntStateOf(base?.introCharges ?: 3) }
    var remind by rememberSaveable(base) { mutableStateOf(base == null || base.remindDaysBefore != null) }
    var dias by rememberSaveable(base) { mutableIntStateOf(base?.remindDaysBefore ?: 1) }
    var pendiente by rememberSaveable(base) { mutableStateOf(base?.createsPending ?: true) }
    // Identificador del pago fijo nuevo, uno por formulario: reintentar el alta con el mismo no crea otro.
    val idPago = rememberSaveable { java.util.UUID.randomUUID().toString() }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf<String?>(null) }
    var confirmar by remember { mutableStateOf(false) }
    val action = rememberAction()
    val esIngreso = tipos[kind] == RecurringKind.Income
    val tipoCategoria = if (esIngreso) CategoryKind.Income else CategoryKind.Expense
    val resources = LocalResources.current

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val dinero = Money.entered(amount)?.takeIf { it > 0 } ?: falla(resources.getString(R.string.comun_el_importe_no_es_valido))
        val conOferta = offer && !esIngreso
        val oferta = if (conOferta) Money.entered(offerPrice)?.takeIf { it > 0 } ?: falla(resources.getString(R.string.form_pago_fijo_el_precio_de_oferta_no_es)) else null
        val item = (editando ?: RecurringSeries(idPago, planning.household.id, name, amountMinor = dinero, startsOn = fecha.toString())).copy(
            name = name, kind = tipos[kind], amountMinor = dinero, accountId = cuenta, categoryId = categoria,
            every = cada.every, unit = cada.unit, startsOn = fecha.toString(), endsOn = if (conFin) fin.toString() else null,
            remindDaysBefore = if (remind) dias else null, introMinor = oferta, introCharges = if (conOferta) charges else null,
            createsPending = pendiente,
        )
        planning.save(item)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando != null) stringResource(R.string.form_pago_fijo_editar_pago_fijo) else stringResource(R.string.form_pago_fijo_nuevo_pago_fijo), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            confirmar && editando != null -> {
                {
                    StmDialog(
                        stringResource(R.string.form_pago_fijo_que_quieres_hacer_con_este_pago),
                        stringResource(R.string.form_pago_fijo_si_dejas_de_pagarlo_se_guarda),
                        icon = StmIcons.deleteForever,
                        onDismiss = { confirmar = false },
                        actions = { Btn(stringResource(R.string.comun_cancelar), { confirmar = false }, kind = BtnKind.Text) },
                    ) {
                        Spacer(Modifier.height(16.dp))
                        Btn(stringResource(R.string.form_pago_fijo_dejar_de_pagarlo_desde_hoy), {
                            action.run {
                                planning.save(editando.copy(endsOn = maxOf(editando.startDay, finance.today()).toString()))
                                nav.back()
                            }
                        }, Modifier.fillMaxWidth(), kind = BtnKind.Tonal)
                        Spacer(Modifier.height(8.dp))
                        Btn(stringResource(R.string.form_pago_fijo_borrarlo_con_sus_pendientes), {
                            action.run {
                                planning.delete(editando)
                                nav.back()
                            }
                        }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
                    }
                }
            }
            selector != null -> {
                {
                    val cerrar = { selector = null }
                    when (selector) {
                        "cada" -> SelectorSheet(
                            stringResource(R.string.form_movimiento_frecuencia),
                            (if (cada in Recurrence.Common) Recurrence.Common else Recurrence.Common + cada).map { r -> r.title to { cada = r } },
                            cerrar,
                        )
                        "cuenta" -> SelectorSheet(
                            stringResource(R.string.comun_cuenta),
                            listOf<Pair<String, () -> Unit>>(stringResource(R.string.form_pago_fijo_sin_cuenta) to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                            cerrar,
                        )
                        else -> SelectorSheet(
                            stringResource(R.string.comun_categoria),
                            listOf<Pair<String, () -> Unit>>(stringResource(R.string.comun_sin_categoria) to { categoria = null }) + finance.categories(tipoCategoria).map { x -> x.name to { categoria = x.id } },
                            cerrar,
                        )
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(
                tipos.map { it.title }, kind,
                { nuevo ->
                    kind = nuevo
                    // Una categoría de gasto no vale para un ingreso, y al revés.
                    val quiere = if (tipos[nuevo] == RecurringKind.Income) CategoryKind.Income else CategoryKind.Expense
                    if (finance.category(categoria)?.kind != quiere) categoria = null
                },
            )
            FilledField(stringResource(R.string.comun_nombre), name, { name = it })
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledField(stringResource(R.string.comun_importe), amount, { amount = it }, Modifier.weight(1f), suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
                FilledField(stringResource(R.string.comun_cada), periodo(cada), modifier = Modifier.weight(1f), trailing = StmIcons.arrowDropDown, onClick = { selector = "cada" })
            }
            FilledField(
                if (editando != null) stringResource(R.string.form_pago_fijo_desde) else stringResource(R.string.comun_proximo_cargo), Fechas.largo(fecha, finance.today()),
                trailing = StmIcons.calendarToday, onClick = { eligeFecha = "inicio" },
            )
            if (!esIngreso) {
                ListCard {
                    ListItem(
                        stringResource(R.string.form_pago_fijo_precio_de_oferta_al_principio), stringResource(R.string.form_pago_fijo_por_ejemplo_3_meses_a_5),
                        trailing = { StmSwitch(offer) { offer = it } },
                    )
                }
                if (offer) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilledField(
                            stringResource(R.string.form_pago_fijo_precio_de_oferta), offerPrice, { offerPrice = it }, Modifier.weight(1f),
                            suffix = "€", keyboard = KeyboardType.Decimal, calculator = true,
                        )
                        Stepper(pluralStringResource(R.plurals.form_pago_fijo_cargos, charges, charges), { charges = (charges - 1).coerceAtLeast(1) }, { charges = (charges + 1).coerceAtMost(36) })
                    }
                }
            }
            ListCard {
                ListItem(stringResource(R.string.form_pago_fijo_se_comparte_con_todo_el_hogar))
                Divider(inset = 16.dp)
                ListItem(stringResource(R.string.form_pago_fijo_avisarme, textoAviso(dias)), trailing = { StmSwitch(remind) { remind = it } })
            }
            // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
            if (remind) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.form_pago_fijo_cuando_avisar), Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Stepper(if (dias == 0) stringResource(R.string.form_pago_fijo_mismo_dia) else pluralStringResource(R.plurals.form_pago_fijo_dias, dias, dias), { dias = (dias - 1).coerceAtLeast(0) }, { dias = (dias + 1).coerceAtMost(14) })
                }
            }
            FilledField(stringResource(R.string.comun_cuenta), finance.account(cuenta)?.name ?: stringResource(R.string.form_pago_fijo_sin_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField(stringResource(R.string.comun_categoria), finance.category(categoria)?.name ?: stringResource(R.string.comun_sin_categoria), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
            ListCard {
                ListItem(
                    stringResource(R.string.form_pago_fijo_apuntarlo_como_pendiente_al_llegar),
                    stringResource(R.string.form_pago_fijo_el_dia_del_cargo_aparece_en),
                    supportingLines = 4,
                    trailing = { StmSwitch(pendiente) { pendiente = it } },
                )
            }
            ListCard {
                ListItem(stringResource(R.string.form_pago_fijo_tiene_fecha_de_fin), trailing = { StmSwitch(conFin) { conFin = it } })
            }
            if (conFin) {
                FilledField(stringResource(R.string.form_pago_fijo_ultimo_cargo), Fechas.largo(fin, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "fin" })
            }
            if (editando != null) {
                Btn(
                    if (editando.isArchived) stringResource(R.string.form_pago_fijo_reactivar) else stringResource(R.string.form_pago_fijo_archivar_ya_no_se_paga),
                    {
                        action.run {
                            planning.setArchived(editando, !editando.isArchived)
                            nav.back()
                        }
                    },
                    kind = BtnKind.Text,
                )
                Btn(stringResource(R.string.comun_borrar), { confirmar = true }, kind = BtnKind.Text, color = c.error)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    eligeFecha?.let { campo ->
        SelectorFecha(if (campo == "fin") fin else fecha, { if (campo == "fin") fin = it else fecha = it }) { eligeFecha = null }
    }
}
