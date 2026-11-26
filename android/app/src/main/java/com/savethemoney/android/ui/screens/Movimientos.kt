package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.MovementDateFilter
import com.savethemoney.android.data.MovementDay
import com.savethemoney.android.data.MovementFilter
import com.savethemoney.android.data.MovementKindFilter
import com.savethemoney.android.data.MovementStatusFilter
import com.savethemoney.android.data.MovementBulkEdit
import com.savethemoney.android.data.MovementTags
import com.savethemoney.android.data.Payee
import com.savethemoney.android.data.SimilarMovements
import com.savethemoney.android.data.Change
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.style.TextDecoration
import com.savethemoney.android.ui.Vista
import com.savethemoney.android.ui.components.Calculadora
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CardPurchase
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.CategoryLearner
import com.savethemoney.android.data.MerchantDirectory
import com.savethemoney.android.data.Movement
import com.savethemoney.android.ui.components.MerchantLogo
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.monthEndBalances
import com.savethemoney.android.ui.Bloqueo
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.MovementForm
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.abs

/** 05 Movimientos: búsqueda, filtros (cuenta, tipo, categoría y fechas), lista por días y aviso de borrado. */
@Composable
fun Pantalla05(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    var hoja by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf<String?>(null) }
    val action = rememberAction()
    val filtro = finance.movementFilter
    // Modo «Seleccionar»: tocar marca en vez de abrir, y abajo salen las acciones para todos.
    var seleccionando by remember { mutableStateOf(false) }
    var elegidos by remember { mutableStateOf(emptySet<String>()) }
    val categorias = finance.recent.mapNotNull { it.categoryId }.groupingBy { it }.eachCount().entries
        .sortedByDescending { it.value }.mapNotNull { finance.category(it.key) }
    val visibles = filtro.apply(finance.recent, finance.categories, finance.today(), finance.household.monthStartDay)
    val filtrando = filtro.activeCount > 0 || filtro.search.isNotBlank()
    val marcados = visibles.filter { it.id in elegidos }
    fun terminaSeleccion() {
        seleccionando = false
        elegidos = emptySet()
    }
    val borrado = finance.lastDeleted
    LaunchedEffect(borrado) {
        if (borrado != null) {
            delay(6_000)
            finance.lastDeleted = null
        }
    }
    StmScreen(
        topBar = {
            MovimientosTopBar(nav, filtro.activeCount, onFiltros = { hoja = "filtros" }, onMas = { hoja = "mas" })
            CampoBusqueda(filtro.search, { finance.movementFilter = filtro.copy(search = it) }, "Concepto, beneficiario, #etiqueta o importe")
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                categorias.forEach { cat ->
                    Chip(cat.name, selected = cat.id == filtro.categoryId, onClick = {
                        finance.movementFilter = filtro.copy(categoryId = if (cat.id == filtro.categoryId) null else cat.id)
                    })
                }
            }
            Spacer(Modifier.height(12.dp))
        },
        bottomBar = {
            if (seleccionando) {
                BarraSeleccion(
                    marcados.size, todos = marcados.size == visibles.size && visibles.isNotEmpty(),
                    onTodos = { elegidos = if (marcados.size == visibles.size) emptySet() else visibles.map { it.id }.toSet() },
                    onRevisado = { action.run { finance.update(MovementBulkEdit(reviewed = true).changes(marcados)) } },
                    onEditar = { hoja = "masiva" },
                    onBorrar = { hoja = "borrar" },
                )
            } else {
                NavBar(Tab.Inicio, nav::tab)
            }
        },
        fab = if (seleccionando) null else { { Fab("Añadir") { nav.go(if (finance.activeAccounts.isEmpty()) 9 else 7) } } },
        snackbar = if (action.error != null) {
            { Snackbar(action.error!!) }
        } else if (!seleccionando && borrado != null) {
            {
                // El diseño deja 16 dp entre FAB y snackbar; StmScreen pone 12.
                Spacer(Modifier.height(4.dp))
                Snackbar("Movimiento eliminado", "Deshacer") {
                    action.run { finance.undoDelete() }
                }
            }
        } else null,
        overlay = when (hoja) {
            "filtros" -> { { HojaFiltros(finance, { hoja = it }, { eligeFecha = it }) } }
            "categoria" -> {
                {
                    SelectorSheet(
                        "Categoría",
                        listOf<Pair<String, () -> Unit>>("Todas las categorías" to { finance.movementFilter = finance.movementFilter.copy(categoryId = null) }) +
                            (finance.categories(CategoryKind.Expense) + finance.categories(CategoryKind.Income) + finance.categories(CategoryKind.Transfer))
                                .map { cat -> cat.name to { finance.movementFilter = finance.movementFilter.copy(categoryId = cat.id) } },
                    ) { hoja = "filtros" }
                }
            }
            "masiva" -> { { HojaEdicionMasiva(finance, marcados, { hoja = null }) { terminaSeleccion() } } }
            "borrar" -> {
                {
                    StmDialog(
                        if (marcados.size == 1) "¿Borrar 1 movimiento?" else "¿Borrar ${marcados.size} movimientos?",
                        "No se puede deshacer.",
                        icon = StmIcons.deleteForever,
                        onDismiss = { hoja = null },
                        actions = {
                            Btn("Cancelar", { hoja = null }, kind = BtnKind.Text)
                            Btn("Borrar", {
                                hoja = null
                                action.run {
                                    finance.delete(marcados)
                                    terminaSeleccion()
                                }
                            }, kind = BtnKind.Error)
                        },
                    )
                }
            }
            "mas" -> {
                {
                    BottomSheet("Movimientos", onDismiss = { hoja = null }) {
                        if (finance.recent.isNotEmpty()) {
                            SheetItem(StmIcons.check, if (seleccionando) "Terminar selección" else "Seleccionar") {
                                hoja = null
                                if (seleccionando) terminaSeleccion() else seleccionando = true
                            }
                        }
                        if (filtrando) {
                            SheetItem(StmIcons.close, "Quitar filtros y búsqueda") {
                                hoja = null
                                finance.movementFilter = MovementFilter()
                            }
                        }
                        SheetItem(if (Vista.incognito) StmIcons.visibility else StmIcons.visibilityOff, if (Vista.incognito) "Mostrar importes" else "Ocultar importes") {
                            hoja = null
                            Vista.setIncognito(!Vista.incognito)
                        }
                        SheetItem(StmIcons.uploadFile, "Importar CSV") {
                            hoja = null
                            nav.go(32)
                        }
                    }
                }
            }
            else -> null
        },
    ) {
        if (filtrando) {
            ResumenFiltro(visibles, finance) { finance.movementFilter = MovementFilter() }
            Spacer(Modifier.height(16.dp))
        }
        if (visibles.isEmpty()) {
            Vacio(if (finance.recent.isEmpty()) "No hay movimientos. Apunta uno con Añadir o importa un CSV desde Más opciones." else "Nada coincide con la búsqueda o los filtros.")
        } else {
            ListaMovimientos(visibles.take(MAX_FILAS), finance, seleccion = if (seleccionando) elegidos else null) { m ->
                if (seleccionando) {
                    elegidos = if (m.id in elegidos) elegidos - m.id else elegidos + m.id
                } else {
                    finance.tappedMovement = m
                    nav.go(8)
                }
            }
        }
    }
    eligeFecha?.let { campo ->
        val actual = (if (campo == "desde") filtro.customFrom else filtro.customThrough) ?: finance.today()
        SelectorFecha(actual, { dia ->
            finance.movementFilter = if (campo == "desde") finance.movementFilter.copy(customFrom = dia) else finance.movementFilter.copy(customThrough = dia)
        }) { eligeFecha = null }
    }
}

