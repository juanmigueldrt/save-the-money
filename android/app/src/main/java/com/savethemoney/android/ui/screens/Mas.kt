package com.savethemoney.android.ui.screens

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AmountColumns
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CsvImporter
import androidx.compose.foundation.isSystemInDarkTheme
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.CsvMapping
import com.savethemoney.android.data.MovementsCsv
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.data.CsvTable
import com.savethemoney.android.data.DateOrder
import com.savethemoney.android.data.ImportResult
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Donut
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.SelectorSheet
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.UUID

/** 25 Inversiones: cartera con evolución, reparto y posiciones. */
@Composable
fun Pantalla25(nav: Nav) {
    val c = Stm.colors
    var range by remember { mutableIntStateOf(2) }
    StmScreen(
        topBar = {
            MediumTopBar("Cartera", onBack = nav::back) {
                IconBtn(StmIcons.eventRepeat, { nav.go(27) }, contentDescription = "Inversiones recurrentes")
                IconBtn(StmIcons.add, { nav.go(26) }, contentDescription = "Comprar")
            }
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
    ) {
        Spacer(Modifier.height(7.5.dp))
        Text("31.950 €", style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Pill("+3.420 € (+12,0 %)")
            Spacer(Modifier.width(8.dp))
            Text("desde el inicio", style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(20.dp))
        HugSegmented(listOf("1S", "1M", "1A", "Todo"), range) { range = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            LineChart(listOf(116f, 100.4f, 108.2f, 73.1f, 45.8f, 55.6f, 22.4f, 0f).map { 1f - it / 120f })
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Donut(listOf(Slice(0.62f, c.primary), Slice(0.24f, c.tertiary), Slice(0.14f, c.secondaryContainer)), 112.dp, 16.dp)
                Spacer(Modifier.width(16.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Legend(c.primary, "Fondos indexados 62 %")
                    Legend(c.tertiary, "Acciones 24 %")
                    Legend(c.secondaryContainer, "Efectivo 14 %")
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Fondo indexado mundial", "112,4 participaciones",
                leading = { LeadIcon(StmIcons.public, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("19.810 €", style = StmType.labelLarge, color = c.onSurface)
                        Text("+14,2 %", style = StmType.bodySmall, color = c.onSurfaceVariant)
                    }
                },
                onClick = { nav.go(26) },
            )
        }
    }
}

/** 26 Comprar activo: precio, evolución, posición y compra por importe o participaciones. */
@Composable
fun Pantalla26(nav: Nav) {
    val c = Stm.colors
    var mode by remember { mutableIntStateOf(0) }
    var amount by remember { mutableStateOf("300,00") }
    var fee by remember { mutableStateOf("0,10") }
    StmScreen(
        topBar = {
            TopBar("Fondo indexado mundial", onNav = nav::back) {
                IconBtn(StmIcons.edit, null, contentDescription = "Editar")
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Precio · apuntado hoy", style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(3.5.dp))
        Text("176,25 €", style = StmType.displaySmall, color = c.onSurface)
        Spacer(Modifier.height(4.5.dp))
        Pill("+0,8 % hoy")
        Spacer(Modifier.height(20.dp))
        StmCard {
            LineChart(listOf(96f, 80.2f, 85.5f, 53.9f, 32.9f, 43.4f, 17.1f, 0f).map { 1f - it / 100f }, plotHeight = 100.dp)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Tu posición", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            DataRow("Participaciones", "112,40")
            Spacer(Modifier.height(8.dp))
            DataRow("Valor", "19.810 €")
            Spacer(Modifier.height(8.dp))
            DataRow("Rentabilidad", "+2.462 € (+14,2 %)", c.success)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Comprar", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Segmented(listOf("Por importe", "Por participaciones"), mode, { mode = it })
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SuffixField("Importe", amount, { amount = it }, "€", Modifier.weight(1f))
                SuffixField("Comisión", fee, { fee = it }, "%", Modifier.weight(1f))
            }
            Spacer(Modifier.height(12.dp))
            Text("≈ 1,70 participaciones · comisión 0,30 €", style = StmType.bodySmall, color = c.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Btn("Comprar", nav::back, Modifier.fillMaxWidth())
        }
    }
}

/** 27 Inversiones recurrentes: calendario del mes con los días de aportación y planes activos. */
@Composable
fun Pantalla27(nav: Nav) {
    val c = Stm.colors
    var world by remember { mutableStateOf(true) }
    var bonds by remember { mutableStateOf(false) }
    StmScreen(
        topBar = {
            TopBar("Inversiones recurrentes", onNav = nav::back) {
                IconBtn(StmIcons.add, null, contentDescription = "Añadir")
            }
        },
    ) {
        StmCard {
            Text("Noviembre", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                    Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) {
                        Text(it, style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            // Noviembre de 2026 empieza en domingo en el calendario real; el diseño lo pinta en sábado.
            val days = List(5) { null } + (1..30).toList()
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                days.chunked(7).forEach { week ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        week.forEach { day ->
                            val (bg, fg) = when (day) {
                                5 -> c.primary to c.onPrimary
                                1, 20 -> c.secondaryContainer to c.onSecondaryContainer
                                else -> Color.Transparent to c.onSurface
                            }
                            Box(Modifier.size(40.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
                                if (day != null) Text("$day", style = StmType.bodyMedium, color = fg)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                "Fondo indexado mundial", "300 € el día 1 de cada mes",
                leading = { LeadIcon(StmIcons.public, c.tertiaryContainer, c.onTertiaryContainer) },
                trailing = { StmSwitch(world) { world = it } },
                onClick = { nav.go(26) },
            )
            Divider()
            ListItem(
                "Fondo de bonos", "100 € el día 20 · en pausa",
                leading = { LeadIcon(StmIcons.accountBalance, c.surfaceContainerHighest, c.onSurfaceVariant) },
                trailing = { StmSwitch(bonds) { bonds = it } },
            )
        }
    }
}

/** 30 Más opciones: menú de secciones, datos y preferencias. */
@Composable
fun Pantalla30(nav: Nav) {
    val finance = LocalSession.current.finance
    val categorias = finance?.categories?.size ?: 0
    val session = LocalSession.current
    val context = LocalContext.current
    val tema = session.profile?.theme ?: AppTheme.System
    val oscuro = when (tema) {
        AppTheme.Light -> false
        AppTheme.Dark -> true
        AppTheme.System -> isSystemInDarkTheme()
    }
    var eligeTema by remember { mutableStateOf(false) }
    val action = rememberAction()
    var alerts by remember(finance) { mutableStateOf(finance?.planning?.alertsEnabled ?: true) }
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeTema) {
            {
                SelectorSheet(
                    "Tema", AppTheme.entries.map { t -> t.title to { action.run { session.setTheme(t) } } }, { eligeTema = false },
                )
            }
        } else {
            null
        },
    ) {
        ListCard {
            MenuRow(StmIcons.creditCard, "Tarjetas") { nav.go(10) }
            MenuRow(StmIcons.eventRepeat, "Pagos fijos", count = LocalSession.current.finance?.planning?.activeSeries?.size?.toString()) { nav.go(20) }
            MenuRow(StmIcons.monitoring, "Patrimonio, informes y score") { nav.go(17) }
            MenuRow(StmIcons.candlestickChart, "Inversiones") { nav.go(25) }
            MenuRow(StmIcons.group, "Hogar") { nav.go(28) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Datos")
            MenuRow(StmIcons.uploadFile, "Importar CSV") { nav.go(32) }
            MenuRow(StmIcons.pictureAsPdf, "PDF de pagos del mes") { nav.go(36) }
            MenuRow(StmIcons.tableView, "CSV para Excel") {
                action.run {
                    val modelo = finance ?: return@run
                    val datos = modelo.exportCsv()
                    val fichero = ficheroExportar(context, MovementsCsv.fileName(modelo.today()))
                    withContext(Dispatchers.IO) { fichero.writeBytes(datos) }
                    compartir(context, fichero, "text/csv")
                }
            }
            MenuRow(StmIcons.category, "Categorías", count = categorias.toString()) { nav.go(31) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Preferencias")
            ListItem(
                "Tema oscuro", if (tema == AppTheme.System) "Igual que el sistema" else tema.title,
                leading = { StmIcon(StmIcons.darkMode, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(oscuro) { activo -> action.run { session.setTheme(if (activo) AppTheme.Dark else AppTheme.Light) } }
                },
                onClick = { eligeTema = true },
            )
            ListItem(
                "Avisos de cobros y límites",
                leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(alerts) {
                        alerts = it
                        finance?.planning?.alertsEnabled = it
                        finance?.cards?.reschedule()
                    }
                },
            )
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false) { nav.go(33) }
        }
        // No está en el diseño; va la última para no mover lo anterior.
        Spacer(Modifier.height(16.dp))
        ListCard {
            MenuRow(StmIcons.logout, "Cerrar sesión", chevron = false) { action.run { session.signOut() } }
        }
        Spacer(Modifier.height(16.dp))
    }
}

/** 31 Categorías: gastos o ingresos agrupados; tocar una para editarla. */
@Composable
fun Pantalla31(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val c = Stm.colors
    var income by remember { mutableStateOf(false) }
    var editando by remember { mutableStateOf<BudgetCategory?>(null) }
    val kind = if (income) CategoryKind.Income else CategoryKind.Expense
    val lista = finance.categories(kind)
    StmScreen(
        topBar = {
            TopBar("Categorías", onNav = nav::back) {
                IconBtn(StmIcons.add, {
                    editando = BudgetCategory(
                        UUID.randomUUID().toString(), finance.household.id, "", kind,
                        if (income) null else BudgetGroup.Needs,
                    )
                }, contentDescription = "Añadir categoría")
            }
        },
        overlay = editando?.let { cat -> { DialogoCategoria(cat, finance) { editando = null } } },
    ) {
        ChipRow {
            Chip("Gastos", selected = !income, onClick = { income = false })
            Chip("Ingresos", selected = income, onClick = { income = true })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            val grupos = lista.groupBy { it.budgetGroup }
            (BudgetGroup.entries + listOf(null)).forEach { grupo ->
                val filas = grupos[grupo] ?: return@forEach
                when {
                    grupo != null -> ListHeader(grupo.title)
                    !income -> ListHeader("Sin grupo")
                }
                filas.forEach { cat ->
                    val deseo = grupo == BudgetGroup.Wants
                    CategoryRow(
                        iconoCategoria(cat), cat.name,
                        if (deseo) c.tertiaryContainer else c.secondaryContainer,
                        if (deseo) c.onTertiaryContainer else c.onSecondaryContainer,
                    ) { editando = cat }
                }
            }
        }
    }
}

/** Crear, renombrar, cambiar de grupo o borrar una categoría. */
@Composable
private fun BoxScope.DialogoCategoria(inicial: BudgetCategory, finance: FinanceModel, onDismiss: () -> Unit) {
    val c = Stm.colors
    val existe = finance.categories.any { it.id == inicial.id }
    var nombre by remember { mutableStateOf(inicial.name) }
    var grupo by remember { mutableStateOf(inicial.budgetGroup) }
    var borrando by remember { mutableStateOf(false) }
    val action = rememberAction()
    if (borrando) {
        val usos = finance.recent.count { it.categoryId == inicial.id }
        StmDialog(
            "¿Borrar «${inicial.name}»?",
            if (usos > 0) "$usos movimientos recientes se quedarán sin categoría." else "No hay movimientos recientes con esta categoría.",
            icon = StmIcons.deleteForever,
            onDismiss = { borrando = false },
            actions = {
                Btn("Cancelar", { borrando = false }, kind = BtnKind.Text)
                Btn("Borrar", {
                    action.run {
                        finance.delete(inicial)
                        onDismiss()
                    }
                }, kind = BtnKind.Error)
            },
        ) { action.error?.let { Text(it, style = StmType.bodySmall, color = c.error) } }
        return
    }
    StmDialog(
        if (existe) "Editar categoría" else "Nueva categoría",
        onDismiss = onDismiss,
        actions = {
            if (existe) Btn("Borrar", { borrando = true }, kind = BtnKind.Error)
            Btn("Cancelar", onDismiss, kind = BtnKind.Text)
            Btn("Guardar", {
                action.run {
                    finance.save(inicial.copy(name = nombre, budgetGroup = grupo))
                    onDismiss()
                }
            }, kind = BtnKind.Text)
        },
    ) {
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Nombre", nombre, { nombre = it }, labelBackground = c.surfaceContainerHigh, autoFocus = !existe,
            error = action.error != null, supporting = action.error,
        )
        if (inicial.kind == CategoryKind.Expense) {
            Spacer(Modifier.height(12.dp))
            ChipRow {
                BudgetGroup.entries.forEach { g -> Chip(g.title, selected = g == grupo, onClick = { grupo = g }) }
            }
        }
    }
}

/** 32 Importar CSV: archivo elegido, columnas, vista previa e importación. El archivo no sale del móvil. */
@Composable
fun Pantalla32(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val cardShape = RoundedCornerShape(12.dp)
    var nombre by remember { mutableStateOf<String?>(null) }
    var tabla by remember { mutableStateOf<CsvTable?>(null) }
    var mapeo by remember { mutableStateOf<CsvMapping?>(null) }
    var cuenta by remember { mutableStateOf(finance.takeCsvAccount() ?: finance.activeAccounts.firstOrNull()?.id) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var resultado by remember { mutableStateOf<ImportResult?>(null) }
    var selector by remember { mutableStateOf<String?>(null) }
    val action = rememberAction()

    fun cargar(texto: String, archivo: String) {
        val t = CsvTable.parse(texto)
        nombre = archivo
        tabla = t
        mapeo = CsvMapping.detect(t)
        resultado = null
        aviso = null
    }
    LaunchedEffect(Unit) { if (session.capture) cargar(CSV_MUESTRA, "movimientos-octubre.csv") }
    val elegir = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val leido = withContext(Dispatchers.IO) { leerCsv(context, uri) }
            leido.onSuccess { (texto, archivo) -> cargar(texto, archivo) }.onFailure { aviso = it.message }
        }
    }
    val abrir = { elegir.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel", "application/octet-stream")) }

    val t = tabla
    val m = mapeo
    val filas = remember(t, m, cuenta) {
        val id = cuenta
        if (t != null && m != null && id != null) CsvImporter.rows(t, m, id) else emptyList()
    }
    val validas = filas.mapNotNull { it.draft }
    val problemas = filas.filter { it.issue != null }
    val anchura = t?.rows?.maxOfOrNull { it.size } ?: 0
    val cabeceras = m?.headerRow?.let { t?.rows?.get(it) } ?: emptyList()
    fun letra(i: Int) = "Columna " + if (i < 26) ('A' + i).toString() else (i + 1).toString()
    fun columna(i: Int) = letra(i) + (cabeceras.getOrNull(i)?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: "")

    StmScreen(
        topBar = { TopBar("Importar CSV", navIcon = StmIcons.close, onNav = nav::back) },
        // En una snackbar: la vista previa puede ocupar más que la pantalla.
        snackbar = (action.error ?: resultado?.let { r ->
            "${r.inserted} movimientos importados." + if (r.duplicates > 0) " ${r.duplicates} ya estaban y no se han repetido." else ""
        })?.let { texto -> { Snackbar(texto) } },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn(
                    when {
                        action.busy -> "Importando…"
                        validas.isEmpty() -> "Importar"
                        else -> "Importar ${validas.size} movimientos"
                    },
                    {
                        action.run {
                            aviso = null
                            resultado = finance.importMovements(validas)
                        }
                    },
                    Modifier.fillMaxWidth(), large = true, enabled = validas.isNotEmpty() && !action.busy,
                )
            }
        },
        overlay = selector?.let { campo ->
            {
                val cerrar = { selector = null }
                val columnas = { fijar: (Int) -> Unit -> (0 until anchura).map { i -> columna(i) to { fijar(i) } } }
                when (campo) {
                    "fecha" -> SelectorSheet("Fecha", columnas { i -> mapeo = mapeo?.copy(date = i) }, cerrar)
                    "concepto" -> SelectorSheet("Concepto", columnas { i -> mapeo = mapeo?.copy(description = i) }, cerrar)
                    "importe" -> SelectorSheet("Importe", columnas { i -> mapeo = mapeo?.copy(amount = AmountColumns.Signed(i)) }, cerrar)
                    "cargos" -> SelectorSheet("Cargos (gastos)", columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split(i, (it.amount as? AmountColumns.Split)?.credit ?: i)) }
                    }, cerrar)
                    "abonos" -> SelectorSheet("Abonos (ingresos)", columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split((it.amount as? AmountColumns.Split)?.debit ?: i, i)) }
                    }, cerrar)
                    "formato" -> SelectorSheet("Formato de fecha", DateOrder.entries.map { o -> o.title to { mapeo = mapeo?.copy(dateOrder = o) } }, cerrar)
                    else -> SelectorSheet("Cuenta de destino", finance.activeAccounts.map { a -> a.name to { cuenta = a.id; resultado = null } }, cerrar)
                }
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().height(72.dp).clip(cardShape).background(c.surface)
                .border(1.dp, c.outlineVariant, cardShape).tap(onClick = abrir).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LeadIcon(StmIcons.description, c.tertiaryContainer, c.onTertiaryContainer)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(nombre ?: "Elegir archivo CSV", style = StmType.titleMedium, color = c.onSurface, maxLines = 1)
                Text(
                    t?.let { "${it.rows.size - (m?.firstDataRow ?: 0)} filas · separador ${if (it.delimiter == '\t') "tabulador" else it.delimiter}" }
                        ?: "El archivo no se sube: solo se guardan los movimientos",
                    style = StmType.bodySmall, color = c.onSurfaceVariant, maxLines = 1,
                )
            }
            if (nombre != null) IconBtn(StmIcons.close, {
                nombre = null
                tabla = null
                mapeo = null
                resultado = null
            }, contentDescription = "Quitar archivo")
        }
        aviso?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
        if (t != null && m == null) {
            Spacer(Modifier.height(12.dp))
            Text("No he reconocido las columnas de fecha, concepto e importe de este archivo.", style = StmType.bodySmall, color = c.error)
        }
        if (finance.activeAccounts.isEmpty()) {
            Spacer(Modifier.height(12.dp))
            Btn("Crear una cuenta", { nav.go(9) }, kind = BtnKind.Tonal, icon = StmIcons.add)
        }
        if (m != null) {
            Spacer(Modifier.height(16.dp))
            Text("Qué columna es cada dato", style = StmType.titleSmall, color = c.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))
            FilledField("Fecha", "${letra(m.date)} · ${m.dateOrder.title.lowercase()}", trailing = StmIcons.arrowDropDown, onClick = { selector = "fecha" })
            Spacer(Modifier.height(16.dp))
            FilledField("Concepto", columna(m.description), trailing = StmIcons.arrowDropDown, onClick = { selector = "concepto" })
            when (val a = m.amount) {
                is AmountColumns.Signed -> {
                    Spacer(Modifier.height(16.dp))
                    val coma = t.orEmptyRows().drop(m.firstDataRow).take(20).any { ',' in it.getOrElse(a.column) { "" } }
                    FilledField("Importe", letra(a.column) + if (coma) " · coma decimal" else "", trailing = StmIcons.arrowDropDown, onClick = { selector = "importe" })
                }
                is AmountColumns.Split -> {
                    Spacer(Modifier.height(16.dp))
                    FilledField("Cargos (gastos)", columna(a.debit), trailing = StmIcons.arrowDropDown, onClick = { selector = "cargos" })
                    Spacer(Modifier.height(16.dp))
                    FilledField("Abonos (ingresos)", columna(a.credit), trailing = StmIcons.arrowDropDown, onClick = { selector = "abonos" })
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        FilledField("Cuenta de destino", finance.account(cuenta)?.name ?: "Elige una cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
        if (validas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader("Vista previa")
                validas.take(10).forEachIndexed { i, d ->
                    if (i > 0) Divider(inset = 16.dp)
                    ListItem(d.description, Fechas.numerica(d.bookedOn), trailingText = Money.format(d.amountMinor, signed = true))
                }
                if (validas.size > 10) ListItem("… y ${validas.size - 10} más")
            }
        }
        if (problemas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader("Filas que no se importarán (${problemas.size})")
                problemas.take(10).forEach { ListItem("Fila ${it.line}: ${it.issue}", supportingColor = c.error) }
            }
        }
        if (m != null) {
            Spacer(Modifier.height(16.dp))
            FilledField("Formato de fecha", m.dateOrder.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "formato" })
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListItem(
                    "Cargos y abonos en columnas separadas",
                    trailing = {
                        StmSwitch(m.amount is AmountColumns.Split) { separadas ->
                            mapeo = when (val a = m.amount) {
                                is AmountColumns.Signed -> if (separadas) m.copy(amount = AmountColumns.Split(a.column, a.column)) else m
                                is AmountColumns.Split -> if (!separadas) m.copy(amount = AmountColumns.Signed(a.debit)) else m
                            }
                        }
                    },
                )
            }
        }
    }
}

