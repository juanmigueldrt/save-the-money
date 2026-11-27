package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.YearMonth
import java.time.temporal.ChronoUnit

/** 24 Nueva o editar meta: tipo, nombre, importe (con error), fecha, aporte necesario y datos opcionales. */
@Composable
fun Pantalla24(nav: Nav, goalId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val editando = rememberRow(goalId, planning::goal)
    if (goalId != null && editando == null) return NoEncontrado(nav)
    // Identificador de la meta nueva, uno por formulario: reintentar el alta con el mismo no crea otra.
    val idMeta = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val base = editando
    val hoy = planning.today()
    var kind by rememberSaveable(base) { mutableIntStateOf(if (base?.kind == GoalKind.Debt) 1 else 0) }
    var name by rememberSaveable(base) { mutableStateOf(base?.name ?: "") }
    var target by rememberSaveable(base) { mutableStateOf(base?.let { Money.format(it.targetMinor, symbol = false) } ?: "") }
    var fecha by rememberSaveable(base) { mutableStateOf(base?.targetDay) }
    var starting by rememberSaveable(base) { mutableStateOf(base?.startingMinor?.takeIf { it != 0L }?.let { Money.format(it, symbol = false) } ?: "") }
    var plan by rememberSaveable(base) { mutableStateOf(base?.monthlyPlanMinor?.let { Money.format(it, symbol = false) } ?: "") }
    var cuenta by rememberSaveable(base) { mutableStateOf(base?.accountId) }
    var eligeFecha by remember { mutableStateOf(false) }
    var eligeCuenta by remember { mutableStateOf(false) }
    var confirmar by remember { mutableStateOf(false) }
    val action = rememberAction()
    val deuda = kind == 1
    val invalid = target.isNotEmpty() && (Money.entered(target) ?: 0) <= 0
    val objetivo = Money.entered(target)?.takeIf { it > 0 } ?: base?.targetMinor
    val limite = fecha
    val necesario = if (limite != null && objetivo != null) {
        GoalProgress(
            Goal(editando?.id ?: "", "", name, targetMinor = objetivo, startingMinor = Money.entered(starting) ?: 0, targetOn = limite.toString()),
            planning.contributions, hoy,
        ).neededMonthly
    } else {
        null
    }
    val resources = LocalResources.current

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val meta = Money.entered(target)?.takeIf { it > 0 } ?: falla(if (deuda) resources.getString(R.string.form_meta_indica_cuanto_se_debia) else resources.getString(R.string.form_meta_indica_cuanto_quieres_juntar))
        // Un campo vacío es cero o nada; lo que no se entiende, se avisa.
        val inicio = if (starting.isBlank()) 0 else Money.entered(starting) ?: falla(resources.getString(R.string.form_meta_algun_importe_no_es_valido))
        val previsto = if (plan.isBlank()) null else Money.entered(plan) ?: falla(resources.getString(R.string.form_meta_algun_importe_no_es_valido))
        val item = (editando ?: Goal(idMeta, planning.household.id, name, targetMinor = meta)).copy(
            name = name, kind = if (deuda) GoalKind.Debt else GoalKind.Savings, targetMinor = meta, startingMinor = inicio,
            monthlyPlanMinor = previsto, targetOn = fecha?.toString(), accountId = cuenta,
        )
        planning.save(item)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando != null) stringResource(R.string.form_meta_editar_meta) else stringResource(R.string.form_meta_nueva_meta), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            confirmar && editando != null -> {
                {
                    StmDialog(
                        stringResource(R.string.metas_borrar_esta_meta),
                        stringResource(R.string.metas_se_borran_tambien_sus_aportaciones),
                        icon = StmIcons.deleteForever,
                        onDismiss = { confirmar = false },
                        actions = {
                            Btn(stringResource(R.string.comun_cancelar), { confirmar = false }, kind = BtnKind.Text)
                            Btn(stringResource(R.string.comun_borrar), {
                                action.run {
                                    planning.delete(editando)
                                    // Se sale también del detalle, que ya no existe.
                                    nav.back()
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        },
                    )
                }
            }
            eligeCuenta -> {
                {
                    SelectorSheet(
                        stringResource(R.string.form_meta_cuenta_asociada),
                        listOf<Pair<String, () -> Unit>>(stringResource(R.string.form_meta_ninguna) to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } },
                        { eligeCuenta = false },
                    )
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf(stringResource(R.string.form_meta_ahorro), stringResource(R.string.form_meta_pagar_deuda)), kind, { kind = it })
            FilledField(stringResource(R.string.form_meta_nombre_de_la_meta), name, { name = it }, supporting = stringResource(R.string.form_meta_lo_veras_en_tu_lista_de))
            FilledField(
                if (deuda) stringResource(R.string.form_meta_cuanto_se_debia_al_empezar) else stringResource(R.string.form_meta_importe_objetivo), target, { target = it }, keyboard = KeyboardType.Decimal, calculator = true,
                trailing = if (invalid) StmIcons.error else null,
                supporting = if (invalid) stringResource(R.string.form_meta_escribe_un_importe_por_ejemplo_150) else null,
                error = invalid,
            )
            FilledField(
                stringResource(R.string.form_meta_fecha_limite), limite?.let { "${Fechas.mesTitulo(it)} ${it.year}" } ?: stringResource(R.string.form_meta_sin_fecha),
                trailing = StmIcons.calendarToday, onClick = { eligeFecha = true },
            )
            if (necesario != null && limite != null) {
                val meses = maxOf(1, ChronoUnit.MONTHS.between(YearMonth.from(hoy), YearMonth.from(limite)).toInt())
                StmCard(color = c.surfaceContainerHighest) {
                    Text(stringResource(R.string.form_meta_aporte_mensual_necesario), style = StmType.labelMedium, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.form_meta_mes, importe(necesario)), style = StmType.titleLarge, color = c.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(pluralStringResource(R.plurals.form_meta_durante_meses, meses, meses), style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
            ListCard {
                ListItem(stringResource(R.string.form_meta_se_comparte_con_el_hogar), stringResource(R.string.form_meta_todos_podran_ver_y_aportar))
            }
            // Lo que el diseño no dibuja y iOS sí permite va debajo, para no mover lo anterior.
            if (limite != null) Btn(stringResource(R.string.form_meta_quitar_la_fecha), { fecha = null }, kind = BtnKind.Text)
            FilledField(if (deuda) stringResource(R.string.form_meta_lo_que_ya_has_pagado_opcional) else stringResource(R.string.form_meta_lo_que_ya_tienes_opcional), starting, { starting = it }, keyboard = KeyboardType.Decimal, calculator = true)
            FilledField(stringResource(R.string.form_meta_aportacion_mensual_prevista), plan, { plan = it }, keyboard = KeyboardType.Decimal, calculator = true)
            FilledField(stringResource(R.string.form_meta_cuenta_asociada), finance.account(cuenta)?.name ?: stringResource(R.string.form_meta_ninguna), trailing = StmIcons.arrowDropDown, onClick = { eligeCuenta = true })
            if (editando != null) {
                Btn(
                    if (editando.isArchived) stringResource(R.string.comun_desarchivar) else stringResource(R.string.comun_archivar),
                    {
                        action.run {
                            planning.setArchived(editando, !editando.isArchived)
                            nav.back()
                        }
                    },
                    kind = BtnKind.Text,
                )
                Btn(stringResource(R.string.metas_borrar_meta_y_aportaciones), { confirmar = true }, kind = BtnKind.Text, color = c.error)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    if (eligeFecha) SelectorFecha(limite ?: hoy.plusYears(1), { fecha = it }) { eligeFecha = false }
}
