package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.BudgetPeriod
import com.savethemoney.android.data.ExtraBudget
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.PeriodInsights
import com.savethemoney.android.ui.BudgetModel
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch

// PeriodViews.swift: selector de periodo, «Puedes gastar hoy», día de cobro y presupuestos extra.

/** ‹ 25 oct – 24 nov ›, compartido por Presupuesto y Flujo. Tocar el título vuelve al periodo de hoy. */
@Composable
internal fun SelectorPeriodo(budgets: BudgetModel) {
    val c = Stm.colors
    val scope = rememberCoroutineScope()
    val period = budgets.period
    val rango = "${BudgetPeriod.dayMonth(period.start)} – ${BudgetPeriod.dayMonth(period.end)}"
    StmCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconBtn(StmIcons.chevronLeft, { scope.launch { budgets.showPrevious() } }, contentDescription = "Periodo anterior")
            Column(
                Modifier.weight(1f).tap(role = Role.Button) { scope.launch { budgets.showCurrent() } },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(period.title, style = StmType.titleMedium, color = c.onSurface, textAlign = TextAlign.Center)
                Text(if (budgets.isCurrentPeriod) "$rango · en curso" else rango, style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            IconBtn(StmIcons.chevronRight, { scope.launch { budgets.showNext() } }, contentDescription = "Periodo siguiente")
        }
    }
}

/** Cuánto puedes gastar hoy y cuántos días faltan para cobrar, del periodo en curso. */
@Composable
internal fun GastarHoyCard(budgets: BudgetModel, finance: FinanceModel, onClick: (() -> Unit)? = null) {
    val c = Stm.colors
    val insights = budgets.insights(finance.categories)
    StmCard(onClick = onClick) {
        Text("Puedes gastar hoy", style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.dp))
        Text(Money.format(insights.perDay), style = StmType.displaySmall, color = if (insights.left < 0) c.error else c.onSurface)
        Spacer(Modifier.height(4.dp))
        Text(detalle(insights), style = StmType.bodyMedium, color = c.onSurfaceVariant)
        Text(
            if (budgets.hasOwnSchedule) budgets.schedule.summary else "Dinos cuándo cobras en Presupuesto › Día de cobro.",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
    }
}

private fun detalle(insights: PeriodInsights): String {
    val dias = if (insights.daysToPayday == 1) "1 día" else "${insights.daysToPayday} días"
    return if (insights.left < 0) "Te has pasado ${Money.format(-insights.left)} · faltan $dias para cobrar"
    else "Te quedan ${Money.format(insights.left)} · faltan $dias para cobrar"
}

/** Presupuestos aparte del del periodo (p. ej. «Vacaciones»), con lo gastado en cada uno. */
@Composable
internal fun ExtrasSection(budgets: BudgetModel, finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    StmCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Presupuestos extra", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
            Btn("Añadir", { nav.go(Route.FormExtra()) }, kind = BtnKind.Text, icon = StmIcons.add)
        }
        if (budgets.extraBudgets.isEmpty()) {
            Text(
                "Para controlar un gasto concreto aparte del presupuesto: unas vacaciones, una reforma o los regalos de Navidad.",
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        budgets.extraBudgets.forEach { extra ->
            Spacer(Modifier.height(12.dp))
            ExtraRow(extra, gastadoExtra(budgets, finance, extra)) { nav.go(Route.FormExtra(extra.id)) }
        }
    }
}

/** El presupuesto extra favorito, en Resumen. */
@Composable
internal fun FavoritoExtraCard(budgets: BudgetModel, finance: FinanceModel, nav: Nav) {
    val favorito = budgets.extraBudgets.firstOrNull { it.isFavorite } ?: return
    StmCard { ExtraRow(favorito, gastadoExtra(budgets, finance, favorito)) { nav.go(Route.FormExtra(favorito.id)) } }
}

/** Sus fechas pueden salirse del periodo: se piden sus movimientos aparte. */
@Composable
private fun gastadoExtra(budgets: BudgetModel, finance: FinanceModel, extra: ExtraBudget): Long {
    val gastado by produceState(0L, extra, finance.recent, finance.categories) {
        value = extra.spent(budgets.movements(extra), finance.categories)
    }
    return gastado
}

@Composable
private fun ExtraRow(extra: ExtraBudget, spent: Long, onClick: () -> Unit) {
    val c = Stm.colors
    val over = spent > extra.limit
    val fraction = if (extra.limit > 0) (spent.toDouble() / extra.limit).coerceIn(0.0, 1.0).toFloat() else 0f
    Column(Modifier.fillMaxWidth().tap(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StmIcon(if (extra.isFavorite) StmIcons.flagFilled else StmIcons.flag, c.onSurfaceVariant)
            Spacer(Modifier.width(8.dp))
            Text(extra.name, Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
            Text("${Money.format(spent)} de ${Money.format(extra.limit)}", style = StmType.bodySmall, color = if (over) c.error else c.onSurfaceVariant)
        }
        Spacer(Modifier.height(8.dp))
        if (over) Progress(fraction, color = c.error, track = c.errorContainer) else Progress(fraction)
        Spacer(Modifier.height(4.dp))
        Text(
            extra.endsOn?.let { "Del ${Fechas.corto(extra.startsOn)} al ${Fechas.corto(it)}" } ?: "Desde el ${Fechas.corto(extra.startsOn)}, sin fecha de fin",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
    }
}