/** Lee el archivo en el dispositivo. Devuelve el texto y el nombre, o el motivo en español. */
private fun leerCsv(context: Context, uri: Uri): Result<Pair<String, String>> = try {
    var archivo = "archivo.csv"
    var bytes = -1L
    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val n = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val s = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (n >= 0 && !cursor.isNull(n)) archivo = cursor.getString(n)
            if (s >= 0 && !cursor.isNull(s)) bytes = cursor.getLong(s)
        }
    }
    if (bytes > MAX_CSV_BYTES) {
        Result.failure(AppError.InvalidInput("El archivo es demasiado grande (máximo 10 MB)."))
    } else {
        val data = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        if (data == null) Result.failure(AppError.InvalidInput("No he podido abrir el archivo."))
        else Result.success(CsvTable.decode(data) to archivo)
    }
} catch (_: IOException) {
    Result.failure(AppError.InvalidInput("No he podido abrir el archivo."))
} catch (_: SecurityException) {
    Result.failure(AppError.InvalidInput("No he podido abrir el archivo."))
}

private const val MAX_CSV_BYTES = 10L * 1024 * 1024
private const val CSV_MUESTRA = "Fecha;Concepto;Cuenta;Importe\n03/10/2026;Supermercado Día;;-64,20\n01/10/2026;Nómina;;2150,00\n"