/** Hoja «Filtros» de Movimientos: cuenta, tipo, categoría y fechas. */
@Composable
private fun BoxScope.HojaFiltros(finance: FinanceModel, abrir: (String?) -> Unit, eligeFecha: (String) -> Unit) {
    val c = Stm.colors
    val filtro = finance.movementFilter
    fun cambia(nuevo: MovementFilter) { finance.movementFilter = nuevo }
    BottomSheet("Filtros", onDismiss = { abrir(null) }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Text("Cuenta", style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                Chip("Todas", selected = filtro.accountId == null, onClick = { cambia(filtro.copy(accountId = null)) })
                finance.accounts.forEach { a ->
                    Chip(a.name, selected = filtro.accountId == a.id, onClick = { cambia(filtro.copy(accountId = a.id)) })
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Tipo", style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementKindFilter.entries.forEach { k -> Chip(k.title, selected = filtro.kind == k, onClick = { cambia(filtro.copy(kind = k)) }) }
            }
            Spacer(Modifier.height(16.dp))
            Text("Estado", style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementStatusFilter.entries.forEach { e -> Chip(e.title, selected = filtro.status == e, onClick = { cambia(filtro.copy(status = e)) }) }
            }
            val etiquetas = finance.knownTags
            if (etiquetas.isNotEmpty() || filtro.tag != null) {
                Spacer(Modifier.height(16.dp))
                Text("Etiqueta", style = StmType.labelLarge, color = c.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                ChipRow(Modifier.fillMaxWidth()) {
                    Chip("Todas las etiquetas", selected = filtro.tag == null, onClick = { cambia(filtro.copy(tag = null)) })
                    (etiquetas + listOfNotNull(filtro.tag)).distinct().forEach { t ->
                        Chip("#$t", selected = filtro.tag == t, onClick = { cambia(filtro.copy(tag = t)) })
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            FilledField(
                "Categoría", finance.category(filtro.categoryId)?.name ?: "Todas las categorías",
                leading = filtro.categoryId?.let { iconoCategoria(finance.category(it)) },
                trailing = StmIcons.arrowDropDown, onClick = { abrir("categoria") },
            )
            Spacer(Modifier.height(16.dp))
            Text("Fechas", style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementDateFilter.entries.forEach { d ->
                    Chip(d.title, selected = filtro.dates == d, onClick = {
                        val hoy = finance.today()
                        cambia(
                            if (d == MovementDateFilter.Custom && filtro.customFrom == null) {
                                filtro.copy(dates = d, customFrom = hoy.minusMonths(1), customThrough = hoy)
                            } else filtro.copy(dates = d),
                        )
                    })
                }
            }
            if (filtro.dates == MovementDateFilter.Custom) {
                val hoy = finance.today()
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledField("Desde", Fechas.largo(filtro.customFrom ?: hoy, hoy), modifier = Modifier.weight(1f), trailing = StmIcons.calendarToday, onClick = { eligeFecha("desde") })
                    FilledField("Hasta", Fechas.largo(filtro.customThrough ?: hoy, hoy), modifier = Modifier.weight(1f), trailing = StmIcons.calendarToday, onClick = { eligeFecha("hasta") })
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                if (filtro.activeCount > 0) Btn("Quitar filtros", { cambia(MovementFilter(search = filtro.search)) }, kind = BtnKind.Text)
                Btn("Ver movimientos", { abrir(null) })
            }
        }
    }
}

/** "12 movimientos · Gastos −340,20 € · Ingresos +1.200,00 €" de lo filtrado, sin transferencias. */
@Composable
private fun ResumenFiltro(items: List<Movement>, finance: FinanceModel, quitar: () -> Unit) {
    val c = Stm.colors
    val contados = items.filter { !it.excluded && finance.category(it.categoryId)?.kind != CategoryKind.Transfer }
    val gastos = contados.filter { it.isExpense }.sumOf { it.amountMinor }
    val ingresos = contados.filter { !it.isExpense }.sumOf { it.amountMinor }
    StmCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(if (items.size == 1) "1 movimiento" else "${items.size} movimientos", style = StmType.titleMedium, color = c.onSurface)
                Text(
                    "Gastos ${Money.format(gastos, signed = true)} · Ingresos ${Money.format(ingresos, signed = true)}",
                    style = StmType.bodySmall, color = c.onSurfaceVariant,
                )
            }
            Btn("Quitar filtros", quitar, kind = BtnKind.Text)
        }
    }
}

/** 06 Cuenta: saldo, acciones, evolución en 6 meses y sus movimientos por mes. */
@Composable
fun Pantalla06(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val account = finance.selectedAccount ?: return
    val c = Stm.colors
    var lista by remember(account.id) { mutableStateOf(emptyList<Movement>()) }
    var opciones by remember { mutableStateOf(false) }
    var confirmar by remember { mutableStateOf(false) }
    var ajustando by remember { mutableStateOf(false) }
    val action = rememberAction()
    var fallo by remember(account.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(account.id, finance.recent) {
        try {
            lista = finance.movements(account)
            fallo = null
        } catch (e: AppError) {
            // Se queda la lista que había, con el aviso: no es lo mismo que una cuenta sin movimientos.
            fallo = "No se han podido cargar los movimientos. ${e.message}"
        }
    }
    val hoy = finance.today()
    val serie = monthEndBalances(finance.balance(account), lista, hoy)
    val alto = serie.max()
    val bajo = serie.min()
    StmScreen(
        topBar = {
            TopBar(account.name, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    finance.accountToEdit = account
                    nav.go(9)
                }, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, { opciones = true }, contentDescription = "Más opciones")
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            ajustando -> { { HojaAjusteSaldo(finance, account) { ajustando = false } } }
            confirmar -> {
                {
                    StmDialog(
                        "¿Borrar esta cuenta?",
                        "Se borran también todos sus movimientos, para todo el hogar. No se puede deshacer.",
                        icon = StmIcons.deleteForever,
                        onDismiss = { confirmar = false },
                        actions = {
                            Btn("Cancelar", { confirmar = false }, kind = BtnKind.Text)
                            Btn("Borrar", {
                                action.run {
                                    finance.deleteAccount(account)
                                    finance.selectedAccountId = null
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        },
                    )
                }
            }
            opciones -> {
                {
                    BottomSheet(account.name, onDismiss = { opciones = false }) {
                        SheetItem(StmIcons.syncAlt, "Actualizar saldo") {
                            opciones = false
                            ajustando = true
                        }
                        SheetItem(StmIcons.visibilityOff, if (account.isArchived) "Desarchivar" else "Archivar") {
                            opciones = false
                            action.run {
                                finance.updateAccount(account.copy(archivedAt = if (account.isArchived) null else Instant.now().toString()))
                                if (!account.isArchived) nav.back()
                            }
                        }
                        SheetItem(StmIcons.delete, "Borrar cuenta y movimientos") {
                            opciones = false
                            confirmar = true
                        }
                    }
                }
            }
            else -> null
        },
    ) {
        CifraCuenta("Saldo", Money.format(finance.balance(account)), if (account.isShared) "${account.kind.title} · compartida" else account.kind.title)
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Btn("Importar CSV", {
                finance.csvAccountId = account.id
                nav.go(32)
            }, kind = BtnKind.Tonal, icon = StmIcons.uploadFile)
            Btn("Transferir", {
                finance.movementForm = MovementForm(accountId = account.id, transfer = true)
                nav.go(7)
            }, kind = BtnKind.Outlined, icon = StmIcons.syncAlt)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Saldo en 6 meses", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            LineChart(serie.map { if (alto == bajo) 0.5f else (it - bajo).toFloat() / (alto - bajo) })
        }
        Spacer(Modifier.height(16.dp))
        fallo?.let { Text(it, Modifier.padding(vertical = 8.dp), style = StmType.bodyMedium, color = Stm.colors.error) }
        if (lista.isEmpty() && fallo == null) Vacio("Todavía no hay movimientos en esta cuenta.")
        lista.take(MAX_FILAS).groupBy { it.day.withDayOfMonth(1) }.forEach { (mes, items) ->
            ListCard {
                ListHeader(Fechas.mesTitulo(mes) + if (mes.year != hoy.year) " ${mes.year}" else "")
                items.forEachIndexed { i, m ->
                    if (i > 0) Divider()
                    FilaMovimiento(m, finance, Fechas.corto(m.day)) {
                        finance.tappedMovement = m
                        nav.go(34)
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** 07 Nuevo o editar movimiento: tipo, importe, concepto, categoría, cuenta, fecha y extras. */
@Composable
fun Pantalla07(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val form = remember { finance.takeMovementForm() }
    val base = remember { form.movement }
    var tipo by remember { mutableIntStateOf(if (form.transfer) 2 else if (base?.isExpense == false) 1 else 0) }
    var importe by remember { mutableStateOf(base?.let { Money.input(abs(it.amountMinor)) } ?: form.amountMinor?.let(Money::input) ?: "") }
    var concepto by remember { mutableStateOf(base?.description ?: form.description) }
    var categoria by remember { mutableStateOf(base?.categoryId) }
    var autoCategoria by remember { mutableStateOf<String?>(null) }
    var cuenta by remember { mutableStateOf(form.accountId ?: base?.accountId ?: finance.defaultAccount?.id) }
    var destino by remember { mutableStateOf(form.toAccountId) }
    var fecha by remember { mutableStateOf(base?.day ?: finance.today()) }
    var notas by remember { mutableStateOf(base?.notes ?: "") }
    var conNotas by remember { mutableStateOf(notas.isNotEmpty()) }
    var beneficiario by remember { mutableStateOf(base?.payee ?: "") }
    var etiquetas by remember { mutableStateOf(MovementTags.text(base?.tags.orEmpty())) }
    var excluido by remember { mutableStateOf(base?.excluded ?: false) }
    var revisado by remember { mutableStateOf(base?.isReviewed ?: false) }
    // Tras cambiar la categoría: otros con el mismo concepto a los que ofrecer el mismo cambio.
    var parecidos by remember { mutableStateOf(emptyList<Movement>()) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    // Sólo gasto nuevo en una tarjeta: normal (0), a plazos (1) o recurrente (2).
    var compra by remember { mutableIntStateOf(0) }
    var plazos by remember { mutableIntStateOf(CardPurchase.DEFAULT_MONTHS) }
    var cadaCompra by remember { mutableStateOf(Recurrence.Monthly) }
    val action = rememberAction()
    // Uno por formulario: si «Guardar» se repite tras un fallo de red, la transferencia no se guarda dos veces.
    val idTransferencia = remember { java.util.UUID.randomUUID().toString() }
    // Lo mismo para un movimiento nuevo: el reintento lleva el mismo identificador y no se apunta dos veces.
    val idMovimiento = remember { java.util.UUID.randomUUID().toString() }
    val cuentas = finance.activeAccounts.map { it.name to it.id }
    val enTarjeta = form.movement == null && tipo == 0 && finance.account(cuenta)?.kind == AccountKind.CreditCard
    val tipoCategoria = if (tipo == 1) CategoryKind.Income else CategoryKind.Expense
    val elegida = finance.category(categoria)

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val valor = Money.entered(importe)?.takeIf { it != 0L }?.let(::abs) ?: falla("Escribe un importe, por ejemplo 12,50.")
        val origen = cuenta ?: falla("Elige una cuenta.")
        val nota = notas.trim().ifEmpty { null }
        val quien = Payee.clean(beneficiario)
        val marcas = MovementTags.normalize(etiquetas)
        if (tipo == 2) {
            val hacia = destino ?: falla("Elige la cuenta de destino.")
            if (hacia == origen) falla("Elige dos cuentas distintas.")
            val cat = finance.categories(CategoryKind.Transfer).firstOrNull()?.id
            val texto = concepto.ifBlank { "Transferencia" }
            finance.transfer(
                com.savethemoney.android.data.TransferDraft(
                    idTransferencia, origen, hacia, cat, fecha, valor, texto, texto, nota, excluido, quien, marcas,
                ),
            )
        } else {
            val draft = MovementDraft(
                origen, categoria, fecha, if (tipo == 0) -valor else valor, concepto, nota,
                excluded = excluido, payee = quien, tags = marcas, id = idMovimiento,
            )
            draft.issue?.let(::falla)
            val editando = form.movement
            if (editando != null) {
                val cambiado = editando.copy(
                    accountId = draft.accountId, categoryId = draft.categoryId, bookedOn = draft.bookedOn.toString(),
                    amountMinor = draft.amountMinor, description = draft.description, notes = draft.notes,
                    excluded = draft.excluded, payee = draft.payee, tags = draft.tags,
                    reviewedAt = if (revisado) editando.reviewedAt ?: Instant.now().toString() else null,
                )
                finance.update(cambiado)
                if (editando.categoryId != draft.categoryId) {
                    val iguales = SimilarMovements.matches(cambiado, finance.recent, draft.categoryId)
                    if (iguales.isNotEmpty()) {
                        parecidos = iguales
                        return@run
                    }
                }
            } else if (enTarjeta && compra != 0) {
                finance.addCardPurchase(draft, if (compra == 1) CardPurchase.Installments(plazos) else CardPurchase.Recurring(cadaCompra))
            } else {
                finance.add(draft)
            }
        }
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (form.movement != null) "Editar movimiento" else "Nuevo movimiento", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (parecidos.isNotEmpty()) {
            {
                StmDialog(
                    if (parecidos.size == 1) "Hay 1 movimiento con el mismo concepto" else "Hay ${parecidos.size} movimientos con el mismo concepto",
                    "¿Quieres cambiar también su categoría a «${elegida?.name ?: "Sin categoría"}»?",
                    icon = StmIcons.category,
                    onDismiss = nav::back,
                    actions = {
                        Btn("Sólo este", nav::back, kind = BtnKind.Text)
                        Btn("Ponerles la misma categoría", {
                            action.run {
                                finance.update(parecidos.map { it.copy(categoryId = categoria) })
                                nav.back()
                            }
                        }, kind = BtnKind.Text)
                    },
                )
            }
        } else selector?.let { campo ->
            {
                val cerrar = { selector = null }
                when (campo) {
                    "categoria" -> SelectorSheet(
                        "Categoría",
                        listOf<Pair<String, () -> Unit>>("Sin categoría" to { categoria = null }) +
                            (finance.categories(tipoCategoria) + finance.categories(CategoryKind.Transfer)).map { cat -> cat.name to { categoria = cat.id } },
                        cerrar,
                    )
                    "cuenta" -> SelectorSheet("Cuenta", cuentas.map { (n, id) -> n to { cuenta = id } }, cerrar)
                    "cadaCompra" -> SelectorSheet("Frecuencia", Recurrence.Common.map { rec -> rec.title to { cadaCompra = rec } }, cerrar)
                    else -> SelectorSheet("Cuenta de destino", cuentas.map { (n, id) -> n to { destino = id } }, cerrar)
                }
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(
            if (form.movement != null) listOf("Gasto", "Ingreso") else listOf("Gasto", "Ingreso", "Transferencia"),
            tipo,
            { nuevo ->
                tipo = nuevo
                // Una categoría de ingreso no vale para un gasto; las de transferencia sirven para los dos.
                val kind = elegida?.kind
                if (kind != null && kind != CategoryKind.Transfer && kind != (if (nuevo == 1) CategoryKind.Income else CategoryKind.Expense)) categoria = null
            },
        )
        Spacer(Modifier.height(16.dp))
        var enfocado by remember { mutableStateOf(false) }
        Column(
            Modifier.fillMaxWidth().heightIn(min = 116.dp).padding(top = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Importe", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Box(contentAlignment = Alignment.Center) {
                if (importe.isEmpty()) Text("0,00 €", style = StmType.displayLarge, color = c.onSurfaceVariant)
                BasicTextField(
                    importe, { importe = it }, Modifier.fillMaxWidth().onFocusChanged { enfocado = it.isFocused }, singleLine = true,
                    textStyle = StmType.displayLarge.copy(color = c.onSurface, textAlign = TextAlign.Center),
                    cursorBrush = SolidColor(c.primary),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
            }
            Calculadora(importe, { importe = it }, enfocado)
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Concepto", concepto, { texto ->
            concepto = MovementText.display(texto)
            // Comercio conocido o concepto ya usado: pone la categoría sola si no la elegiste a mano.
            if (tipo == 0 && (categoria == null || categoria == autoCategoria)) {
                val sugerida = MerchantDirectory.suggestedCategory(concepto, true, finance.categories, CategoryLearner(finance.recent))?.id
                categoria = sugerida ?: if (categoria == autoCategoria) null else categoria
                autoCategoria = sugerida
            }
        })
        Spacer(Modifier.height(16.dp))
        if (tipo == 2) {
            FilledField("Cuenta de destino", finance.account(destino)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "destino" })
        } else {
            FilledField("Categoría", elegida?.name ?: "Sin categoría", leading = iconoCategoria(elegida), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Cuenta", finance.account(cuenta)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
        if (enTarjeta) {
            Spacer(Modifier.height(16.dp))
            Text("Tipo de compra", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Segmented(listOf("Normal", "A plazos", "Recurrente"), compra, { compra = it })
            if (compra == 1) {
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Plazos", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Stepper(
                        "$plazos meses",
                        { plazos = (plazos - 1).coerceAtLeast(CardPurchase.MONTHS.first) },
                        { plazos = (plazos + 1).coerceAtMost(CardPurchase.MONTHS.last) },
                    )
                }
                Spacer(Modifier.height(8.dp))
                ChipRow(Modifier.fillMaxWidth()) {
                    CardInstallment.commonMonths.forEach { m -> Chip("$m meses", selected = m == plazos, onClick = { plazos = m }) }
                }
                val principal = Money.entered(importe)?.let(::abs) ?: 0L
                val tin = finance.cards.terms[cuenta]?.installmentRate ?: 14.0
                val cuota = CardPurchase.quote(principal, plazos, tin)
                Spacer(Modifier.height(8.dp))
                Text(
                    "${Money.format(cuota.monthly)} al mes · total ${Money.format(cuota.total)} · intereses ${Money.format(cuota.interest)} " +
                        "(TIN ${tin.toString().removeSuffix(".0").replace('.', ',')} %)",
                    style = StmType.bodyMedium, color = c.onSurface,
                )
                if (principal in 1 until CardPurchase.USUAL_MINIMUM) {
                    Text("Muchos contratos sólo aplazan compras de 50 € o más", style = StmType.bodySmall, color = c.error)
                }
            } else if (compra == 2) {
                Spacer(Modifier.height(16.dp))
                FilledField("Cada", cadaCompra.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "cadaCompra" })
                Spacer(Modifier.height(4.dp))
                Text(
                    "Se crea un pago fijo con este concepto, importe y categoría. Los próximos cargos saldrán como pendientes de confirmar.",
                    style = StmType.bodySmall, color = c.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
        Spacer(Modifier.height(16.dp))
        FilledField("Beneficiario (opcional)", beneficiario, { beneficiario = it })
        val propuestos = if (beneficiario.isBlank()) emptyList() else finance.knownPayees
            .filter { it.contains(beneficiario.trim(), ignoreCase = true) && !it.equals(beneficiario.trim(), ignoreCase = true) }.take(4)
        if (propuestos.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) { propuestos.forEach { p -> Chip(p, onClick = { beneficiario = p }, icon = StmIcons.person) } }
        }
        Spacer(Modifier.height(16.dp))
        FilledField(
            "Etiquetas, p. ej. viaje, regalos", etiquetas, { etiquetas = it },
            supporting = "Las etiquetas sirven para juntar gastos de distintas categorías, como un viaje. Sepáralas con comas.",
        )
        val puestas = MovementTags.normalize(etiquetas)
        val sugeridas = finance.knownTags.filter { it !in puestas }.take(6)
        if (sugeridas.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                sugeridas.forEach { t -> Chip("#$t", onClick = { etiquetas = MovementTags.text(puestas + t) }, icon = StmIcons.add) }
            }
        }
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento(conNotas) { conNotas = !conNotas }
        if (conNotas) {
            Spacer(Modifier.height(16.dp))
            FilledField("Notas", notas, { notas = it })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            if (form.movement != null) {
                FilaInterruptor("Revisado", null, revisado) { revisado = it }
                Divider(inset = 16.dp)
            }
            FilaInterruptor(
                "Excluir del presupuesto e informes",
                "Un movimiento excluido sigue contando en el saldo de la cuenta, pero no en el presupuesto, los informes ni el flujo de caja.",
                excluido,
            ) { excluido = it }
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}

/** 08 Acciones del movimiento: la lista de 05 con la hoja de acciones abierta. */
@Composable
fun Pantalla08(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val m = finance.selectedMovement ?: return
    val action = rememberAction()
    val editar = {
        finance.movementForm = MovementForm(movement = m)
        nav.go(7)
    }
    StmScreen(
        topBar = { MovimientosTopBar(nav) },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        overlay = {
            BottomSheet(MovementText.display(m.description), "${Money.format(m.amountMinor, signed = true)} · ${Fechas.dia(m.day, finance.today())}", onDismiss = nav::back) {
                SheetItem(StmIcons.category, "Cambiar categoría", onClick = editar)
                SheetItem(StmIcons.check, if (m.isReviewed) "Marcar sin revisar" else "Marcar revisado") {
                    action.run {
                        finance.update(MovementBulkEdit(reviewed = !m.isReviewed).changes(listOf(m)))
                        nav.back()
                    }
                }
                SheetItem(if (m.excluded) StmIcons.visibility else StmIcons.visibilityOff, if (m.excluded) "Volver a contar en el presupuesto" else "Excluir del presupuesto") {
                    action.run {
                        finance.update(MovementBulkEdit(excluded = !m.excluded).changes(listOf(m)))
                        nav.back()
                    }
                }
                SheetItem(StmIcons.eventRepeat, "Aplazar con la tarjeta") {
                    finance.cards.selectedId = m.accountId
                    finance.cards.purchaseId = m.id
                    nav.go(13)
                }
                SheetItem(StmIcons.delete, "Eliminar") {
                    action.run {
                        finance.delete(m)
                        nav.back()
                    }
                }
            }
        },
    ) {
        ListaMovimientos(listOf(m), finance, totales = false) {}
    }
}

/** 09 Nueva o editar cuenta: nombre, tipo, saldo inicial y si se comparte con el hogar. */
@Composable
fun Pantalla09(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val editando = remember { finance.takeAccountToEdit() }
    var nombre by remember { mutableStateOf(editando?.name ?: "") }
    var tipo by remember { mutableStateOf(editando?.kind ?: finance.newAccountKind.also { finance.newAccountKind = null } ?: AccountKind.Checking) }
    var saldo by remember {
        mutableStateOf(editando?.openingMinor?.takeIf { it != 0L }?.let(Money::input) ?: "")
    }
    var compartir by remember { mutableStateOf(editando?.isShared ?: true) }
    var predeterminada by remember { mutableStateOf(editando?.isDefault ?: false) }
    var patrimonio by remember { mutableStateOf(editando?.includeInNetWorth ?: true) }
    val action = rememberAction()
    // Una tarjeta ya creada no puede cambiar de tipo (el servidor también lo rechaza).
    val tarjetaFija = editando?.kind == AccountKind.CreditCard
    val tipos = listOf(AccountKind.Checking, AccountKind.Savings, AccountKind.CreditCard, AccountKind.Cash, AccountKind.Investment)
        .let { if (tipo in it) it else it + tipo }
        .filter { !tarjetaFija || it == AccountKind.CreditCard }

    fun guardar() = action.run {
        val apertura = if (saldo.isBlank()) 0L else Money.entered(saldo) ?: throw AppError.InvalidInput("El saldo inicial no es un importe válido.")
        val dueno = if (compartir) null else editando?.ownerId ?: session.profile?.id
        val draft = AccountDraft(nombre, tipo, apertura, dueno)
        draft.issue?.let { throw AppError.InvalidInput(it) }
        if (editando != null) {
            finance.updateAccount(
                editando.copy(
                    name = draft.trimmedName, kind = tipo, openingMinor = apertura, ownerId = dueno,
                    isDefault = predeterminada, includeInNetWorth = patrimonio,
                ),
            )
        } else {
            val nueva = finance.createAccount(draft)
            if (predeterminada || !patrimonio) finance.updateAccount(nueva.copy(isDefault = predeterminada, includeInNetWorth = patrimonio))
        }
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando != null) "Editar cuenta" else "Nueva cuenta", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField("Nombre", nombre, { nombre = it }, autoFocus = true)
        Spacer(Modifier.height(16.dp))
        Text("Tipo", style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        ChipRow(Modifier.fillMaxWidth()) {
            tipos.forEach { t ->
                Chip(if (t == AccountKind.Checking) "Corriente" else t.title, selected = t == tipo, onClick = { tipo = t })
            }
        }
        if (tarjetaFija) {
            Spacer(Modifier.height(8.dp))
            Text("Una tarjeta de crédito no puede cambiar de tipo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Saldo inicial", saldo, { saldo = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Compartir con el hogar", "Tu pareja verá el saldo y los movimientos",
                trailing = {
                    // El diseño reserva 40 dp al final y deja que el interruptor de 52 sobresalga.
                    Box(Modifier.width(40.dp).wrapContentWidth(Alignment.Start, unbounded = true)) {
                        StmSwitch(compartir) { compartir = it }
                    }
                },
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            FilaInterruptor("Cuenta predeterminada", null, predeterminada) { predeterminada = it }
            Divider(inset = 16.dp)
            FilaInterruptor("Contar en el patrimonio", null, patrimonio) { patrimonio = it }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "La predeterminada sale elegida al apuntar un movimiento. Sin «Contar en el patrimonio», la cuenta sigue con su saldo pero no suma en el patrimonio neto.",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
    }
}

/** 34 Detalle de movimiento con el menú de acciones abierto. */
@Composable
fun Pantalla34(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val m = finance.selectedMovement ?: return
    var menu by remember { mutableStateOf(true) }
    val action = rememberAction()
    val cat = finance.category(m.categoryId)
    val editar = {
        finance.movementForm = MovementForm(movement = m)
        nav.go(7)
    }
    StmScreen(
        topBar = {
            TopBar(MovementText.display(m.description), onNav = nav::back) {
                IconBtn(StmIcons.edit, editar, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, { menu = !menu }, contentDescription = "Más opciones")
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (menu) {
            {
                Box(
                    Modifier.matchParentSize()
                        .clickable(remember { MutableInteractionSource() }, indication = null) { menu = false },
                )
                // Barra superior (64) + 96 del diseño, a 12 dp del borde derecho.
                MenuDesplegable(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 160.dp, end = 12.dp)) {
                    ElementoMenu(StmIcons.edit, "Editar", onClick = editar)
                    ElementoMenu(StmIcons.contentCopy, "Duplicar") {
                        action.run {
                            finance.add(m.toDraft().copy(importHash = null))
                            nav.back()
                        }
                    }
                    ElementoMenu(StmIcons.check, if (m.isReviewed) "Sin revisar" else "Marcar revisado") {
                        menu = false
                        action.run { finance.update(MovementBulkEdit(reviewed = !m.isReviewed).changes(listOf(m))) }
                    }
                    ElementoMenu(if (m.excluded) StmIcons.visibility else StmIcons.visibilityOff, if (m.excluded) "Volver a contar" else "Excluir") {
                        menu = false
                        action.run { finance.update(MovementBulkEdit(excluded = !m.excluded).changes(listOf(m))) }
                    }
                    ElementoMenu(StmIcons.eventRepeat, "Aplazar") {
                        finance.cards.selectedId = m.accountId
                        finance.cards.purchaseId = m.id
                        nav.go(13)
                    }
                    Spacer(Modifier.height(8.dp))
                    Divider(inset = 0.dp, endInset = 0.dp)
                    Spacer(Modifier.height(8.dp))
                    ElementoMenu(StmIcons.delete, "Eliminar", Stm.colors.error, Stm.colors.error) {
                        action.run {
                            finance.delete(m)
                            finance.lastDeleted = null
                            nav.back()
                        }
                    }
                }
            }
        } else null,
    ) {
        CifraCuenta(
            listOfNotNull(cat?.name ?: "Sin categoría", finance.account(m.accountId)?.name).joinToString(" · "),
            Money.format(m.amountMinor, signed = true),
            Fechas.largo(m.day, finance.today()),
        )
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento(!m.notes.isNullOrEmpty(), editar)
        m.notes?.takeIf { it.isNotEmpty() }?.let {
            Spacer(Modifier.height(16.dp))
            Text(it, style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        }
        val extra = listOfNotNull(
            m.payee,
            m.tags.takeIf { it.isNotEmpty() }?.joinToString(" ") { "#$it" },
            if (m.isReviewed) "Revisado" else null,
            if (m.excluded) "Excluido del presupuesto" else null,
        )
        if (extra.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text(extra.joinToString(" · "), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        }
    }
}

/** «Actualizar saldo»: escribes lo que marca el banco y se apunta hoy un «AJUSTE DE SALDO» por la diferencia. */
@Composable
private fun BoxScope.HojaAjusteSaldo(finance: FinanceModel, account: Account, cerrar: () -> Unit) {
    val c = Stm.colors
    var real by remember { mutableStateOf("") }
    val action = rememberAction()
    val actual = finance.balance(account)
    val diferencia = Money.entered(real)?.let { it - actual }
    BottomSheet("Actualizar saldo", "Saldo en la app: ${Money.format(actual)}", onDismiss = cerrar) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            FilledField("Saldo real", real, { real = it }, suffix = "€", keyboard = KeyboardType.Decimal, autoFocus = true, calculator = true)
            Spacer(Modifier.height(8.dp))
            Text(
                if (diferencia != null && diferencia != 0L) "Ajuste: ${Money.format(diferencia, signed = true, options = Money.display.copy(plusSign = true))}"
                else "Se apunta un movimiento «Ajuste de saldo» por la diferencia, hoy. No cuenta como gasto ni como ingreso.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            action.error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, style = StmType.bodySmall, color = c.error)
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Btn("Cancelar", cerrar, kind = BtnKind.Text)
                Btn("Guardar", {
                    action.run {
                        val valor = Money.entered(real) ?: throw AppError.InvalidInput("Escribe el saldo, por ejemplo 1.250,00.")
                        finance.adjustBalance(account, valor)
                        cerrar()
                    }
                })
            }
        }
    }
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

// shortcut: la pantalla no es perezosa, se pintan como mucho 200 filas; pasar a LazyColumn si hace falta ver más.
private const val MAX_FILAS = 200

/** Barra de 05 y 08: atrás, título, filtros (con cuántos hay puestos) y más opciones. */
@Composable
private fun MovimientosTopBar(nav: Nav, filtros: Int = 0, onFiltros: (() -> Unit)? = null, onMas: (() -> Unit)? = null) {
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
private fun FilaMovimiento(m: Movement, finance: FinanceModel, detalle: String? = null, elegido: Boolean? = null, onClick: () -> Unit) {
    val c = Stm.colors
    val cat = finance.category(m.categoryId)
    val icono = iconoCategoria(cat)
    val partes = listOfNotNull(
        detalle ?: cat?.name ?: "Sin categoría",
        if (detalle == null) finance.account(m.accountId)?.name else null,
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

/** Abajo, en modo «Seleccionar»: cuántos hay y qué hacer con todos. */
@Composable
private fun BarraSeleccion(
    cuantos: Int,
    todos: Boolean,
    onTodos: () -> Unit,
    onRevisado: () -> Unit,
    onEditar: () -> Unit,
    onBorrar: () -> Unit,
) {
    val c = Stm.colors
    Column(Modifier.fillMaxWidth().background(c.surfaceContainer).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (cuantos == 1) "1 seleccionado" else "$cuantos seleccionados", Modifier.weight(1f), style = StmType.titleSmall, color = c.onSurface)
            Btn(if (todos) "Ninguno" else "Todos", onTodos, kind = BtnKind.Text)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Btn("Revisado", onRevisado, kind = BtnKind.Tonal, icon = StmIcons.check, enabled = cuantos > 0)
            Btn("Editar", onEditar, kind = BtnKind.Outlined, icon = StmIcons.tune, enabled = cuantos > 0)
            Spacer(Modifier.weight(1f))
            Btn("Borrar", onBorrar, kind = BtnKind.Error, icon = StmIcons.delete, enabled = cuantos > 0)
        }
    }
}

/**
 * Cambiar varios movimientos a la vez: fecha, categoría, cuenta, beneficiario, etiquetas, revisado y excluido.
 * Lo que no se toca se queda como estaba en cada uno.
 */
@Composable
private fun BoxScope.HojaEdicionMasiva(finance: FinanceModel, movimientos: List<Movement>, cerrar: () -> Unit, hecho: () -> Unit) {
    val c = Stm.colors
    val action = rememberAction()
    var cambiaFecha by remember { mutableStateOf(false) }
    var fecha by remember { mutableStateOf(movimientos.firstOrNull()?.day ?: finance.today()) }
    var cambiaCategoria by remember { mutableStateOf(false) }
    var categoria by remember { mutableStateOf<String?>(null) }
    var cambiaCuenta by remember { mutableStateOf(false) }
    var cuenta by remember { mutableStateOf(finance.defaultAccount?.id) }
    var cambiaBeneficiario by remember { mutableStateOf(false) }
    var beneficiario by remember { mutableStateOf("") }
    var anadir by remember { mutableStateOf("") }
    var quitar by remember { mutableStateOf("") }
    var revisado by remember { mutableStateOf<Boolean?>(null) }
    var excluido by remember { mutableStateOf<Boolean?>(null) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    val edicion = MovementBulkEdit(
        bookedOn = if (cambiaFecha) fecha else null,
        categoryId = if (cambiaCategoria) Change.Set(categoria) else Change.Keep,
        accountId = if (cambiaCuenta) cuenta else null,
        excluded = excluido, reviewed = revisado,
        payee = if (cambiaBeneficiario) Change.Set(Payee.clean(beneficiario)) else Change.Keep,
        addTags = MovementTags.normalize(anadir), removeTags = MovementTags.normalize(quitar),
    )
    when (selector) {
        "categoria" -> SelectorSheet(
            "Categoría",
            listOf<Pair<String, () -> Unit>>("Sin categoría" to { categoria = null }) + finance.categories.map { cat -> cat.name to { categoria = cat.id } },
        ) { selector = null }
        "cuenta" -> SelectorSheet("Cuenta", finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }) { selector = null }
        else -> BottomSheet(if (movimientos.size == 1) "Editar 1 movimiento" else "Editar ${movimientos.size} movimientos", onDismiss = cerrar) {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
                FilaInterruptor("Cambiar la fecha", null, cambiaFecha) { cambiaFecha = it }
                if (cambiaFecha) {
                    FilledField("Fecha", Fechas.largo(fecha, finance.today()), modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
                }
                FilaInterruptor("Cambiar la categoría", null, cambiaCategoria) { cambiaCategoria = it }
                if (cambiaCategoria) {
                    FilledField("Categoría", finance.category(categoria)?.name ?: "Sin categoría", modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
                }
                FilaInterruptor("Cambiar la cuenta", null, cambiaCuenta) { cambiaCuenta = it }
                if (cambiaCuenta) {
                    FilledField("Cuenta", finance.account(cuenta)?.name ?: "Elige una cuenta", modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
                }
                FilaInterruptor("Cambiar el beneficiario", null, cambiaBeneficiario) { cambiaBeneficiario = it }
                if (cambiaBeneficiario) {
                    FilledField("Beneficiario (vacío lo quita)", beneficiario, { beneficiario = it }, Modifier.padding(horizontal = 16.dp).fillMaxWidth())
                }
                Column(Modifier.padding(16.dp)) {
                    val usadas = MovementTags.all(movimientos)
                    FilledField(
                        "Añadir etiquetas, p. ej. viaje", anadir, { anadir = it },
                        supporting = if (usadas.isEmpty()) null else "Ahora llevan: " + usadas.joinToString(" ") { "#$it" },
                    )
                    Spacer(Modifier.height(16.dp))
                    FilledField("Quitar etiquetas", quitar, { quitar = it })
                    Spacer(Modifier.height(16.dp))
                    Text("Revisado", style = StmType.labelLarge, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    ChipRow(Modifier.fillMaxWidth()) {
                        listOf(null to "No cambiar", true to "Marcar revisados", false to "Marcar sin revisar").forEach { (v, t) ->
                            Chip(t, selected = revisado == v, onClick = { revisado = v })
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Text("Presupuesto e informes", style = StmType.labelLarge, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    ChipRow(Modifier.fillMaxWidth()) {
                        listOf(null to "No cambiar", true to "Excluir", false to "Volver a contar").forEach { (v, t) ->
                            Chip(t, selected = excluido == v, onClick = { excluido = v })
                        }
                    }
                    action.error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, style = StmType.bodySmall, color = c.error)
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn("Cancelar", cerrar, kind = BtnKind.Text)
                        Btn("Guardar", {
                            action.run {
                                MovementTags.issue(edicion.addTags)?.let { throw AppError.InvalidInput(it) }
                                finance.update(edicion.changes(movimientos))
                                cerrar()
                                hecho()
                            }
                        }, enabled = !edicion.isEmpty)
                    }
                }
            }
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
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
private fun CifraCuenta(label: String, value: String, note: String) {
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
private fun ChipsMovimiento(conNota: Boolean, onNota: () -> Unit) {
    val c = Stm.colors
    ChipRow(Modifier.fillMaxWidth()) {
        Chip("Añadir nota", selected = conNota, onClick = onNota, icon = StmIcons.stickyNote2, labelColor = c.onSurface)
    }
}

/** «Menú» desplegable de 200 dp en `surface-container`. */
@Composable
private fun MenuDesplegable(modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Column(
        modifier.width(200.dp).shadow(3.dp, shape).clip(shape).background(Stm.colors.surfaceContainer)
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .padding(vertical = 8.dp),
        content = content,
    )
}

/** «Elemento de menú» (48 dp): icono de 24 y texto. */
@Composable
private fun ElementoMenu(
    icon: ImageVector,
    label: String,
    color: Color = Stm.colors.onSurface,
    iconTint: Color = Stm.colors.onSurfaceVariant,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).tap(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(icon, iconTint)
        Spacer(Modifier.width(12.dp))
        Text(label, style = StmType.bodyMedium, color = color)
    }
}
