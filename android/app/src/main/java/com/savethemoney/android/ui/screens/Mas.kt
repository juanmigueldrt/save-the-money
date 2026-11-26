package com.savethemoney.android.ui.screens

import com.savethemoney.android.ui.Vista
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
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.AmountColumns
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CsvImportRow
import com.savethemoney.android.data.CategoryLearner
import com.savethemoney.android.data.CsvImporter
import com.savethemoney.android.data.MerchantDirectory
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.data.ImportMark
import com.savethemoney.android.data.ImportMarks
import androidx.compose.foundation.isSystemInDarkTheme
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.CsvMapping
import com.savethemoney.android.data.MovementsCsv
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.data.CsvTable
import com.savethemoney.android.data.CsvRowReview
import com.savethemoney.android.data.CsvSavedFormat
import kotlinx.serialization.json.Json
import com.savethemoney.android.data.DateOrder
import com.savethemoney.android.data.ImportResult
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalNotifier
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
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.BottomSheet
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
internal fun Diseno25(nav: Nav) {
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
internal fun Diseno26(nav: Nav) {
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
internal fun Diseno27(nav: Nav) {
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
    var limites by remember(finance) { mutableStateOf(finance?.planning?.budgetAlertsEnabled ?: true) }
    var habitos by remember(finance) { mutableStateOf(finance?.planning?.habits ?: HabitSettings()) }
    var eligeHabito by remember { mutableStateOf(false) }
    val cambiaHabitos = { nuevos: HabitSettings ->
        habitos = nuevos
        finance?.planning?.habits = nuevos
    }
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
        } else if (eligeHabito) {
            {
                SelectorSheet(
                    "Recordarme apuntar gastos",
                    HabitSettings.LogReminder.entries.map { r -> r.title to { cambiaHabitos(habitos.copy(logReminder = r)) } },
                    { eligeHabito = false },
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
            // Dos interruptores, como en iOS y Mac.
            ListItem(
                "Avisos de pagos fijos", "Antes de cada cargo",
                leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(alerts) {
                        alerts = it
                        finance?.planning?.alertsEnabled = it
                        finance?.cards?.reschedule()
                        finance?.investments?.reschedule()
                    }
                },
            )
            ListItem(
                "Avisos de límites del presupuesto", "Al llegar al 80 % o pasarse",
                leading = { StmIcon(StmIcons.donutLarge, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(limites) {
                        limites = it
                        finance?.planning?.budgetAlertsEnabled = it
                    }
                },
            )
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false) { nav.go(33) }
        }
        // Sin permiso, Android descarta los avisos sin decir nada: que se vea aquí.
        if (!session.capture && !LocalNotifier(context).canShow) {
            Text(
                "Android no deja mostrar notificaciones de Save the Money: los avisos no se verán hasta que las actives en Ajustes.",
                Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.error,
            )
        }
        // Fase D, como en iOS: recordatorio para apuntar gastos y resumen semanal. Sólo en este dispositivo.
        if (!session.capture && finance != null) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader("Recordatorios")
                ListItem(
                    "Recordarme apuntar gastos", habitos.logReminder.title,
                    leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                    trailing = { StmIcon(StmIcons.arrowDropDown, Stm.colors.onSurfaceVariant) },
                    onClick = { eligeHabito = true },
                )
                if (habitos.logReminder != HabitSettings.LogReminder.Off) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Hora", Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
                        Stepper(
                            "A las ${habitos.logHour}:00",
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour - 1).coerceAtLeast(6))) },
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour + 1).coerceAtMost(23))) },
                        )
                    }
                }
                ListItem(
                    "Resumen semanal los lunes", "A las 9:00, con la semana anterior",
                    leading = { StmIcon(StmIcons.calendarMonth, Stm.colors.onSurfaceVariant) },
                    trailing = { StmSwitch(habitos.weeklySummary) { cambiaHabitos(habitos.copy(weeklySummary = it)) } },
                )
            }
        }
        // No está en el diseño; va al final para no mover lo anterior. Sólo en este dispositivo.
        if (!session.capture) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader("Vista")
                InterruptorVista(StmIcons.visibilityOff, "Modo incógnito", "Oculta los importes; también con el ojo del Resumen", Vista.incognito, Vista::setIncognito)
                InterruptorVista(StmIcons.savings, "Sin céntimos", "1.235 € en vez de 1.234,56 €", Vista.sinCentimos, Vista::setSinCentimos)
                InterruptorVista(StmIcons.add, "Mostrar + en los ingresos", "+1.200,00 €", Vista.signoMas, Vista::setSignoMas)
                InterruptorVista(StmIcons.trendingUp, "Ingresos en verde", "En las listas de movimientos", Vista.ingresosEnVerde, Vista::setIngresosEnVerde)
            }
            Text(
                "Sólo en este dispositivo. Los PDF y CSV llevan siempre los importes completos.",
                Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            MenuRow(StmIcons.logout, "Cerrar sesión", chevron = false) { action.run { session.signOut() } }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun InterruptorVista(icon: androidx.compose.ui.graphics.vector.ImageVector, titulo: String, detalle: String, activo: Boolean, cambia: (Boolean) -> Unit) {
    ListItem(
        titulo, detalle,
        leading = { StmIcon(icon, Stm.colors.onSurfaceVariant) },
        trailing = { StmSwitch(activo, cambia) },
        onClick = { cambia(!activo) },
    )
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
    // Texto del archivo, para volver a leerlo si el usuario cambia el separador.
    var textoCsv by remember { mutableStateOf<String?>(null) }
    var mapeo by remember { mutableStateOf<CsvMapping?>(null) }
    var cuenta by remember { mutableStateOf(finance.takeCsvAccount() ?: finance.defaultAccount?.id) }
    // Revisión fila a fila (por número de línea): no importar, categoría elegida a mano, excluir.
    var revision by remember { mutableStateOf(CsvRowReview()) }
    var filaCategoria by remember { mutableStateOf<CsvImportRow?>(null) }
    // Las columnas salen de un formato de banco ya usado.
    var formatoGuardado by remember { mutableStateOf(false) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var resultado by remember { mutableStateOf<ImportResult?>(null) }
    var selector by remember { mutableStateOf<String?>(null) }
    // Marcas por número de línea del CSV: siguen valiendo si cambia la cuenta de destino.
    var marcas by remember { mutableStateOf(emptyMap<Int, ImportMark>()) }
    var marcando by remember { mutableStateOf<CsvImportRow?>(null) }
    var verTodas by remember { mutableStateOf(false) }
    var creados by remember { mutableStateOf<Int?>(null) }
    val tarjetas = finance.cards.cardAccounts
    var tarjeta by remember { mutableStateOf(tarjetas.firstOrNull()?.id) }
    val action = rememberAction()

    fun cargar(texto: String, archivo: String) {
        val guardado = if (session.capture) null else CsvSavedFormat.match(texto, FormatosCsv.load(context))
        val formato = guardado?.first
        val t = guardado?.second ?: CsvTable.parse(texto)
        textoCsv = texto
        nombre = archivo
        tabla = t
        val conocido = formato?.mapping
        mapeo = conocido ?: CsvMapping.detect(t)
        formatoGuardado = conocido != null
        formato?.accountId?.takeIf { id -> finance.activeAccounts.any { it.id == id } }?.let { cuenta = it }
        revision = CsvRowReview()
        resultado = null
        aviso = null
        marcas = emptyMap()
        verTodas = false
        creados = null
    }
    // Vuelve a leer el archivo con el separador elegido y detecta las columnas, como en iOS.
    fun cambiarSeparador(separador: Char) {
        val texto = textoCsv ?: return
        if (separador == tabla?.delimiter) return
        val t = CsvTable.parse(texto, separador)
        tabla = t
        mapeo = CsvMapping.detect(t)
        formatoGuardado = false
        revision = CsvRowReview()
        resultado = null
        marcas = emptyMap()
        creados = null
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
        if (t != null && m != null && id != null) {
            MerchantDirectory.categorize(CsvImporter.rows(t, m, id), finance.categories, CategoryLearner(finance.recent))
        } else emptyList()
    }
    LaunchedEffect(filas) { revision = revision.keep(filas.map { it.line }.toSet()) }
    // Las filas con lo decidido al revisarlas: sin las descartadas y con su categoría o «excluido».
    val revisadas = revision.apply(filas)
    val validas = revisadas.mapNotNull { it.draft }
    val previas = filas.filter { it.draft != null }
    val problemas = filas.filter { it.issue != null }
    val anchura = t?.rows?.maxOfOrNull { it.size } ?: 0
    val cabeceras = m?.headerRow?.let { t?.rows?.get(it) } ?: emptyList()
    fun letra(i: Int) = "Columna " + if (i < 26) ('A' + i).toString() else (i + 1).toString()
    fun columna(i: Int) = letra(i) + (cabeceras.getOrNull(i)?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: "")

    StmScreen(
        topBar = { TopBar("Importar CSV", navIcon = StmIcons.close, onNav = nav::back) },
        // En una snackbar: la vista previa puede ocupar más que la pantalla.
        snackbar = (action.error ?: resultado?.let { r ->
            "${r.inserted} movimientos importados." + (creados?.let { if (it == 1) " 1 pago recurrente creado." else " $it pagos recurrentes creados." } ?: "") + if (r.duplicates > 0) " ${r.duplicates} ya estaban y no se han repetido." else ""
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
                            creados = null
                            resultado = finance.importMovements(ImportMarks.drafts(revisadas, marcas, tarjeta))
                            if (t != null && m != null && !session.capture) FormatosCsv.remember(context, CsvSavedFormat.of(t, m, cuenta))
                            val fijos = ImportMark.Recurring in marcas.values || ImportMark.Subscription in marcas.values
                            if (fijos) {
                                val nuevos = ImportMarks.series(revisadas, marcas, finance.planning.series, finance.planning.household.id)
                                nuevos.forEach { finance.planning.save(it) }
                                creados = nuevos.size
                            }
                        }
                    },
                    Modifier.fillMaxWidth(), large = true, enabled = validas.isNotEmpty() && !action.busy,
                )
            }
        },
        overlay = marcando?.let { fila ->
            {
                val cerrar = { marcando = null }
                fun marcar(o: ImportMark) {
                    marcas = marcas + (fila.line to o)
                    cerrar()
                }
                val d = revision.apply(fila.draft!!, fila.line)
                BottomSheet(MovementText.display(d.description), "${Fechas.numerica(d.bookedOn)} · ${Money.format(d.amountMinor, signed = true)}", onDismiss = cerrar) {
                    FilaInterruptor("Importar esta fila", null, fila.line !in revision.skipped) { si ->
                        revision = revision.copy(skipped = if (si) revision.skipped - fila.line else revision.skipped + fila.line)
                    }
                    FilaInterruptor("Excluir del presupuesto", null, fila.line in revision.excluded) { si ->
                        revision = revision.copy(excluded = if (si) revision.excluded + fila.line else revision.excluded - fila.line)
                    }
                    SheetItem(StmIcons.category, "Categoría: " + (finance.category(d.categoryId)?.name ?: "Sin categoría")) {
                        filaCategoria = fila
                        cerrar()
                    }
                    if (d.amountMinor < 0) {
                        Divider(inset = 16.dp)
                        SheetItem(StmIcons.close, ImportMark.None.title) { marcar(ImportMark.None) }
                        SheetItem(StmIcons.eventRepeat, ImportMark.Recurring.title) { marcar(ImportMark.Recurring) }
                        SheetItem(StmIcons.subscriptions, ImportMark.Subscription.title) { marcar(ImportMark.Subscription) }
                        if (tarjetas.isNotEmpty()) SheetItem(StmIcons.creditCard, ImportMark.Card.title) { marcar(ImportMark.Card) }
                    }
                }
            }
        } ?: filaCategoria?.let { fila ->
            {
                val tipo = if (fila.draft!!.amountMinor < 0) CategoryKind.Expense else CategoryKind.Income
                fun pon(id: String?) { revision = revision.copy(categories = revision.categories + (fila.line to id)) }
                SelectorSheet(
                    "Categoría",
                    listOf<Pair<String, () -> Unit>>("Sin categoría" to { pon(null) }) +
                        (finance.categories(tipo) + finance.categories(CategoryKind.Transfer)).map { cat -> cat.name to { pon(cat.id) } },
                ) { filaCategoria = null }
            }
        } ?: selector?.let { campo ->
            {
                val cerrar = { selector = null }
                val columnas = { fijar: (Int) -> Unit -> (0 until anchura).map { i -> columna(i) to { fijar(i) } } }
                when (campo) {
                    "separador" -> SelectorSheet("Separador", SEPARADORES.map { s -> etiquetaSeparador(s) to { cambiarSeparador(s) } }, cerrar)
                    "fecha" -> SelectorSheet("Fecha", columnas { i -> mapeo = mapeo?.copy(date = i) }, cerrar)
                    "concepto" -> SelectorSheet("Concepto", columnas { i -> mapeo = mapeo?.copy(description = i) }, cerrar)
                    "importe" -> SelectorSheet("Importe", columnas { i -> mapeo = mapeo?.copy(amount = AmountColumns.Signed(i)) }, cerrar)
                    "cargos" -> SelectorSheet("Cargos (gastos)", columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split(i, (it.amount as? AmountColumns.Split)?.credit ?: i)) }
                    }, cerrar)
                    "abonos" -> SelectorSheet("Abonos (ingresos)", columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split((it.amount as? AmountColumns.Split)?.debit ?: i, i)) }
                    }, cerrar)
                    "tarjeta" -> SelectorSheet("Tarjeta de las compras", tarjetas.map { a -> a.name to { tarjeta = a.id } }, cerrar)
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
                textoCsv = null
                tabla = null
                mapeo = null
                resultado = null
            }, contentDescription = "Quitar archivo")
        }
        aviso?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
        if (t != null) {
            Spacer(Modifier.height(16.dp))
            FilledField("Separador", etiquetaSeparador(t.delimiter), trailing = StmIcons.arrowDropDown, onClick = { selector = "separador" })
            Spacer(Modifier.height(8.dp))
            Text("Si las columnas salen mal, prueba con otro separador.", style = StmType.bodySmall, color = c.onSurfaceVariant)
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
            if (formatoGuardado) {
                Spacer(Modifier.height(12.dp))
                Text("Columnas como la última vez con este banco.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
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
                Row(Modifier.fillMaxWidth().padding(end = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { ListHeader("Revisa fila a fila") }
                    if (revision.skipped.isNotEmpty()) {
                        Text("${revision.skipped.size} sin importar", Modifier.padding(top = 8.dp), style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
                (if (verTodas) previas else previas.take(10)).forEachIndexed { i, fila ->
                    val d = revision.apply(fila.draft!!, fila.line)
                    if (i > 0) Divider(inset = 16.dp)
                    val marca = marcas[fila.line]?.takeIf { it != ImportMark.None }
                    val fuera = fila.line in revision.skipped
                    val detalle = if (fuera) "${Fechas.numerica(d.bookedOn)} · No se importará" else listOfNotNull(
                        Fechas.numerica(d.bookedOn),
                        finance.category(d.categoryId)?.name,
                        if (d.excluded) "Excluido" else null,
                        when (marca) {
                            ImportMark.Recurring -> "Recurrente, cada mes"
                            ImportMark.Subscription -> "Suscripción, cada mes"
                            ImportMark.Card -> "Compra con tarjeta"
                            else -> null
                        },
                    ).joinToString(" · ")
                    ListItem(
                        MovementText.display(d.description), detalle,
                        trailingText = Money.format(d.amountMinor, signed = true),
                        trailingColor = if (fuera) c.onSurfaceVariant else c.onSurface,
                        onClick = { marcando = fila },
                    )
                }
                if (!verTodas && previas.size > 10) ListItem("… y ${previas.size - 10} más", onClick = { verTodas = true })
            }
            if (marcas.values.any { it == ImportMark.Card } && tarjetas.size > 1) {
                Spacer(Modifier.height(16.dp))
                FilledField("Tarjeta de las compras", finance.account(tarjeta)?.name ?: "Elige una tarjeta", trailing = StmIcons.arrowDropDown, onClick = { selector = "tarjeta" })
            }
            if (!session.capture) {
                Spacer(Modifier.height(8.dp))
                Text("Toca una fila para no importarla, cambiar su categoría o excluirla del presupuesto. En un gasto también puedes marcarlo como recurrente o suscripción (se crea un pago mensual desde esa fecha, que puedes ajustar en Pagos fijos) o como compra con tarjeta de crédito (se apunta en la tarjeta).", style = StmType.bodySmall, color = c.onSurfaceVariant)
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

/** Formatos de banco recordados en este móvil (sólo columnas y cuenta, nunca datos del archivo). */
private object FormatosCsv {
    private const val KEY = "formatos"
    private fun prefs(context: Context) = context.getSharedPreferences("csv", Context.MODE_PRIVATE)

    fun load(context: Context): List<CsvSavedFormat> = try {
        prefs(context).getString(KEY, null)?.let { Json.decodeFromString<List<CsvSavedFormat>>(it) }.orEmpty()
    } catch (_: Exception) {
        emptyList()
    }

    fun remember(context: Context, format: CsvSavedFormat) {
        prefs(context).edit().putString(KEY, Json.encodeToString(CsvSavedFormat.remember(format, load(context)))).apply()
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
/** Mismos separadores y orden que en iOS (`CSVTable.delimiters`). */
private val SEPARADORES = listOf(';', '\t', ',')

private fun etiquetaSeparador(c: Char) = when (c) {
    ';' -> "Punto y coma (;)"
    '\t' -> "Tabulador"
    else -> "Coma (,)"
}

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
                "¿Borrar lo que creaste?",
                "Borra lo que creaste tú: cuentas, tarjetas, movimientos, presupuestos, pagos fijos, metas e inversiones. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo. Esta acción no se puede deshacer.",
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
internal fun MediumTopBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit) {
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
internal fun HugSegmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
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
internal fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

/** Dato de la posición: etiqueta a la izquierda y valor a la derecha. */
@Composable
internal fun DataRow(label: String, value: String, valueColor: Color = Stm.colors.onSurface) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        Text(value, style = StmType.labelLarge, color = valueColor)
    }
}

/** Campo con borde y sufijo de unidad (€, %); etiqueta sobre el borde en el color de la tarjeta. */
@Composable
internal fun SuffixField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, modifier: Modifier) {
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
