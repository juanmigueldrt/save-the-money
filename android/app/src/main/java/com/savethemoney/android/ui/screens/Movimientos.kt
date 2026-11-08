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
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.monthEndBalances
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

/** 05 Movimientos: búsqueda, filtros, lista agrupada por día y aviso de borrado. */
@Composable
fun Pantalla05(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    var busqueda by remember { mutableStateOf("") }
    var filtros by remember { mutableStateOf(if (session.capture) setOf("Comida") else emptySet()) }
    var muestra by remember { mutableStateOf(session.capture) }
    val action = rememberAction()
    val nombres = finance.recent.mapNotNull { finance.category(it.categoryId)?.name }
    val categorias = nombres.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }.map { it.key }
    val query = busqueda.trim()
    val visibles = finance.recent.filter { m ->
        val nombre = finance.category(m.categoryId)?.name
        (filtros.isEmpty() || nombre in filtros) &&
            (query.isEmpty() || m.description.contains(query, ignoreCase = true) || nombre?.contains(query, ignoreCase = true) == true)
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
            MovimientosTopBar(nav)
            CampoBusqueda(busqueda, { busqueda = it }, "Comercio o categoría")
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                categorias.forEach { f ->
                    Chip(f, selected = f in filtros, onClick = { filtros = if (f in filtros) filtros - f else filtros + f })
                }
            }
            Spacer(Modifier.height(12.dp))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        fab = { Fab("Añadir") { nav.go(if (finance.activeAccounts.isEmpty()) 9 else 7) } },
        snackbar = if (borrado != null || muestra) {
            {
                // El diseño deja 16 dp entre FAB y snackbar; StmScreen pone 12.
                Spacer(Modifier.height(4.dp))
                Snackbar("Movimiento eliminado", "Deshacer") {
                    muestra = false
                    action.run { finance.undoDelete() }
                }
            }
        } else null,
    ) {
        if (visibles.isEmpty()) {
            Vacio(if (finance.recent.isEmpty()) "No hay movimientos. Apunta uno con Añadir o importa un CSV desde Más opciones." else "Nada coincide con la búsqueda.")
        } else {
            ListaMovimientos(visibles.take(MAX_FILAS), finance) { m ->
                finance.selectedMovementId = m.id
                nav.go(8)
            }
        }
    }
}

