package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDay
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.Bloqueo
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.MovementForm
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.Vista
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.MerchantLogo
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Lo que trae escrito el formulario 07 al abrirse con [route]. El pago de una tarjeta lleva su próximo cargo y su nombre
 * de ahora, no los de cuando se tocó el botón.
 */
internal fun formularioMovimiento(finance: FinanceModel, route: Route.FormMovimiento, movement: Movement?): MovementForm {
    val tarjeta = finance.account(route.toAccountId)?.takeIf { route.cardPayment }
    return MovementForm(
        movement, route.accountId, route.transfer, route.toAccountId,
        amountMinor = tarjeta?.let(finance.cards::summary)?.next?.amount?.takeIf { it > 0 },
        description = tarjeta?.let { "Pago de ${it.name}" }.orEmpty(),
    )
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

/**
 * Al final de la lista de Movimientos: «Cargar más» pide la página siguiente. Si falla, el aviso y «Reintentar»: nunca
 * parece que la lista se ha acabado (ORC-85).
 */
@Composable
internal fun PieLista(finance: FinanceModel) {
    val action = rememberAction()
    val error = finance.listError
    if (error != null) {
        Text(error, Modifier.padding(vertical = 8.dp), style = StmType.bodyMedium, color = Stm.colors.error)
        Btn("Reintentar", { action.run { finance.retryList() } }.takeIf { !finance.isLoadingList }, kind = BtnKind.Outlined)
    } else if (finance.list.hasMore) {
        Btn(if (finance.isLoadingList) "Cargando…" else "Cargar más movimientos", { action.run { finance.loadMoreList() } }.takeIf { !finance.isLoadingList }, kind = BtnKind.Outlined)
    }
    Spacer(Modifier.height(16.dp))
}

/** Barra de 05 y 08: atrás, título, filtros (con cuántos hay puestos) y más opciones. */
@Composable
internal fun MovimientosTopBar(nav: Nav, filtros: Int = 0, onFiltros: (() -> Unit)? = null, onMas: (() -> Unit)? = null) {
    TopBar("Movimientos", onNav = nav::back) {
        Box {
            IconBtn(StmIcons.tune, onFiltros, tint = if (filtros > 0) Stm.colors.primary else Stm.colors.onSurfaceVariant, contentDescription = if (filtros > 0) "Filtros ($filtros)" else "Filtros")
            if (filtros > 0) {
                Box(
                    Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 2.dp).height(16.dp).width(16.dp).clip(RoundedCornerShape(8.dp)).background(Stm.colors.primary),
                    contentAlignment = Alignment.Center,
                ) { Text("$filtros", style = StmType.labelSmall, color = Stm.colors.onPrimary) }
            }
        }
        IconBtn(StmIcons.moreVert, onMas, contentDescription = "Más opciones")
    }
}

/** Movimientos agrupados por día ("Hoy", "Ayer", "3 de noviembre") con lo que suma cada día, sin transferencias. */
@Composable
fun ListaMovimientos(
    items: List<Movement>,
    finance: FinanceModel,
    totales: Boolean = true,
    /** En modo «Seleccionar», los elegidos; nulo fuera de ese modo. */
    seleccion: Set<String>? = null,
    onClick: (Movement) -> Unit,
) {
    ListCard {
        MovementDay.group(items, finance.categories).forEach { (dia, delDia, total) ->
            Row(Modifier.fillMaxWidth().padding(end = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { ListHeader(Fechas.dia(dia, finance.today())) }
                if (totales && total != 0L) {
                    Text(Money.format(total, signed = true), Modifier.padding(top = 8.dp), style = StmType.labelMedium, color = Stm.colors.onSurfaceVariant)
                }
            }
            delDia.forEachIndexed { i, m ->
                if (i > 0) Divider()
                FilaMovimiento(m, finance, elegido = seleccion?.contains(m.id), onClick = { onClick(m) })
            }
        }
    }
}

@Composable
internal fun FilaMovimiento(m: Movement, finance: FinanceModel, detalle: String? = null, elegido: Boolean? = null, onClick: () -> Unit) {
    val c = Stm.colors
    val cat = finance.category(m.categoryId)
    val icono = iconoCategoria(cat)
    val partes = listOfNotNull(
        detalle ?: cat?.name ?: "Sin categoría",
        if (detalle == null) finance.account(m.accountId)?.name else null,
        // En una pata de transferencia, la cuenta de la otra pata: «Hacia Ahorro» o «Desde Nómina».
        m.transferId?.let { t -> (finance.recent.firstOrNull { it.transferId == t && it.id != m.id } ?: finance.list.rows.firstOrNull { it.transferId == t && it.id != m.id }) }
            ?.let { otra -> finance.account(otra.accountId)?.name }?.let { (if (m.isExpense) "Hacia " else "Desde ") + it },
        m.payee,
        m.tags.takeIf { it.isNotEmpty() }?.joinToString(" ") { "#$it" },
    )
    ListItem(
        MovementText.display(m.description),
        partes.joinToString(" · "),
        trailing = {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    Money.format(m.amountMinor, signed = true), style = StmType.labelLarge, textAlign = TextAlign.End,
                    color = when {
                        m.excluded -> c.onSurfaceVariant
                        !m.isExpense && Vista.ingresosEnVerde -> c.success
                        else -> c.onSurface
                    },
                    textDecoration = if (m.excluded) TextDecoration.LineThrough else null,
                )
                if (m.excluded || m.isReviewed) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (m.excluded) StmIcon(StmIcons.visibilityOff, c.onSurfaceVariant, size = 16.dp, contentDescription = "Excluido del presupuesto")
                        if (m.isReviewed) StmIcon(StmIcons.check, c.success, size = 16.dp, contentDescription = "Revisado")
                    }
                }
            }
        },
        leading = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (elegido != null) {
                    Box(
                        Modifier.width(24.dp).height(24.dp).clip(CircleShape)
                            .let { if (elegido) it.background(c.primary) else it.border(2.dp, c.outline, CircleShape) },
                        contentAlignment = Alignment.Center,
                    ) { if (elegido) StmIcon(StmIcons.check, c.onPrimary, size = 16.dp, contentDescription = "Elegido") }
                    Spacer(Modifier.width(12.dp))
                }
                if (m.isExpense) MerchantLogo(m.description, icono)
                else MerchantLogo(m.description, icono, c.successContainer, c.onSuccessContainer)
            }
        },
        onClick = onClick,
    )
}

