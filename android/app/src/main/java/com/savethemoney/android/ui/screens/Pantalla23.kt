package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.roundToInt

/** 23 Detalle de meta: lo ahorrado, la proyección y las aportaciones. */
@Composable
fun Pantalla23(nav: Nav, goalId: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val goal = planning.goal(goalId) ?: return NoEncontrado(nav)
    val p = planning.progress(goal)
    val aportes = planning.contributions(goal)
    val miembros by produceState(emptyList<HouseholdMember>(), planning.household.id) {
        value = runCatching { session.backend.members(planning.household.id) }.getOrDefault(emptyList())
    }
    var borrando by remember { mutableStateOf<GoalContribution?>(null) }
    var opciones by remember { mutableStateOf(false) }
    var borrarMeta by remember { mutableStateOf(false) }
    val action = rememberAction()
    val editarMeta = {
        nav.go(Route.FormMeta(goal.id))
    }
    StmScreen(
        topBar = {
            TopBar(goal.trimmedName, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    nav.go(Route.FormMeta(goal.id))
                }, contentDescription = stringResource(R.string.comun_editar))
                IconBtn(StmIcons.moreVert, { opciones = true }, contentDescription = stringResource(R.string.comun_mas_opciones))
            }
        },
        fab = {
            Fab(if (goal.kind == GoalKind.Savings) stringResource(R.string.metas_aportar) else stringResource(R.string.metas_apuntar_pago)) {
                nav.go(Route.Aportar(goal.id))
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = borrando?.let { item ->
            {
                SelectorSheet(
                    Fechas.corto(item.day),
                    listOf<Pair<String, () -> Unit>>(stringResource(R.string.metas_borrar_esta_aportacion) to { action.run { planning.delete(item) } }),
                    { borrando = null },
                )
            }
        } ?: if (borrarMeta) {
            {
                StmDialog(
                    stringResource(R.string.metas_borrar_esta_meta), stringResource(R.string.metas_se_borran_tambien_sus_aportaciones),
                    icon = StmIcons.deleteForever, onDismiss = { borrarMeta = false },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { borrarMeta = false }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_borrar), {
                            action.run {
                                planning.delete(goal)
                                nav.back()
                            }
                        }, kind = BtnKind.Error, enabled = !action.busy)
                    },
                )
            }
        } else if (opciones) {
            {
                BottomSheet(goal.trimmedName, onDismiss = { opciones = false }) {
                    SheetItem(StmIcons.edit, stringResource(R.string.comun_editar)) {
                        opciones = false
                        editarMeta()
                    }
                    SheetItem(StmIcons.visibilityOff, if (goal.isArchived) stringResource(R.string.comun_desarchivar) else stringResource(R.string.comun_archivar)) {
                        opciones = false
                        action.run {
                            planning.setArchived(goal, !goal.isArchived)
                            if (!goal.isArchived) nav.back()
                        }
                    }
                    SheetItem(StmIcons.delete, stringResource(R.string.metas_borrar_meta_y_aportaciones), Stm.colors.error, Stm.colors.error) {
                        opciones = false
                        borrarMeta = true
                    }
                }
            }
        } else null,
    ) {
        Spacer(Modifier.height(8.dp))
        Text(if (goal.kind == GoalKind.Savings) stringResource(R.string.metas_ahorrado) else stringResource(R.string.metas_pagado), style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(importe(p.saved), style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.dp))
        Text(stringResource(R.string.metas_de_2, importe(goal.targetMinor), (p.fraction * 100).roundToInt()), style = StmType.bodyMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        GoalProgress(p.fraction)
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text(stringResource(R.string.metas_proyeccion), style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            curva(p)?.let { puntos ->
                LineChart(puntos, plotHeight = 120.dp, color = c.tertiary)
                Spacer(Modifier.height(8.dp))
            }
            Text(proyeccion(p, planning.today()), style = StmType.bodyMedium, color = if (p.isOnTrack == false) c.error else c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.metas_aportaciones))
            if (aportes.isEmpty()) ListItem(stringResource(R.string.metas_todavia_no_hay_aportaciones))
            aportes.forEachIndexed { i, item ->
                if (i > 0) Divider()
                val nombre = miembros.firstOrNull { it.profile.id == item.createdBy }?.profile?.name
                ListItem(
                    Money.format(item.amountMinor, decimals = item.amountMinor % 100 != 0L, signed = true),
                    listOfNotNull(Fechas.corto(item.day), nombre).joinToString(" · "),
                    leading = { Avatar(nombre?.take(1)?.uppercase() ?: "·") },
                    trailing = item.note?.let { n -> { Note(n) } },
                    onClick = { borrando = item },
                )
            }
        }
        Spacer(Modifier.height(72.dp))
    }
}

/** Texto de la proyección: cuándo se llega, cuándo con 100 € más y si da tiempo a la fecha límite. */
@Composable private fun proyeccion(p: GoalProgress, hoy: LocalDate): String {
    if (p.isReached) return if (p.goal.kind == GoalKind.Savings) stringResource(R.string.metas_meta_conseguida) else stringResource(R.string.metas_deuda_pagada)
    val partes = mutableListOf<String>()
    val ritmo = p.monthlyPace
    val llegada = p.projectedMonth
    if (ritmo != null && llegada != null) {
        partes += stringResource(R.string.metas_con_mes_llegas_en_de, importe(ritmo), Fechas.mes(llegada.atDay(1)), llegada.year)
        val mas = ritmo + 10_000
        val antes = YearMonth.from(hoy).plusMonths((p.remaining + mas - 1) / mas)
        if (antes != llegada) partes += stringResource(R.string.metas_con_mes_en, importe(mas), Fechas.mes(antes.atDay(1)))
    } else {
        partes += stringResource(R.string.metas_faltan_anade_una_aportacion_o_un, importe(p.remaining))
    }
    val necesario = p.neededMonthly
    val limite = p.goal.targetDay
    if (necesario != null && limite != null) {
        partes += if (p.isOnTrack == true) stringResource(R.string.metas_para_el_vas_bien, limite.dayOfMonth, Fechas.mes(limite), limite.year)
        else stringResource(R.string.metas_para_el_necesitas, limite.dayOfMonth, Fechas.mes(limite), limite.year, importe(necesario))
    }
    return partes.joinToString(". ") + "."
}

/** Nueve puntos (0–1) de lo acumulado desde hoy hasta llegar; null si no hay ritmo con el que proyectar. */
private fun curva(p: GoalProgress): List<Float>? {
    val ritmo = p.monthlyPace?.takeIf { it > 0 } ?: return null
    val meses = p.monthsLeft?.takeIf { it > 0 } ?: return null
    return List(9) { i -> ((p.saved + ritmo * meses * i / 8f) / p.goal.targetMinor).coerceIn(0f, 1f) }
}

/** Texto final secundario de un elemento de lista. */
@Composable
private fun Note(text: String) {
    Text(text, Modifier.widthIn(max = 120.dp), style = StmType.bodyMediumTight, color = Stm.colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
}
