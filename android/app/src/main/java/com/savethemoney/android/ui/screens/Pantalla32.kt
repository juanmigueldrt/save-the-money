package com.savethemoney.android.ui.screens

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AmountColumns
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CategoryLearner
import com.savethemoney.android.data.CsvImportRow
import com.savethemoney.android.data.CsvImporter
import com.savethemoney.android.data.CsvMapping
import com.savethemoney.android.data.CsvRowReview
import com.savethemoney.android.data.CsvSavedFormat
import com.savethemoney.android.data.CsvTable
import com.savethemoney.android.data.DateOrder
import com.savethemoney.android.data.ImportMark
import com.savethemoney.android.data.ImportMarks
import com.savethemoney.android.data.ImportResult
import com.savethemoney.android.data.MerchantDirectory
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.IOException

/** 32 Importar CSV: archivo elegido, columnas, vista previa e importación. El archivo no sale del móvil. */
@Composable
fun Pantalla32(nav: Nav, accountId: String?) {
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
    var cuenta by remember { mutableStateOf(accountId ?: finance.defaultAccount?.id) }
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
    // Id de cada pago fijo que crea la importación, por su nombre: el mismo en cada reintento (ImportMarks.pinned).
    val idsSeries = remember { mutableMapOf<String, String>() }
    val tarjetas = finance.cards.cardAccounts
    var tarjeta by remember { mutableStateOf(tarjetas.firstOrNull()?.id) }
    val action = rememberAction()

    fun cargar(texto: String, archivo: String) {
        val guardado = CsvSavedFormat.match(texto, FormatosCsv.load(context))
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
                        else -> tituloImportar(validas.size)
                    },
                    {
                        action.run {
                            aviso = null
                            creados = null
                            resultado = finance.importMovements(ImportMarks.drafts(revisadas, marcas, tarjeta))
                            if (t != null && m != null) FormatosCsv.remember(context, CsvSavedFormat.of(t, m, cuenta))
                            val fijos = ImportMark.Recurring in marcas.values || ImportMark.Subscription in marcas.values
                            if (fijos) {
                                val nuevos = ImportMarks.series(revisadas, marcas, finance.planning.series, finance.planning.household.id)
                                finance.planning.save(ImportMarks.pinned(nuevos, idsSeries))
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
            Btn("Crear una cuenta", { nav.go(Route.FormCuenta()) }, kind = BtnKind.Tonal, icon = StmIcons.add)
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
            Spacer(Modifier.height(8.dp))
            Text("Toca una fila para no importarla, cambiar su categoría o excluirla del presupuesto. En un gasto también puedes marcarlo como recurrente o suscripción (se crea un pago mensual desde esa fecha, que puedes ajustar en Pagos fijos) o como compra con tarjeta de crédito (se apunta en la tarjeta).", style = StmType.bodySmall, color = c.onSurfaceVariant)
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

private fun CsvTable?.orEmptyRows(): List<List<String>> = this?.rows ?: emptyList()