/** 06 Cuenta: saldo, acciones, evolución en 6 meses y sus movimientos por mes. */
@Composable
fun Pantalla06(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val account = finance.selectedAccount ?: return
    val c = Stm.colors
    var lista by remember(account.id) { mutableStateOf(emptyList<Movement>()) }
    var opciones by remember { mutableStateOf(false) }
    var confirmar by remember { mutableStateOf(false) }
    val action = rememberAction()
    LaunchedEffect(account.id, finance.recent) {
        try { lista = finance.movements(account) } catch (_: AppError) { /* se queda la lista que había */ }
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
        if (lista.isEmpty()) Vacio("Todavía no hay movimientos en esta cuenta.")
        lista.take(MAX_FILAS).groupBy { it.day.withDayOfMonth(1) }.forEach { (mes, items) ->
            ListCard {
                ListHeader(Fechas.mesTitulo(mes) + if (mes.year != hoy.year) " ${mes.year}" else "")
                items.forEachIndexed { i, m ->
                    if (i > 0) Divider()
                    FilaMovimiento(m, finance, Fechas.corto(m.day)) {
                        finance.selectedMovementId = m.id
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
    val base = remember { form.movement ?: if (session.capture) finance.recent.firstOrNull() else null }
    var tipo by remember { mutableIntStateOf(if (form.transfer) 2 else if (base?.isExpense == false) 1 else 0) }
    var importe by remember { mutableStateOf(base?.let { Money.format(abs(it.amountMinor)) } ?: "") }
    var concepto by remember { mutableStateOf(base?.description ?: "") }
    var categoria by remember { mutableStateOf(base?.categoryId) }
    var cuenta by remember { mutableStateOf(form.accountId ?: base?.accountId ?: finance.activeAccounts.firstOrNull()?.id) }
    var destino by remember { mutableStateOf<String?>(null) }
    var fecha by remember { mutableStateOf(base?.day ?: finance.today()) }
    var notas by remember { mutableStateOf(base?.notes ?: "") }
    var conNotas by remember { mutableStateOf(notas.isNotEmpty()) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    val action = rememberAction()
    val cuentas = finance.activeAccounts.map { it.name to it.id }
    val tipoCategoria = if (tipo == 1) CategoryKind.Income else CategoryKind.Expense
    val elegida = finance.category(categoria)

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val valor = Money.parse(importe)?.takeIf { it != 0L }?.let(::abs) ?: falla("Escribe un importe, por ejemplo 12,50.")
        val origen = cuenta ?: falla("Elige una cuenta.")
        val nota = notas.trim().ifEmpty { null }
        if (tipo == 2) {
            val hacia = destino ?: falla("Elige la cuenta de destino.")
            if (hacia == origen) falla("Elige dos cuentas distintas.")
            val cat = finance.categories(CategoryKind.Transfer).firstOrNull()?.id
            val texto = concepto.ifBlank { "Transferencia" }
            finance.importMovements(
                listOf(
                    MovementDraft(origen, cat, fecha, -valor, texto, nota),
                    MovementDraft(hacia, cat, fecha, valor, texto, nota),
                ),
            )
        } else {
            val draft = MovementDraft(origen, categoria, fecha, if (tipo == 0) -valor else valor, concepto, nota)
            draft.issue?.let(::falla)
            val editando = form.movement
            if (editando != null) {
                finance.update(
                    editando.copy(
                        accountId = draft.accountId, categoryId = draft.categoryId, bookedOn = draft.bookedOn.toString(),
                        amountMinor = draft.amountMinor, description = draft.description, notes = draft.notes,
                    ),
                )
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
        overlay = selector?.let { campo ->
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
        Column(
            Modifier.fillMaxWidth().height(116.dp).padding(top = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Importe", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Box(contentAlignment = Alignment.Center) {
                if (importe.isEmpty()) Text("0,00 €", style = StmType.displayLarge, color = c.onSurfaceVariant)
                BasicTextField(
                    importe, { importe = it }, Modifier.fillMaxWidth(), singleLine = true,
                    textStyle = StmType.displayLarge.copy(color = c.onSurface, textAlign = TextAlign.Center),
                    cursorBrush = SolidColor(c.primary),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Concepto", concepto, { concepto = it })
        Spacer(Modifier.height(16.dp))
        if (tipo == 2) {
            FilledField("Cuenta de destino", finance.account(destino)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "destino" })
        } else {
            FilledField("Categoría", elegida?.name ?: "Sin categoría", leading = iconoCategoria(elegida), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Cuenta", finance.account(cuenta)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
        Spacer(Modifier.height(16.dp))
        FilledField("Fecha", Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento(conNotas) { conNotas = !conNotas }
        if (conNotas) {
            Spacer(Modifier.height(16.dp))
            FilledField("Notas", notas, { notas = it })
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}

/** 08 Acciones del movimiento: la lista de 05 con la hoja de acciones abierta. */
@Composable
fun Pantalla08(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
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
            BottomSheet(m.description, "${Money.format(m.amountMinor, signed = true)} · ${Fechas.dia(m.day, finance.today())}", onDismiss = nav::back) {
                SheetItem(StmIcons.category, "Cambiar categoría", onClick = editar)
                SheetItem(StmIcons.callSplit, "Dividir gasto", onClick = null)
                SheetItem(StmIcons.eventRepeat, "Aplazar con la tarjeta") { nav.go(13) }
                SheetItem(StmIcons.visibilityOff, "Ocultar de informes", onClick = null)
                SheetItem(StmIcons.delete, "Eliminar") {
                    action.run {
                        finance.delete(m)
                        nav.back()
                    }
                }
            }
        },
    ) {
        ListaMovimientos(listOf(m), finance) {}
    }
}

/** 09 Nueva o editar cuenta: nombre, tipo, saldo inicial y si se comparte con el hogar. */
@Composable
fun Pantalla09(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val editando = remember { finance.takeAccountToEdit() }
    var nombre by remember { mutableStateOf(editando?.name ?: if (session.capture) "Cuenta ahorro" else "") }
    var tipo by remember { mutableStateOf(editando?.kind ?: if (session.capture) AccountKind.Savings else AccountKind.Checking) }
    var saldo by remember {
        mutableStateOf(editando?.openingMinor?.takeIf { it != 0L }?.let(Money::input) ?: if (session.capture) "1.500,00" else "")
    }
    var compartir by remember { mutableStateOf(editando?.isShared ?: true) }
    val action = rememberAction()
    val tipos = listOf(AccountKind.Checking, AccountKind.Savings, AccountKind.CreditCard, AccountKind.Cash, AccountKind.Investment)
        .let { if (tipo in it) it else it + tipo }

    fun guardar() = action.run {
        val apertura = if (saldo.isBlank()) 0L else Money.parse(saldo) ?: throw AppError.InvalidInput("El saldo inicial no es un importe válido.")
        val dueno = if (compartir) null else editando?.ownerId ?: session.profile?.id
        val draft = AccountDraft(nombre, tipo, apertura, dueno)
        draft.issue?.let { throw AppError.InvalidInput(it) }
        if (editando != null) {
            finance.updateAccount(editando.copy(name = draft.trimmedName, kind = tipo, openingMinor = apertura, ownerId = dueno))
        } else {
            finance.createAccount(draft)
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
        Spacer(Modifier.height(16.dp))
        FilledField("Saldo inicial", saldo, { saldo = it }, suffix = "€", keyboard = KeyboardType.Decimal)
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
    }
}

/** 34 Detalle de movimiento con el menú de acciones abierto. */
@Composable
fun Pantalla34(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
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
            TopBar(m.description, onNav = nav::back) {
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
                    ElementoMenu(StmIcons.eventRepeat, "Aplazar") { nav.go(13) }
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
    }
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

// shortcut: la pantalla no es perezosa, se pintan como mucho 200 filas; pasar a LazyColumn si hace falta ver más.
private const val MAX_FILAS = 200

/** Barra de 05 y 08: atrás, título, filtros y más opciones. */
@Composable
private fun MovimientosTopBar(nav: Nav) {
    TopBar("Movimientos", onNav = nav::back) {
        IconBtn(StmIcons.tune, null, contentDescription = "Filtros")
        IconBtn(StmIcons.moreVert, null, contentDescription = "Más opciones")
    }
}

/** Movimientos agrupados por día ("Hoy", "Ayer", "3 de noviembre"). */
@Composable
fun ListaMovimientos(items: List<Movement>, finance: FinanceModel, onClick: (Movement) -> Unit) {
    ListCard {
        items.groupBy { it.day }.forEach { (dia, delDia) ->
            ListHeader(Fechas.dia(dia, finance.today()))
            delDia.forEachIndexed { i, m ->
                if (i > 0) Divider()
                FilaMovimiento(m, finance, onClick = { onClick(m) })
            }
        }
    }
}

@Composable
private fun FilaMovimiento(m: Movement, finance: FinanceModel, detalle: String? = null, onClick: () -> Unit) {
    val c = Stm.colors
    val cat = finance.category(m.categoryId)
    val icono = iconoCategoria(cat)
    ListItem(
        m.description,
        detalle ?: listOfNotNull(cat?.name ?: "Sin categoría", finance.account(m.accountId)?.name).joinToString(" · "),
        trailingText = Money.format(m.amountMinor, signed = true),
        leading = { if (m.isExpense) LeadIcon(icono) else LeadIcon(icono, c.successContainer, c.onSuccessContainer) },
        onClick = onClick,
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
private fun CampoBusqueda(value: String, onValueChange: (String) -> Unit, placeholder: String) {
    val c = Stm.colors
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
                value, onValueChange, Modifier.fillMaxWidth(), singleLine = true,
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

/** Chips de acción «Dividir gasto» y «Añadir nota» (07 y 34). */
@Composable
private fun ChipsMovimiento(conNota: Boolean, onNota: () -> Unit) {
    val c = Stm.colors
    ChipRow(Modifier.fillMaxWidth()) {
        Chip("Dividir gasto", icon = StmIcons.callSplit, labelColor = c.onSurface)
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
