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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
import com.savethemoney.android.ui.titulo
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
    val resources = LocalResources.current
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
    fun letra(i: Int) = resources.getString(R.string.importar_csv_columna, if (i < 26) ('A' + i).toString() else (i + 1).toString())
    fun columna(i: Int) = letra(i) + (cabeceras.getOrNull(i)?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: "")

    StmScreen(
        topBar = { TopBar(stringResource(R.string.importar_csv_importar_csv), navIcon = StmIcons.close, onNav = nav::back) },
        // En una snackbar: la vista previa puede ocupar más que la pantalla.
        snackbar = (action.error ?: resultado?.let { r ->
            stringResource(R.string.importar_csv_movimientos_importados, r.inserted) + (creados?.let { pluralStringResource(R.plurals.importar_csv_pagos_recurrentes_creados, it, it) } ?: "") + if (r.duplicates > 0) stringResource(R.string.importar_csv_ya_estaban_y_no_se_han, r.duplicates) else ""
        })?.let { texto -> { Snackbar(texto) } },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn(
                    when {
                        action.busy -> stringResource(R.string.importar_csv_importando)
                        validas.isEmpty() -> stringResource(R.string.importar_csv_importar)
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
                    FilaInterruptor(stringResource(R.string.importar_csv_importar_esta_fila), null, fila.line !in revision.skipped) { si ->
                        revision = revision.copy(skipped = if (si) revision.skipped - fila.line else revision.skipped + fila.line)
                    }
                    FilaInterruptor(stringResource(R.string.acciones_movimiento_excluir_del_presupuesto), null, fila.line in revision.excluded) { si ->
                        revision = revision.copy(excluded = if (si) revision.excluded + fila.line else revision.excluded - fila.line)
                    }
                    SheetItem(StmIcons.category, stringResource(R.string.importar_csv_categoria, finance.category(d.categoryId)?.name ?: stringResource(R.string.comun_sin_categoria))) {
                        filaCategoria = fila
                        cerrar()
                    }
                    if (d.amountMinor < 0) {
                        Divider(inset = 16.dp)
                        SheetItem(StmIcons.close, stringResource(ImportMark.None.titulo)) { marcar(ImportMark.None) }
                        SheetItem(StmIcons.eventRepeat, stringResource(ImportMark.Recurring.titulo)) { marcar(ImportMark.Recurring) }
                        SheetItem(StmIcons.subscriptions, stringResource(ImportMark.Subscription.titulo)) { marcar(ImportMark.Subscription) }
                        if (tarjetas.isNotEmpty()) SheetItem(StmIcons.creditCard, stringResource(ImportMark.Card.titulo)) { marcar(ImportMark.Card) }
                    }
                }
            }
        } ?: filaCategoria?.let { fila ->
            {
                val tipo = if (fila.draft!!.amountMinor < 0) CategoryKind.Expense else CategoryKind.Income
                fun pon(id: String?) { revision = revision.copy(categories = revision.categories + (fila.line to id)) }
                SelectorSheet(
                    stringResource(R.string.comun_categoria),
                    listOf<Pair<String, () -> Unit>>(stringResource(R.string.comun_sin_categoria) to { pon(null) }) +
                        (finance.categories(tipo) + finance.categories(CategoryKind.Transfer)).map { cat -> cat.name to { pon(cat.id) } },
                ) { filaCategoria = null }
            }
        } ?: selector?.let { campo ->
            {
                val cerrar = { selector = null }
                val columnas = { fijar: (Int) -> Unit -> (0 until anchura).map { i -> columna(i) to { fijar(i) } } }
                when (campo) {
                    "separador" -> SelectorSheet(stringResource(R.string.importar_csv_separador), SEPARADORES.map { s -> etiquetaSeparador(s) to { cambiarSeparador(s) } }, cerrar)
                    "fecha" -> SelectorSheet(stringResource(R.string.comun_fecha), columnas { i -> mapeo = mapeo?.copy(date = i) }, cerrar)
                    "concepto" -> SelectorSheet(stringResource(R.string.comun_concepto), columnas { i -> mapeo = mapeo?.copy(description = i) }, cerrar)
                    "importe" -> SelectorSheet(stringResource(R.string.comun_importe), columnas { i -> mapeo = mapeo?.copy(amount = AmountColumns.Signed(i)) }, cerrar)
                    "cargos" -> SelectorSheet(stringResource(R.string.importar_csv_cargos_gastos), columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split(i, (it.amount as? AmountColumns.Split)?.credit ?: i)) }
                    }, cerrar)
                    "abonos" -> SelectorSheet(stringResource(R.string.importar_csv_abonos_ingresos), columnas { i ->
                        mapeo = mapeo?.let { it.copy(amount = AmountColumns.Split((it.amount as? AmountColumns.Split)?.debit ?: i, i)) }
                    }, cerrar)
                    "tarjeta" -> SelectorSheet(stringResource(R.string.importar_csv_tarjeta_de_las_compras), tarjetas.map { a -> a.name to { tarjeta = a.id } }, cerrar)
                    "formato" -> SelectorSheet(stringResource(R.string.importar_csv_formato_de_fecha), DateOrder.entries.map { o -> stringResource(o.titulo) to { mapeo = mapeo?.copy(dateOrder = o) } }, cerrar)
                    else -> SelectorSheet(stringResource(R.string.form_movimiento_cuenta_de_destino), finance.activeAccounts.map { a -> a.name to { cuenta = a.id; resultado = null } }, cerrar)
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
                Text(nombre ?: stringResource(R.string.importar_csv_elegir_archivo_csv), style = StmType.titleMedium, color = c.onSurface, maxLines = 1)
                Text(
                    t?.let { stringResource(R.string.importar_csv_filas_separador, it.rows.size - (m?.firstDataRow ?: 0), if (it.delimiter == '\t') stringResource(R.string.importar_csv_tabulador) else it.delimiter.toString()) }
                        ?: stringResource(R.string.importar_csv_el_archivo_no_se_sube_solo),
                    style = StmType.bodySmall, color = c.onSurfaceVariant, maxLines = 1,
                )
            }
            if (nombre != null) IconBtn(StmIcons.close, {
                nombre = null
                textoCsv = null
                tabla = null
                mapeo = null
                resultado = null
            }, contentDescription = stringResource(R.string.importar_csv_quitar_archivo))
        }
        aviso?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
        if (t != null) {
            Spacer(Modifier.height(16.dp))
            FilledField(stringResource(R.string.importar_csv_separador), etiquetaSeparador(t.delimiter), trailing = StmIcons.arrowDropDown, onClick = { selector = "separador" })
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.importar_csv_si_las_columnas_salen_mal_prueba), style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        if (t != null && m == null) {
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.importar_csv_no_he_reconocido_las_columnas_de), style = StmType.bodySmall, color = c.error)
        }
        if (finance.activeAccounts.isEmpty()) {
            Spacer(Modifier.height(12.dp))
            Btn(stringResource(R.string.importar_csv_crear_una_cuenta), { nav.go(Route.FormCuenta()) }, kind = BtnKind.Tonal, icon = StmIcons.add)
        }
        if (m != null) {
            if (formatoGuardado) {
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.importar_csv_columnas_como_la_ultima_vez_con), style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.importar_csv_que_columna_es_cada_dato), style = StmType.titleSmall, color = c.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))
            FilledField(stringResource(R.string.comun_fecha), "${letra(m.date)} · ${stringResource(m.dateOrder.titulo).lowercase()}", trailing = StmIcons.arrowDropDown, onClick = { selector = "fecha" })
            Spacer(Modifier.height(16.dp))
            FilledField(stringResource(R.string.comun_concepto), columna(m.description), trailing = StmIcons.arrowDropDown, onClick = { selector = "concepto" })
            when (val a = m.amount) {
                is AmountColumns.Signed -> {
                    Spacer(Modifier.height(16.dp))
                    val coma = t.orEmptyRows().drop(m.firstDataRow).take(20).any { ',' in it.getOrElse(a.column) { "" } }
                    FilledField(stringResource(R.string.comun_importe), letra(a.column).let { if (coma) stringResource(R.string.importar_csv_coma_decimal, it) else it }, trailing = StmIcons.arrowDropDown, onClick = { selector = "importe" })
                }
                is AmountColumns.Split -> {
                    Spacer(Modifier.height(16.dp))
                    FilledField(stringResource(R.string.importar_csv_cargos_gastos), columna(a.debit), trailing = StmIcons.arrowDropDown, onClick = { selector = "cargos" })
                    Spacer(Modifier.height(16.dp))
                    FilledField(stringResource(R.string.importar_csv_abonos_ingresos), columna(a.credit), trailing = StmIcons.arrowDropDown, onClick = { selector = "abonos" })
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        FilledField(stringResource(R.string.form_movimiento_cuenta_de_destino), finance.account(cuenta)?.name ?: stringResource(R.string.comun_elige_una_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
        if (validas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                Row(Modifier.fillMaxWidth().padding(end = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { ListHeader(stringResource(R.string.importar_csv_revisa_fila_a_fila)) }
                    if (revision.skipped.isNotEmpty()) {
                        Text(stringResource(R.string.importar_csv_sin_importar, revision.skipped.size), Modifier.padding(top = 8.dp), style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
                (if (verTodas) previas else previas.take(10)).forEachIndexed { i, fila ->
                    val d = revision.apply(fila.draft!!, fila.line)
                    if (i > 0) Divider(inset = 16.dp)
                    val marca = marcas[fila.line]?.takeIf { it != ImportMark.None }
                    val fuera = fila.line in revision.skipped
                    val detalle = if (fuera) stringResource(R.string.importar_csv_no_se_importara, Fechas.numerica(d.bookedOn)) else listOfNotNull(
                        Fechas.numerica(d.bookedOn),
                        finance.category(d.categoryId)?.name,
                        if (d.excluded) stringResource(R.string.importar_csv_excluido) else null,
                        when (marca) {
                            ImportMark.Recurring -> stringResource(R.string.importar_csv_recurrente_cada_mes)
                            ImportMark.Subscription -> stringResource(R.string.importar_csv_suscripcion_cada_mes)
                            ImportMark.Card -> stringResource(R.string.importar_csv_compra_con_tarjeta)
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
                if (!verTodas && previas.size > 10) ListItem(stringResource(R.string.importar_csv_y_mas, previas.size - 10), onClick = { verTodas = true })
            }
            if (marcas.values.any { it == ImportMark.Card } && tarjetas.size > 1) {
                Spacer(Modifier.height(16.dp))
                FilledField(stringResource(R.string.importar_csv_tarjeta_de_las_compras), finance.account(tarjeta)?.name ?: stringResource(R.string.importar_csv_elige_una_tarjeta), trailing = StmIcons.arrowDropDown, onClick = { selector = "tarjeta" })
            }
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.importar_csv_toca_una_fila_para_no_importarla), style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        if (problemas.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader(stringResource(R.string.importar_csv_filas_que_no_se_importaran, problemas.size))
                problemas.take(10).forEach { ListItem(stringResource(R.string.importar_csv_fila, it.line, it.issue.orEmpty()), supportingColor = c.error) }
            }
        }
        if (m != null) {
            Spacer(Modifier.height(16.dp))
            FilledField(stringResource(R.string.importar_csv_formato_de_fecha), stringResource(m.dateOrder.titulo), trailing = StmIcons.arrowDropDown, onClick = { selector = "formato" })
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListItem(
                    stringResource(R.string.importar_csv_cargos_y_abonos_en_columnas),
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
        Result.failure(AppError.InvalidInput(context.getString(R.string.importar_csv_el_archivo_es_demasiado_grande)))
    } else {
        val data = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        if (data == null) Result.failure(AppError.InvalidInput(context.getString(R.string.importar_csv_no_he_podido_abrir_el_archivo)))
        else Result.success(CsvTable.decode(data) to archivo)
    }
} catch (_: IOException) {
    Result.failure(AppError.InvalidInput(context.getString(R.string.importar_csv_no_he_podido_abrir_el_archivo)))
} catch (_: SecurityException) {
    Result.failure(AppError.InvalidInput(context.getString(R.string.importar_csv_no_he_podido_abrir_el_archivo)))
}

private const val MAX_CSV_BYTES = 10L * 1024 * 1024

/** Mismos separadores y orden que en iOS (`CSVTable.delimiters`). */
private val SEPARADORES = listOf(';', '\t', ',')

@Composable private fun etiquetaSeparador(c: Char) = when (c) {
    ';' -> stringResource(R.string.importar_csv_punto_y_coma)
    '\t' -> stringResource(R.string.importar_csv_tabulador_2)
    else -> stringResource(R.string.importar_csv_coma)
}

private fun CsvTable?.orEmptyRows(): List<List<String>> = this?.rows ?: emptyList()