/** 33 Borrar datos: diálogo de confirmación sobre Más opciones. */
@Composable
fun Pantalla33(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance
    // Vacío de verdad: solo la captura del diseño lo trae escrito.
    var confirm by remember { mutableStateOf(if (session.capture) "borrar" else "") }
    val action = rememberAction()
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = {
            StmDialog(
                "¿Borrar todos los datos?",
                "Se borrarán las cuentas, movimientos, presupuestos, metas, tarjetas e inversiones del hogar. Esta acción no se puede deshacer.",
                icon = StmIcons.deleteForever,
                onDismiss = nav::back,
                actions = {
                    Btn("Cancelar", nav::back, kind = BtnKind.Text)
                    Btn(
                        "Borrar",
                        {
                            action.run {
                                finance?.resetHousehold()
                                nav.reset(4)
                            }
                        },
                        kind = BtnKind.Error, enabled = confirm.trim().lowercase() == "borrar" && !action.busy,
                    )
                },
            ) {
                Spacer(Modifier.height(16.dp))
                OutlinedField("Escribe «borrar» para confirmar", confirm, { confirm = it }, labelBackground = c.surfaceContainerHigh, autoFocus = true)
            }
        },
    ) {
        ListCard {
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false, onClick = null)
        }
    }
}

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

