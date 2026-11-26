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
import androidx.compose.ui.unit.dp
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
            LargeTitle("Metas", "Fija metas (y cúmplelas)")
        },
        bottomBar = { NavBar(Tab.Metas, nav::tab) },
        fab = { Fab("Nueva meta") { nueva() } },
        snackbar = planning.error?.let { e -> { Snackbar(e) } },
    ) {
        ChipRow {
            listOf("Ahorro", "Deudas", "Completadas").forEachIndexed { i, label ->
                Chip(label, selected = i == filter, onClick = { filter = i })
            }
            if (archivadas.isNotEmpty() || filter == 3) Chip("Archivadas (${archivadas.size})", selected = filter == 3, onClick = { filter = 3 })
        }
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (planning.progress.isEmpty() && filter != 3) {
                StmCard {
                    Text("Sin metas todavía", style = StmType.titleMedium, color = c.onSurface)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Crea una meta para ahorrar (un viaje, un fondo de emergencia) o para terminar de pagar una deuda. Verás cuánto falta y cuándo llegarás.",
                        style = StmType.bodyMedium, color = c.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Btn("Crear una meta", ::nueva)
                }
            } else if (visibles.isEmpty()) {
                Text("No hay metas en esta sección.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            visibles.forEach { p ->
                val deuda = p.goal.kind == GoalKind.Debt
                GoalCard(
                    iconoMeta(p.goal), p.goal.trimmedName, resumenMeta(p), p.fraction, importe(p.saved), "de ${importe(p.goal.targetMinor)}",
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

private fun resumenMeta(p: GoalProgress): String {
    val g = p.goal
    val llegada = p.projectedMonth
    val limite = g.targetDay
    val faltan = p.monthsLeft
    return when {
        p.isReached -> if (g.kind == GoalKind.Savings) "¡Meta conseguida!" else "¡Deuda pagada!"
        g.kind == GoalKind.Debt && faltan != null -> if (faltan == 1) "Deuda · 1 cuota" else "Deuda · $faltan cuotas"
        llegada != null && faltan != null ->
            "A este ritmo, en ${Fechas.mes(llegada.atDay(1))}" + if (faltan >= 12) " de ${llegada.year}" else ""
        limite != null -> "Compartida · ${Fechas.mes(limite)} ${limite.year}"
        else -> "Faltan ${importe(p.remaining)}"
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
