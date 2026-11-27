package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.Change
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementBulkEdit
import com.savethemoney.android.data.MovementDateFilter
import com.savethemoney.android.data.MovementFilter
import com.savethemoney.android.data.MovementKindFilter
import com.savethemoney.android.data.MovementStatusFilter
import com.savethemoney.android.data.MovementTags
import com.savethemoney.android.data.Payee
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.Vista
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo
import kotlinx.coroutines.delay

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
    // Las filas cargadas de la lista general (ORC-85). La búsqueda la hace el servidor; lo demás se filtra aquí, sobre lo cargado.
    val cargados = if (finance.list.accountId == null) finance.list.rows else emptyList()
    val visibles = filtro.copy(search = "").apply(cargados, finance.categories, finance.today(), finance.household.monthStartDay)
    val filtrando = filtro.activeCount > 0 || filtro.search.isNotBlank()
    LaunchedEffect(filtro.search) {
        // Al escribir, espera a que se pare un momento antes de preguntar al servidor.
        if (finance.list.search != filtro.search) delay(300)
        finance.showList(null, filtro.search)
    }
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
            CampoBusqueda(filtro.search, { finance.movementFilter = filtro.copy(search = it) }, stringResource(R.string.movimientos_concepto_beneficiario_etiqueta_o))
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
        fab = if (seleccionando) null else { { Fab(stringResource(R.string.comun_anadir)) { nav.go(if (finance.activeAccounts.isEmpty()) Route.FormCuenta() else Route.FormMovimiento()) } } },
        snackbar = if (action.error != null) {
            { Snackbar(action.error!!) }
        } else if (!seleccionando && borrado != null) {
            {
                // El diseño deja 16 dp entre FAB y snackbar; StmScreen pone 12.
                Spacer(Modifier.height(4.dp))
                Snackbar(stringResource(R.string.movimientos_movimiento_eliminado), stringResource(R.string.comun_deshacer)) {
                    action.run { finance.undoDelete() }
                }
            }
        } else null,
        overlay = when (hoja) {
            "filtros" -> { { HojaFiltros(finance, { hoja = it }, { eligeFecha = it }) } }
            "categoria" -> {
                {
                    SelectorSheet(
                        stringResource(R.string.comun_categoria),
                        listOf<Pair<String, () -> Unit>>(stringResource(R.string.movimientos_todas_las_categorias) to { finance.movementFilter = finance.movementFilter.copy(categoryId = null) }) +
                            (finance.categories(CategoryKind.Expense) + finance.categories(CategoryKind.Income) + finance.categories(CategoryKind.Transfer))
                                .map { cat -> cat.name to { finance.movementFilter = finance.movementFilter.copy(categoryId = cat.id) } },
                    ) { hoja = "filtros" }
                }
            }
            "masiva" -> { { HojaEdicionMasiva(finance, marcados, { hoja = null }) { terminaSeleccion() } } }
            "borrar" -> {
                {
                    StmDialog(
                        pluralStringResource(R.plurals.movimientos_borrar_movimientos, marcados.size, marcados.size),
                        if (marcados.any { it.transferId != null }) {
                            stringResource(R.string.movimientos_las_transferencias_se_borran_con)
                        } else {
                            stringResource(R.string.movimientos_no_se_puede_deshacer)
                        },
                        icon = StmIcons.deleteForever,
                        onDismiss = { hoja = null },
                        actions = {
                            Btn(stringResource(R.string.comun_cancelar), { hoja = null }, kind = BtnKind.Text)
                            Btn(stringResource(R.string.comun_borrar), {
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
                    BottomSheet(stringResource(R.string.movimientos_movimientos), onDismiss = { hoja = null }) {
                        if (finance.recent.isNotEmpty()) {
                            SheetItem(StmIcons.check, if (seleccionando) stringResource(R.string.movimientos_terminar_seleccion) else stringResource(R.string.movimientos_seleccionar)) {
                                hoja = null
                                if (seleccionando) terminaSeleccion() else seleccionando = true
                            }
                        }
                        if (filtrando) {
                            SheetItem(StmIcons.close, stringResource(R.string.movimientos_quitar_filtros_y_busqueda)) {
                                hoja = null
                                finance.movementFilter = MovementFilter()
                            }
                        }
                        SheetItem(if (Vista.incognito) StmIcons.visibility else StmIcons.visibilityOff, if (Vista.incognito) stringResource(R.string.comun_mostrar_importes) else stringResource(R.string.comun_ocultar_importes)) {
                            hoja = null
                            Vista.setIncognito(!Vista.incognito)
                        }
                        SheetItem(StmIcons.uploadFile, stringResource(R.string.importar_csv_importar_csv)) {
                            hoja = null
                            nav.go(Route.ImportarCsv())
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
            when {
                finance.listError != null -> Unit
                cargados.isEmpty() && (finance.isLoading || finance.isLoadingList || finance.list.accountId != null) -> Vacio(stringResource(R.string.comun_cargando))
                cargados.isEmpty() && filtro.search.isBlank() -> Vacio(stringResource(R.string.movimientos_no_hay_movimientos_apunta_uno_con))
                else -> Vacio(stringResource(R.string.movimientos_nada_coincide_con_la_busqueda_o))
            }
        } else {
            ListaMovimientos(visibles, finance, seleccion = if (seleccionando) elegidos else null) { m ->
                if (seleccionando) {
                    elegidos = if (m.id in elegidos) elegidos - m.id else elegidos + m.id
                } else {
                    finance.tappedMovement = m
                    nav.go(Route.AccionesMovimiento(m.id))
                }
            }
        }
        if (finance.list.accountId == null) PieLista(finance)
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
    BottomSheet(stringResource(R.string.movimientos_filtros_2), onDismiss = { abrir(null) }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Text(stringResource(R.string.comun_cuenta), style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                Chip(stringResource(R.string.movimientos_todas), selected = filtro.accountId == null, onClick = { cambia(filtro.copy(accountId = null)) })
                finance.accounts.forEach { a ->
                    Chip(a.name, selected = filtro.accountId == a.id, onClick = { cambia(filtro.copy(accountId = a.id)) })
                }
            }
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.movimientos_tipo), style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementKindFilter.entries.forEach { k -> Chip(stringResource(k.titulo), selected = filtro.kind == k, onClick = { cambia(filtro.copy(kind = k)) }) }
            }
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.movimientos_estado), style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementStatusFilter.entries.forEach { e -> Chip(stringResource(e.titulo), selected = filtro.status == e, onClick = { cambia(filtro.copy(status = e)) }) }
            }
            val etiquetas = finance.knownTags
            if (etiquetas.isNotEmpty() || filtro.tag != null) {
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.movimientos_etiqueta), style = StmType.labelLarge, color = c.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                ChipRow(Modifier.fillMaxWidth()) {
                    Chip(stringResource(R.string.movimientos_todas_las_etiquetas), selected = filtro.tag == null, onClick = { cambia(filtro.copy(tag = null)) })
                    (etiquetas + listOfNotNull(filtro.tag)).distinct().forEach { t ->
                        Chip("#$t", selected = filtro.tag == t, onClick = { cambia(filtro.copy(tag = t)) })
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            FilledField(
                stringResource(R.string.comun_categoria), finance.category(filtro.categoryId)?.name ?: stringResource(R.string.movimientos_todas_las_categorias),
                leading = filtro.categoryId?.let { iconoCategoria(finance.category(it)) },
                trailing = StmIcons.arrowDropDown, onClick = { abrir("categoria") },
            )
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.movimientos_fechas), style = StmType.labelLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) {
                MovementDateFilter.entries.forEach { d ->
                    Chip(stringResource(d.titulo), selected = filtro.dates == d, onClick = {
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
                    FilledField(stringResource(R.string.movimientos_desde_2), Fechas.largo(filtro.customFrom ?: hoy, hoy), modifier = Modifier.weight(1f), trailing = StmIcons.calendarToday, onClick = { eligeFecha("desde") })
                    FilledField(stringResource(R.string.movimientos_hasta), Fechas.largo(filtro.customThrough ?: hoy, hoy), modifier = Modifier.weight(1f), trailing = StmIcons.calendarToday, onClick = { eligeFecha("hasta") })
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                if (filtro.activeCount > 0) Btn(stringResource(R.string.movimientos_quitar_filtros), { cambia(MovementFilter(search = filtro.search)) }, kind = BtnKind.Text)
                Btn(stringResource(R.string.movimientos_ver_movimientos), { abrir(null) })
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
                Text(pluralStringResource(R.plurals.movimientos_movimientos_2, items.size, items.size), style = StmType.titleMedium, color = c.onSurface)
                Text(
                    stringResource(R.string.movimientos_gastos_ingresos, Money.format(gastos, signed = true), Money.format(ingresos, signed = true)),
                    style = StmType.bodySmall, color = c.onSurfaceVariant,
                )
            }
            Btn(stringResource(R.string.movimientos_quitar_filtros), quitar, kind = BtnKind.Text)
        }
    }
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
            Text(pluralStringResource(R.plurals.movimientos_seleccionados, cuantos, cuantos), Modifier.weight(1f), style = StmType.titleSmall, color = c.onSurface)
            Btn(if (todos) stringResource(R.string.movimientos_ninguno) else stringResource(R.string.movimientos_todos), onTodos, kind = BtnKind.Text)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Btn(stringResource(R.string.movimientos_revisado), onRevisado, kind = BtnKind.Tonal, icon = StmIcons.check, enabled = cuantos > 0)
            Btn(stringResource(R.string.comun_editar), onEditar, kind = BtnKind.Outlined, icon = StmIcons.tune, enabled = cuantos > 0)
            Spacer(Modifier.weight(1f))
            Btn(stringResource(R.string.comun_borrar), onBorrar, kind = BtnKind.Error, icon = StmIcons.delete, enabled = cuantos > 0)
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
            stringResource(R.string.comun_categoria),
            listOf<Pair<String, () -> Unit>>(stringResource(R.string.comun_sin_categoria) to { categoria = null }) + finance.categories.map { cat -> cat.name to { categoria = cat.id } },
        ) { selector = null }
        "cuenta" -> SelectorSheet(stringResource(R.string.comun_cuenta), finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }) { selector = null }
        else -> BottomSheet(pluralStringResource(R.plurals.movimientos_editar_movimientos, movimientos.size, movimientos.size), onDismiss = cerrar) {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
                FilaInterruptor(stringResource(R.string.movimientos_cambiar_la_fecha), null, cambiaFecha) { cambiaFecha = it }
                if (cambiaFecha) {
                    FilledField(stringResource(R.string.comun_fecha), Fechas.largo(fecha, finance.today()), modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
                }
                FilaInterruptor(stringResource(R.string.movimientos_cambiar_la_categoria), null, cambiaCategoria) { cambiaCategoria = it }
                if (cambiaCategoria) {
                    FilledField(stringResource(R.string.comun_categoria), finance.category(categoria)?.name ?: stringResource(R.string.comun_sin_categoria), modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
                }
                FilaInterruptor(stringResource(R.string.movimientos_cambiar_la_cuenta), null, cambiaCuenta) { cambiaCuenta = it }
                if (cambiaCuenta) {
                    FilledField(stringResource(R.string.comun_cuenta), finance.account(cuenta)?.name ?: stringResource(R.string.comun_elige_una_cuenta), modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
                }
                FilaInterruptor(stringResource(R.string.movimientos_cambiar_el_beneficiario), null, cambiaBeneficiario) { cambiaBeneficiario = it }
                if (cambiaBeneficiario) {
                    FilledField(stringResource(R.string.movimientos_beneficiario_vacio_lo_quita), beneficiario, { beneficiario = it }, Modifier.padding(horizontal = 16.dp).fillMaxWidth())
                }
                Column(Modifier.padding(16.dp)) {
                    val usadas = MovementTags.all(movimientos)
                    FilledField(
                        stringResource(R.string.movimientos_anadir_etiquetas_p_ej_viaje), anadir, { anadir = it },
                        supporting = if (usadas.isEmpty()) null else stringResource(R.string.movimientos_ahora_llevan, usadas.joinToString(" ") { "#$it" }),
                    )
                    Spacer(Modifier.height(16.dp))
                    FilledField(stringResource(R.string.movimientos_quitar_etiquetas), quitar, { quitar = it })
                    Spacer(Modifier.height(16.dp))
                    Text(stringResource(R.string.movimientos_revisado), style = StmType.labelLarge, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    ChipRow(Modifier.fillMaxWidth()) {
                        listOf(null to stringResource(R.string.movimientos_no_cambiar), true to stringResource(R.string.movimientos_marcar_revisados), false to stringResource(R.string.acciones_movimiento_marcar_sin_revisar)).forEach { (v, t) ->
                            Chip(t, selected = revisado == v, onClick = { revisado = v })
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Text(stringResource(R.string.movimientos_presupuesto_e_informes), style = StmType.labelLarge, color = c.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    ChipRow(Modifier.fillMaxWidth()) {
                        listOf(null to stringResource(R.string.movimientos_no_cambiar), true to stringResource(R.string.movimientos_excluir), false to stringResource(R.string.movimientos_volver_a_contar)).forEach { (v, t) ->
                            Chip(t, selected = excluido == v, onClick = { excluido = v })
                        }
                    }
                    action.error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, style = StmType.bodySmall, color = c.error)
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn(stringResource(R.string.comun_cancelar), cerrar, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_guardar), {
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