/** Cabecera de Más opciones: barra vacía de 64 y título grande (152 dp en total). */
@Composable
private fun MasHeader() {
    Spacer(Modifier.height(88.dp))
    Text("Más opciones", Modifier.padding(start = 16.dp), style = StmType.headlineLarge, color = Stm.colors.onSurface)
    Spacer(Modifier.height(24.dp))
}

/** Barra superior mediana (112 dp): fila de 60 con atrás y acciones, y título de 28 debajo. */
@Composable
private fun MediumTopBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconBtn(StmIcons.arrowBack, onBack, contentDescription = "Atrás")
        Spacer(Modifier.weight(1f))
        actions()
    }
    Text(title, Modifier.padding(start = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = Stm.colors.onSurface)
}

/**
 * Botón segmentado que se ajusta al texto: 12 dp a cada lado, mínimo 48 y 4 dp más en los extremos
 * redondeados (el compartido reparte el ancho a partes iguales).
 */
@Composable
private fun HugSegmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            val outer = if (i == 0 || i == options.lastIndex) 4.dp else 0.dp
            Row(
                Modifier.fillMaxHeight().let { if (on) it.background(c.secondaryContainer) else it }
                    .drawBehind { if (i > 0) drawRect(c.outline, Offset.Zero, Size(1.dp.toPx(), size.height)) }
                    .tap(role = Role.RadioButton) { onSelect(i) }
                    .padding(start = if (i == 0) outer else 0.dp, end = if (i == options.lastIndex) outer else 0.dp)
                    .widthIn(min = 48.dp - outer).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (on) {
                    StmIcon(StmIcons.check, c.onSecondaryContainer, size = 18.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(label, style = StmType.labelLarge, color = if (on) c.onSecondaryContainer else c.onSurface, maxLines = 1)
            }
        }
    }
}

