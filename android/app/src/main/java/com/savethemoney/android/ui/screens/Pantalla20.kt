package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.monthlyTotal
import com.savethemoney.android.data.yearlyTotal
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.LocalDate

/** 20 Pagos fijos: total del mes y cargos recurrentes agrupados en próximos e ingresos. */
@Composable
fun Pantalla20(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val planning = finance.planning
    val c = Stm.colors
    val hoy = planning.today()
    var buscando by remember { mutableStateOf(false) }
    var busqueda by remember { mutableStateOf("") }
    val texto = busqueda.trim()
    val coincide = { s: RecurringSeries -> texto.isEmpty() || s.trimmedName.contains(texto, ignoreCase = true) }
    val porFecha = planning.activeSeries.filter(coincide).sortedBy { it.nextDue(hoy) ?: LocalDate.MAX }
    val gastos = porFecha.filter { it.kind != RecurringKind.Income }
    val ingresos = porFecha.filter { it.kind == RecurringKind.Income }
    val archivados = planning.series.filter { it.isArchived && coincide(it) }
    val total = planning.series.monthlyTotal(RecurringKind.Subscription, hoy) + planning.series.monthlyTotal(RecurringKind.Essential, hoy)
    val anual = planning.series.yearlyTotal(setOf(RecurringKind.Subscription, RecurringKind.Essential), hoy)
    fun editar(s: RecurringSeries?) {
        nav.go(Route.FormPagoFijo(s?.id))
    }
    StmScreen(
        topBar = {
            // En el diseño la fila mide 60 (no 64) y el título va justo debajo, sin subtítulo.
            Box(Modifier.fillMaxWidth().height(60.dp)) {
                TopBar(null, onNav = nav::back) {
                    IconBtn(StmIcons.calendarMonth, { nav.go(Route.Calendario) }, contentDescription = "Calendario de pagos")
                    IconBtn(if (buscando) StmIcons.close else StmIcons.search, {
                        buscando = !buscando
                        busqueda = ""
                    }, contentDescription = if (buscando) "Cerrar búsqueda" else "Buscar")
                }
            }
            Text("Pagos fijos", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
            if (buscando) {
                CampoBusqueda(busqueda, { busqueda = it }, "Nombre del pago", autoFocus = true)
                Spacer(Modifier.height(16.dp))
            }
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        fab = { Fab("Nuevo pago") { editar(null) } },
        snackbar = planning.error?.let { e -> { Snackbar(e) } },
    ) {
        StmCard {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f).padding(top = 4.dp)) {
                    Text("Este mes", style = StmType.labelMedium, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    Text(Money.format(total), style = StmType.titleLarge, color = c.onSurface)
                    if (anual > 0) {
                        Text("${Money.format(anual)} en los próximos 12 meses", style = StmType.bodySmall, color = c.onSurfaceVariant)
                    }
                }
                Tag(if (gastos.size == 1) "1 pago" else "${gastos.size} pagos")
            }
        }
        Spacer(Modifier.height(16.dp))
        if (texto.isNotEmpty() && porFecha.isEmpty() && archivados.isEmpty()) {
            Vacio("Ningún pago fijo se llama así.")
        } else if (porFecha.isEmpty() && archivados.isEmpty()) {
            StmCard {
                Text(
                    "Apunta suscripciones, alquiler, luz o tu nómina para ver cuánto suman y recibir un aviso antes de cada cobro.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
            }
        } else {
            ListCard {
                if (gastos.isNotEmpty()) {
                    ListHeader("Próximos")
                    gastos.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
                if (ingresos.isNotEmpty()) {
                    ListHeader("Ingresos")
                    ingresos.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
                if (archivados.isNotEmpty()) {
                    ListHeader("Archivados")
                    archivados.forEachIndexed { i, s ->
                        if (i > 0) Divider()
                        FilaPago(s, hoy) { editar(s) }
                    }
                }
            }
        }
    }
}

private fun detallePago(s: RecurringSeries, hoy: LocalDate): String {
    if (s.isArchived) return "Archivado"
    val due = s.nextDue(hoy) ?: return "Terminado"
    val partes = mutableListOf(Fechas.corto(due))
    if (s.isIntro(due)) {
        partes += "oferta " + periodo(Recurrence(s.every * (s.introCharges ?: 1), s.unit))
    } else if (s.kind != RecurringKind.Income) {
        partes += s.kind.title
    }
    if (s.recurrence != Recurrence.Monthly) partes += s.recurrence.title.lowercase()
    return partes.joinToString(" · ")
}

// shortcut: el esquema no guarda icono en Android; se deduce del nombre. Si se añade elegir icono, usar goal.icon.
private fun iconoPago(s: RecurringSeries): ImageVector {
    val n = s.trimmedName.lowercase()
    return when {
        s.kind == RecurringKind.Income -> StmIcons.work
        "agua" in n -> StmIcons.waterDrop
        "gimnasio" in n || "gym" in n -> StmIcons.fitnessCenter
        s.kind == RecurringKind.Subscription -> StmIcons.liveTv
        else -> StmIcons.home
    }
}

/** Fila de un pago: el importe del próximo cargo y, si va con oferta, lo que costará luego. */
@Composable
private fun FilaPago(s: RecurringSeries, hoy: LocalDate, onClick: () -> Unit) {
    val c = Stm.colors
    val due = if (s.isArchived) null else s.nextDue(hoy)
    val ahora = due?.let(s::amountOn) ?: s.amountMinor
    val texto = Money.format(ahora, signed = s.kind == RecurringKind.Income)
    val (fondo, tinta) = when (s.kind) {
        RecurringKind.Subscription -> c.tertiaryContainer to c.onTertiaryContainer
        RecurringKind.Essential -> c.secondaryContainer to c.onSecondaryContainer
        RecurringKind.Income -> c.successContainer to c.onSuccessContainer
    }
    ListItem(
        s.trimmedName, detallePago(s, hoy),
        leading = { LeadIcon(iconoPago(s), fondo, tinta) },
        trailing = if (ahora != s.amountMinor) {
            {
                Column(horizontalAlignment = Alignment.End) {
                    Text(texto, style = StmType.labelLarge, color = c.onSurface)
                    Text("luego ${Money.format(s.amountMinor)}", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
        } else {
            null
        },
        trailingText = if (ahora != s.amountMinor) null else texto,
        onClick = onClick,
    )
}

/** «Etiqueta» neutra de 24 dp en `surface-container-highest`. */
@Composable
private fun Tag(text: String) {
    Text(
        text, style = StmType.labelMedium, color = Stm.colors.onSurfaceVariant,
        modifier = Modifier.height(24.dp).clip(RoundedCornerShape(8.dp)).background(Stm.colors.surfaceContainerHighest)
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}