/** Interruptor con texto y, si hace falta, una explicación debajo. */
@Composable
internal fun FilaInterruptor(label: String, nota: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        label, nota, supportingLines = 3,
        trailing = {
            Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) { StmSwitch(checked, onChange) }
        },
        onClick = { onChange(!checked) },
    )
}

/** Antes de borrar una pata de transferencia: avisa de que se borran las dos. */
@Composable
internal fun BoxScope.DialogoBorrarTransferencia(
    m: Movement,
    finance: FinanceModel,
    action: com.savethemoney.android.ui.Action,
    onDismiss: () -> Unit,
    onDeleted: () -> Unit,
) {
    StmDialog(
        "¿Borrar la transferencia?",
        com.savethemoney.android.data.TransferDraft.DELETE_WARNING,
        icon = StmIcons.deleteForever,
        onDismiss = onDismiss,
        actions = {
            Btn("Cancelar", onDismiss, kind = BtnKind.Text)
            Btn("Borrar los dos movimientos", {
                onDismiss()
                action.run {
                    finance.delete(m)
                    onDeleted()
                }
            }, kind = BtnKind.Error)
        },
    )
}

/** Texto gris para listas vacías. */
@Composable
fun Vacio(texto: String) {
    Text(texto, Modifier.padding(vertical = 8.dp), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SelectorFecha(inicial: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val state = rememberDatePickerState(initialSelectedDateMillis = inicial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
    // Bloqueada, el diálogo (otra ventana) no se pinta; la fecha elegida se conserva y vuelve al desbloquear.
    if (Bloqueo.app.bloqueada) return
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            Btn("Aceptar", {
                state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                onDismiss()
            }, kind = BtnKind.Text)
        },
        dismissButton = { Btn("Cancelar", onDismiss, kind = BtnKind.Text) },
    ) { DatePicker(state) }
}

/** «Campo de texto» con borde, lupa y texto de ejemplo, sin etiqueta. */
@Composable
internal fun CampoBusqueda(value: String, onValueChange: (String) -> Unit, placeholder: String, autoFocus: Boolean = false) {
    val c = Stm.colors
    val foco = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { foco.requestFocus() }
    Row(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(56.dp)
            .border(1.dp, c.outline, RoundedCornerShape(4.dp)).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(StmIcons.search, c.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = StmType.bodyLarge, color = c.onSurfaceVariant)
            BasicTextField(
                value, onValueChange, Modifier.fillMaxWidth().focusRequester(foco), singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
            )
        }
    }
}

/** «Cifra principal» (100 dp): etiqueta, cifra serif y nota. */
@Composable
internal fun CifraCuenta(label: String, value: String, note: String) {
    val c = Stm.colors
    Column(Modifier.fillMaxWidth().height(100.dp).padding(top = 8.dp)) {
        Text(label, style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.5.dp))
        Text(value, style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Text(note, style = StmType.bodyMedium, color = c.onSurfaceVariant)
    }
}

/** Chip de acción «Añadir nota» (07 y 34). «Dividir gasto» llegará en una fase futura. */
@Composable
internal fun ChipsMovimiento(conNota: Boolean, onNota: () -> Unit) {
    val c = Stm.colors
    ChipRow(Modifier.fillMaxWidth()) {
        Chip("Añadir nota", selected = conNota, onClick = onNota, icon = StmIcons.stickyNote2, labelColor = c.onSurface)
    }
}
