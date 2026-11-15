package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.PendingCharge
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.WeeklySummary
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

// PendingViews.swift de iOS: pagos fijos pendientes de confirmar y resumen semanal.

/** Los cargos de pagos fijos que han llegado y esperan confirmación. Sale en Resumen sólo si hay alguno. */
@Composable
internal fun PendientesCard(finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    val planning = finance.planning
    val pendientes = planning.pending
    if (pendientes.isEmpty()) return
    val action = rememberAction()
    StmCard {
        Text("Pendientes de confirmar", style = StmType.titleMedium, color = c.onSurface)
        Text("Aún no cuentan en tus saldos ni en el presupuesto.", style = StmType.bodySmall, color = c.onSurfaceVariant)
        pendientes.take(5).forEach { item ->
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(item.series.trimmedName, Modifier.weight(1f), style = StmType.titleSmall, color = c.onSurface)
                Text(Money.format(item.charge.amountMinor), style = StmType.titleSmall, color = c.onSurface)
            }
            Text(
                listOfNotNull(Fechas.corto(item.charge.due), finance.account(item.series.accountId)?.name).joinToString(" · "),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Btn("Confirmar", {
                    planning.chargeToConfirm = item
                    nav.go(46)
                })
                Btn("No se ha cobrado", { action.run { planning.skip(item) } }, kind = BtnKind.Outlined, enabled = !action.busy)
            }
        }
        if (pendientes.size > 5) {
            Spacer(Modifier.height(8.dp))
            Text("Y ${pendientes.size - 5} más.", style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        action.error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
    }
}

/** 46 Confirmar un cargo: se puede cambiar el importe, el día, la cuenta y la categoría antes de apuntarlo. */
@Composable
fun Pantalla46(nav: Nav) {
    val c = Stm.colors
    val finance = LocalSession.current.finance ?: return
    val planning = finance.planning
    val item: PendingCharge = remember { planning.chargeToConfirm } ?: return
    val esIngreso = item.series.kind == RecurringKind.Income
    var importe by remember { mutableStateOf(Money.format(kotlin.math.abs(item.charge.amountMinor), symbol = false)) }
    var dia by remember { mutableStateOf(item.charge.due) }
    var cuenta by remember { mutableStateOf(item.series.accountId ?: finance.activeAccounts.firstOrNull { it.isDefault }?.id) }
    var categoria by remember { mutableStateOf(item.series.categoryId) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()
    val confirmar = {
        action.run {
            val dinero = Money.entered(importe)?.takeIf { it > 0 } ?: throw AppError.InvalidInput("Escribe el importe, por ejemplo 12,99.")
            val id = cuenta ?: throw AppError.InvalidInput("Elige la cuenta del cargo.")
            finance.confirm(item, MovementDraft(id, categoria, dia, if (esIngreso) dinero else -dinero, item.series.trimmedName))
            nav.back()
        }
    }
    StmScreen(
        topBar = {
            TopBar(item.series.trimmedName, navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Confirmar", confirmar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = selector?.let { campo ->
            {
                val cerrar = { selector = null }
                if (campo == "cuenta") {
                    SelectorSheet("Cuenta", finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                } else {
                    SelectorSheet(
                        "Categoría",
                        listOf<Pair<String, () -> Unit>>("Sin categoría" to { categoria = null }) +
                            finance.categories(if (esIngreso) CategoryKind.Income else CategoryKind.Expense).map { x -> x.name to { categoria = x.id } },
                        cerrar,
                    )
                }
            }
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Importe", importe, { importe = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
            FilledField("Día", Fechas.largo(dia, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
            FilledField("Cuenta", finance.account(cuenta)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField("Categoría", finance.category(categoria)?.name ?: "Sin categoría", trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
            Text(
                "Se apunta como un movimiento normal. Si el importe ha cambiado, pon el que te han cobrado de verdad.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
    if (eligeFecha) SelectorFecha(dia, { dia = it }) { eligeFecha = false }
}

/** La semana pasada en una línea; lleva al resumen completo (47). */
@Composable
internal fun SemanaCard(finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    val resumen = WeeklySummary(finance.recent, finance.categories, finance.today())
    StmCard(onClick = { nav.go(47) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("La semana pasada · ${resumen.title}", Modifier.weight(1f), style = StmType.labelMedium, color = c.onSurfaceVariant)
            StmIcon(StmIcons.chevronRight, c.onSurfaceVariant)
        }
        Text(Money.format(resumen.week.spent), style = StmType.displaySmall, color = c.onSurface)
        Text(resumen.changeText, style = StmType.bodyMedium, color = c.onSurfaceVariant)
    }
}

/** 47 Resumen semanal: total frente a la anterior, gastos más grandes, categorías y mapa de calor. */
@Composable
fun Pantalla47(nav: Nav) {
    val c = Stm.colors
    val finance = LocalSession.current.finance ?: return
    var semana by remember { mutableIntStateOf(0) }
    val resumen = WeeklySummary(finance.recent, finance.categories, finance.today(), includeCurrent = semana == 1)
    StmScreen(topBar = { TopBar("Resumen semanal", navIcon = StmIcons.arrowBack, onNav = nav::back) }) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("La pasada", "Esta semana"), semana, { semana = it })
            StmCard {
                Text(resumen.title, style = StmType.labelMedium, color = c.onSurfaceVariant)
                Text(Money.format(resumen.week.spent), style = StmType.displaySmall, color = c.onSurface)
                Text(resumen.changeText, style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            ListCard {
                ListItem("Ingresos", trailingText = Money.format(resumen.week.income))
                Divider()
                ListItem("Semana anterior", trailingText = Money.format(resumen.previous.spent))
            }
            ListCard {
                ListItem("Gastos más grandes")
                if (resumen.biggest.isEmpty()) {
                    Box(Modifier.padding(horizontal = 16.dp)) { Vacio("No hay gastos esta semana.") }
                }
                resumen.biggest.forEach { m ->
                    Divider()
                    ListItem(
                        m.description, "${DIAS[m.day.dayOfWeek.value - 1]}, ${Fechas.corto(m.day)}",
                        trailingText = Money.format(-m.amountMinor),
                    )
                }
            }
            if (resumen.topCategories.isNotEmpty()) {
                StmCard {
                    Text("En qué se fue", style = StmType.titleMedium, color = c.onSurface)
                    resumen.topCategories.forEach { row ->
                        Spacer(Modifier.height(12.dp))
                        Row {
                            Text(row.title, Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurface)
                            Text(Money.format(row.amount), style = StmType.titleSmall, color = c.onSurface)
                        }
                        Spacer(Modifier.height(4.dp))
                        Progress(row.share.toFloat())
                    }
                }
            }
            StmCard {
                Text("Día a día", style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(12.dp))
                MapaCalor(resumen.heatmap)
                Spacer(Modifier.height(8.dp))
                Text("Cuanto más oscuro, más gastaste ese día. Las últimas 6 semanas.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
    }
}

private val DIAS = listOf("Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo")

/** Cuadrícula de lunes a domingo, una fila por semana. */
@Composable
private fun MapaCalor(semanas: List<List<WeeklySummary.Day>>) {
    val c = Stm.colors
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                Text(it, Modifier.weight(1f), style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }
        semanas.forEach { semana ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                semana.forEach { d ->
                    val color = if (d.spent == 0L) c.surfaceContainer else c.primary.copy(alpha = (0.2 + 0.8 * d.intensity).toFloat())
                    Box(
                        Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(4.dp)).background(color)
                            .semantics { contentDescription = "${DIAS[d.day.dayOfWeek.value - 1]} ${Fechas.corto(d.day)}: ${Money.format(d.spent)}" },
                    )
                }
            }
        }
    }
}
