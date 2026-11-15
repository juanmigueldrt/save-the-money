package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetPeriod
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.ExtraBudget
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.PayFrequency
import com.savethemoney.android.data.PaySchedule
import com.savethemoney.android.data.PeriodInsights
import com.savethemoney.android.ui.BudgetModel
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch
import java.util.UUID

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

/** 44 Día de cobro: de ahí salen los periodos del presupuesto. Sólo lo ve quien lo guarda. */
@Composable
fun Pantalla44(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val actual = budgets.schedule
    val hoy = finance.today()
    var frecuencia by remember { mutableStateOf(actual.frequency) }
    var dia1 by remember { mutableStateOf(actual.day1) }
    var dia2 by remember { mutableStateOf(actual.day2 ?: maxOf(15, actual.day1 + 1)) }
    var ancla by remember { mutableStateOf(actual.anchor ?: hoy) }
    var eligiendo by remember { mutableStateOf(false) }
    var eligeFecha by remember { mutableStateOf(false) }
    val schedule = PaySchedule(
        frecuencia, dia1, if (frecuencia == PayFrequency.TwiceMonthly) dia2 else null, if (frecuencia.usesAnchor) ancla else null,
    )
    val guardar = {
        action.run {
            schedule.issue?.let { throw AppError.InvalidInput(it) }
            budgets.save(schedule)
            nav.back()
        }
    }
    StmScreen(
        topBar = {
            TopBar("Día de cobro", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            { SelectorSheet("Cobro", PayFrequency.entries.map { f -> f.title to { frecuencia = f } }, { eligiendo = false }) }
        } else null,
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Cobro", frecuencia.title, trailing = StmIcons.arrowDropDown, onClick = { eligiendo = true })
            when (frecuencia) {
                PayFrequency.Monthly -> FilaDia("El día $dia1", { dia1 = (dia1 - 1).coerceAtLeast(1) }, { dia1 = (dia1 + 1).coerceAtMost(31) })
                PayFrequency.TwiceMonthly -> {
                    FilaDia("Primer día: $dia1", { dia1 = (dia1 - 1).coerceAtLeast(1) }, { dia1 = (dia1 + 1).coerceAtMost(30) })
                    FilaDia("Segundo día: $dia2", { dia2 = (dia2 - 1).coerceAtLeast(2) }, { dia2 = (dia2 + 1).coerceAtMost(31) })
                }
                else -> FilledField(
                    "Un día que cobraste", Fechas.largo(ancla, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true },
                )
            }
            Text(
                "El presupuesto va de un cobro al día antes del siguiente. Si cobras un día 31 y el mes es más corto, cuenta el último día. Sólo lo ves tú.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            val issue = schedule.issue
            if (issue != null) {
                Text(issue, style = StmType.bodySmall, color = c.error)
            } else {
                val periodo = schedule.period(hoy)
                ListCard {
                    ListHeader("Periodo de hoy")
                    ListItem("Del", trailingText = Fechas.largo(periodo.start, hoy))
                    Divider()
                    ListItem("Al", trailingText = Fechas.largo(periodo.end, hoy))
                }
            }
        }
    }
    if (eligeFecha) SelectorFecha(ancla, { ancla = it }) { eligeFecha = false }
}

@Composable
private fun FilaDia(texto: String, menos: () -> Unit, mas: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("Día de cobro", Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
        Stepper(texto, menos, mas)
    }
}

/** Presupuestos aparte del del periodo (p. ej. «Vacaciones»), con lo gastado en cada uno. */
@Composable
internal fun ExtrasSection(budgets: BudgetModel, finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    StmCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Presupuestos extra", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
            Btn("Añadir", { budgets.edit(null); nav.go(45) }, kind = BtnKind.Text, icon = StmIcons.add)
        }
        if (budgets.extraBudgets.isEmpty()) {
            Text(
                "Para controlar un gasto concreto aparte del presupuesto: unas vacaciones, una reforma o los regalos de Navidad.",
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        budgets.extraBudgets.forEach { extra ->
            Spacer(Modifier.height(12.dp))
            ExtraRow(extra, gastadoExtra(budgets, finance, extra)) { budgets.edit(extra); nav.go(45) }
        }
    }
}

/** El presupuesto extra favorito, en Resumen. */
@Composable
internal fun FavoritoExtraCard(budgets: BudgetModel, finance: FinanceModel, nav: Nav) {
    val favorito = budgets.extraBudgets.firstOrNull { it.isFavorite } ?: return
    StmCard { ExtraRow(favorito, gastadoExtra(budgets, finance, favorito)) { budgets.edit(favorito); nav.go(45) } }
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

/** 45 Crear o editar un presupuesto extra. */
@Composable
fun Pantalla45(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val hoy = finance.today()
    val editando = remember { budgets.takeExtra() }
    val extra = remember { editando ?: ExtraBudget(UUID.randomUUID().toString(), budgets.household.id, startsOn = budgets.period.start) }
    var nombre by remember { mutableStateOf(extra.name) }
    var limite by remember { mutableStateOf(if (extra.limit == 0L) "" else Money.input(extra.limit)) }
    var desde by remember { mutableStateOf(extra.startsOn) }
    var conFin by remember { mutableStateOf(extra.endsOn != null) }
    var hasta by remember { mutableStateOf(extra.endsOn ?: extra.startsOn.plusDays(30)) }
    val categorias = remember { mutableStateListOf<String>().apply { addAll(extra.categoryIds) } }
    val cuentas = remember { mutableStateListOf<String>().apply { addAll(extra.accountIds) } }
    var favorito by remember { mutableStateOf(extra.isFavorite) }
    var eligeFecha by remember { mutableStateOf<String?>(null) }
    var confirmar by remember { mutableStateOf(false) }
    val guardar = {
        action.run {
            val amount = Money.entered(limite)?.takeIf { it > 0 } ?: throw AppError.InvalidInput("Escribe un límite, por ejemplo 800,00.")
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
            TopBar(if (editando == null) "Nuevo presupuesto extra" else editando.name, navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (confirmar && editando != null) {
            {
                StmDialog(
                    "¿Borrar «${editando.name}»?", "Los movimientos no se borran.", icon = StmIcons.deleteForever,
                    onDismiss = { confirmar = false },
                    actions = {
                        Btn("Cancelar", { confirmar = false }, kind = BtnKind.Text)
                        Btn("Borrar", {
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
            FilledField("Nombre, p. ej. Vacaciones", nombre, { nombre = it })
            FilledField("Límite, p. ej. 800,00", limite, { limite = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            ListCard {
                ListItem("Favorito (sale en Resumen)", trailing = { StmSwitch(favorito) { favorito = it } })
                Divider(inset = 16.dp)
                ListItem("Con fecha de fin", trailing = { StmSwitch(conFin) { conFin = it } })
            }
            FilledField("Desde", Fechas.largo(desde, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "desde" })
            if (conFin) FilledField("Hasta", Fechas.largo(hasta, hoy), trailing = StmIcons.calendarToday, onClick = { eligeFecha = "hasta" })
            ListCard {
                ListHeader("Categorías")
                finance.categories(CategoryKind.Expense).forEachIndexed { i, category ->
                    if (i > 0) Divider(inset = 16.dp)
                    ListItem(category.name, trailing = {
                        StmSwitch(category.id in categorias) { on -> if (on) categorias += category.id else categorias -= category.id }
                    })
                }
            }
            Text(
                if (categorias.isEmpty()) "Si no eliges ninguna, cuenta todo el gasto." else "${categorias.size} elegidas.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            ListCard {
                ListHeader("Cuentas")
                finance.activeAccounts.forEachIndexed { i, account ->
                    if (i > 0) Divider(inset = 16.dp)
                    ListItem(account.name, trailing = {
                        StmSwitch(account.id in cuentas) { on -> if (on) cuentas += account.id else cuentas -= account.id }
                    })
                }
            }
            Text(
                if (cuentas.isEmpty()) "Si no eliges ninguna, cuentan todas." else "${cuentas.size} elegidas.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            if (editando != null) Btn("Borrar presupuesto extra", { confirmar = true }, kind = BtnKind.Text, color = c.error)
            Spacer(Modifier.height(8.dp))
        }
    }
    eligeFecha?.let { campo ->
        SelectorFecha(if (campo == "hasta") hasta else desde, { if (campo == "hasta") hasta = it else desde = it }) { eligeFecha = null }
    }
}