/** Elemento de leyenda: punto de 8 y texto. */
@Composable
private fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

/** Dato de la posición: etiqueta a la izquierda y valor a la derecha. */
@Composable
private fun DataRow(label: String, value: String, valueColor: Color = Stm.colors.onSurface) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        Text(value, style = StmType.labelLarge, color = valueColor)
    }
}

/** Campo con borde y sufijo de unidad (€, %); etiqueta sobre el borde en el color de la tarjeta. */
@Composable
private fun SuffixField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, modifier: Modifier) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(4.dp)
    Box(modifier.height(56.dp)) {
        Row(
            Modifier.fillMaxSize().border(if (focused) 2.dp else 1.dp, if (focused) c.primary else c.outline, shape)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value, onValueChange, Modifier.weight(1f).onFocusChanged { focused = it.isFocused }, singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            Spacer(Modifier.width(12.dp))
            Text(suffix, style = StmType.bodyLarge, color = c.onSurfaceVariant)
        }
        Text(
            label, style = StmType.bodySmall, color = if (focused) c.primary else c.onSurfaceVariant,
            modifier = Modifier.offset(12.dp, (-8).dp).background(c.surfaceContainerLowest).padding(horizontal = 4.dp),
        )
    }
}

/** Fila del menú de Más: icono de 24, texto, contador opcional y chevron. */
@Composable
private fun MenuRow(icon: ImageVector, label: String, count: String? = null, chevron: Boolean = true, onClick: (() -> Unit)?) {
    val c = Stm.colors
    ListItem(
        label,
        leading = { StmIcon(icon, c.onSurfaceVariant) },
        trailing = if (!chevron) null else {
            {
                Row {
                    if (count != null) {
                        Text(count, style = StmType.bodyMedium, color = c.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                    }
                    StmIcon(StmIcons.chevronRight, c.onSurfaceVariant)
                }
            }
        },
        onClick = onClick,
    )
}

/** Categoría: icono en círculo, nombre y asa para arrastrar. */
@Composable
private fun CategoryRow(
    icon: ImageVector,
    label: String,
    container: Color = Stm.colors.secondaryContainer,
    tint: Color = Stm.colors.onSecondaryContainer,
    onClick: () -> Unit,
) {
    ListItem(
        label,
        onClick = onClick,
        leading = { LeadIcon(icon, container, tint) },
        trailing = { StmIcon(StmIcons.dragIndicator, Stm.colors.onSurfaceVariant, contentDescription = "Reordenar") },
    )
}

private fun CsvTable?.orEmptyRows(): List<List<String>> = this?.rows ?: emptyList()
