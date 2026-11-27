package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlin.math.roundToInt

/** 22 Metas: filtros y tarjetas de cada meta con su progreso. */
@Composable
fun Pantalla22(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    var filter by remember { mutableIntStateOf(0) }
    val archivadas = planning.goals.filter { it.isArchived }.map(planning::progress)
    val visibles = if (filter == 3) archivadas else planning.progress.filter { p ->
        when (filter) {
            0 -> p.goal.kind == GoalKind.Savings && !p.isReached
            1 -> p.goal.kind == GoalKind.Debt && !p.isReached
            else -> p.isReached
        }
    }
    fun nueva() {
        nav.go(Route.FormMeta())
    }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null)
            LargeTitle(stringResource(R.string.metas_metas), stringResource(R.string.metas_fija_metas_y_cumplelas))
        },
        bottomBar = { NavBar(Tab.Metas, nav::tab) },
        fab = { Fab(stringResource(R.string.form_meta_nueva_meta)) { nueva() } },
        snackbar = planning.error?.let { e -> { Snackbar(e) } },
    ) {
        ChipRow {
            listOf(stringResource(R.string.metas_ahorro), stringResource(R.string.metas_deudas), stringResource(R.string.metas_completadas)).forEachIndexed { i, label ->
                Chip(label, selected = i == filter, onClick = { filter = i })
            }
            if (archivadas.isNotEmpty() || filter == 3) Chip(stringResource(R.string.metas_archivadas, archivadas.size), selected = filter == 3, onClick = { filter = 3 })
        }
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (planning.progress.isEmpty() && filter != 3) {
                StmCard {
                    Text(stringResource(R.string.metas_sin_metas_todavia), style = StmType.titleMedium, color = c.onSurface)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        stringResource(R.string.metas_crea_una_meta_para_ahorrar_un),
                        style = StmType.bodyMedium, color = c.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Btn(stringResource(R.string.metas_crear_una_meta), ::nueva)
                }
            } else if (visibles.isEmpty()) {
                Text(stringResource(R.string.metas_no_hay_metas_en_esta_seccion), style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            visibles.forEach { p ->
                val deuda = p.goal.kind == GoalKind.Debt
                GoalCard(
                    iconoMeta(p.goal), p.goal.trimmedName, resumenMeta(p), p.fraction, importe(p.saved), stringResource(R.string.metas_de, importe(p.goal.targetMinor)),
                    if (deuda) c.errorContainer else c.secondaryContainer,
                    if (deuda) c.onErrorContainer else c.onSecondaryContainer,
                ) {
                    nav.go(Route.Meta(p.goal.id))
                }
            }
        }
    }
}

private fun iconoMeta(g: Goal): ImageVector {
    val n = g.trimmedName.lowercase()
    return when {
        "viaje" in n -> StmIcons.flight
        "coche" in n -> StmIcons.directionsCar
        g.kind == GoalKind.Debt -> StmIcons.creditCard
        else -> StmIcons.savings
    }
}

@Composable private fun resumenMeta(p: GoalProgress): String {
    val g = p.goal
    val llegada = p.projectedMonth
    val limite = g.targetDay
    val faltan = p.monthsLeft
    return when {
        p.isReached -> if (g.kind == GoalKind.Savings) stringResource(R.string.metas_meta_conseguida) else stringResource(R.string.metas_deuda_pagada)
        g.kind == GoalKind.Debt && faltan != null -> pluralStringResource(R.plurals.metas_deuda_cuotas, faltan, faltan)
        llegada != null && faltan != null ->
            if (faltan >= 12) stringResource(R.string.metas_a_este_ritmo_en_mes_de_ano, Fechas.mes(llegada.atDay(1)), llegada.year) else stringResource(R.string.metas_a_este_ritmo_en_mes, Fechas.mes(llegada.atDay(1)))
        limite != null -> stringResource(R.string.metas_compartida, Fechas.mes(limite), limite.year)
        else -> stringResource(R.string.metas_faltan, importe(p.remaining))
    }
}

/** Tarjeta de una meta: icono, nombre, porcentaje, progreso e importes. */
@Composable
private fun GoalCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    fraction: Float,
    saved: String,
    total: String,
    container: Color = Stm.colors.secondaryContainer,
    tint: Color = Stm.colors.onSecondaryContainer,
    onClick: () -> Unit,
) {
    val c = Stm.colors
    StmCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LeadIcon(icon, container, tint)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = StmType.titleMedium, color = c.onSurface)
                Text(subtitle, style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.width(12.dp))
            Text("${(fraction * 100).roundToInt()}%", style = StmType.labelLarge, color = c.onSurface)
        }
        Spacer(Modifier.height(12.dp))
        GoalProgress(fraction)
        Spacer(Modifier.height(12.dp))
        Row {
            Text(saved, Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurface)
            Text(total, style = StmType.bodyMedium, color = c.onSurfaceVariant)
        }
    }
}
