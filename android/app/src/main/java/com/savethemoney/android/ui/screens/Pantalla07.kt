package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CardPurchase
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CategoryLearner
import com.savethemoney.android.data.MerchantDirectory
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.MovementTags
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.data.Payee
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.SimilarMovements
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Calculadora
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.Instant
import kotlin.math.abs

/** 07 Nuevo o editar movimiento: tipo, importe, concepto, categoría, cuenta, fecha y extras. */
@Composable
fun Pantalla07(nav: Nav, route: Route.FormMovimiento) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val movimiento = rememberRow(route.movementId, finance::movement)
    if (route.movementId != null && movimiento == null) return NoEncontrado(nav)
    val form = remember { formularioMovimiento(finance, route, movimiento) }
    val base = remember { form.movement }
    var tipo by rememberSaveable { mutableIntStateOf(if (form.transfer) 2 else if (base?.isExpense == false) 1 else 0) }
    var importe by rememberSaveable { mutableStateOf(base?.let { Money.input(abs(it.amountMinor)) } ?: form.amountMinor?.let(Money::input) ?: "") }
    var concepto by rememberSaveable { mutableStateOf(base?.description ?: form.description) }
    var categoria by rememberSaveable { mutableStateOf(base?.categoryId) }
    var autoCategoria by rememberSaveable { mutableStateOf<String?>(null) }
    var cuenta by rememberSaveable { mutableStateOf(form.accountId ?: base?.accountId ?: finance.defaultAccount?.id) }
    var destino by rememberSaveable { mutableStateOf(form.toAccountId) }
    var fecha by rememberSaveable { mutableStateOf(base?.day ?: finance.today()) }
    var notas by rememberSaveable { mutableStateOf(base?.notes ?: "") }
    var conNotas by rememberSaveable { mutableStateOf(notas.isNotEmpty()) }
    var beneficiario by rememberSaveable { mutableStateOf(base?.payee ?: "") }
    var etiquetas by rememberSaveable { mutableStateOf(MovementTags.text(base?.tags.orEmpty())) }
    var excluido by rememberSaveable { mutableStateOf(base?.excluded ?: false) }
    var revisado by rememberSaveable { mutableStateOf(base?.isReviewed ?: false) }
    // Tras cambiar la categoría: otros con el mismo concepto a los que ofrecer el mismo cambio.
    var parecidos by remember { mutableStateOf(emptyList<Movement>()) }
    var selector by remember { mutableStateOf<String?>(null) }
    var eligeFecha by remember { mutableStateOf(false) }
    // Sólo gasto nuevo en una tarjeta: normal (0), a plazos (1) o recurrente (2).
    var compra by rememberSaveable { mutableIntStateOf(0) }
    var plazos by rememberSaveable { mutableIntStateOf(CardPurchase.DEFAULT_MONTHS) }
    var cadaCompra by remember { mutableStateOf(Recurrence.Monthly) }
    val action = rememberAction()
    // Uno por formulario: si «Guardar» se repite tras un fallo de red, la transferencia no se guarda dos veces.
    val idTransferencia = rememberSaveable { java.util.UUID.randomUUID().toString() }
    // Lo mismo para un movimiento nuevo: el reintento lleva el mismo identificador y no se apunta dos veces.
    val idMovimiento = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val cuentas = finance.activeAccounts.map { it.name to it.id }
    val enTarjeta = form.movement == null && tipo == 0 && finance.account(cuenta)?.kind == AccountKind.CreditCard
    val tipoCategoria = if (tipo == 1) CategoryKind.Income else CategoryKind.Expense
    val elegida = finance.category(categoria)
    val resources = LocalResources.current

    fun guardar() = action.run {
        fun falla(texto: String): Nothing = throw AppError.InvalidInput(texto)
        val valor = Money.entered(importe)?.takeIf { it != 0L }?.let(::abs) ?: falla(resources.getString(R.string.form_movimiento_escribe_un_importe_por_ejemplo_12))
        val origen = cuenta ?: falla(resources.getString(R.string.form_movimiento_elige_una_cuenta))
        val nota = notas.trim().ifEmpty { null }
        val quien = Payee.clean(beneficiario)
        val marcas = MovementTags.normalize(etiquetas)
        if (tipo == 2) {
            val hacia = destino ?: falla(resources.getString(R.string.form_movimiento_elige_la_cuenta_de_destino))
            if (hacia == origen) falla(resources.getString(R.string.form_movimiento_elige_dos_cuentas_distintas))
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
            TopBar(if (form.movement != null) stringResource(R.string.form_movimiento_editar_movimiento) else stringResource(R.string.form_movimiento_nuevo_movimiento), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (parecidos.isNotEmpty()) {
            {
                StmDialog(
                    pluralStringResource(R.plurals.form_movimiento_hay_movimientos_con_el_mismo, parecidos.size, parecidos.size),
                    stringResource(R.string.form_movimiento_cambiar_tambien_su_categoria, elegida?.name ?: stringResource(R.string.comun_sin_categoria)),
                    icon = StmIcons.category,
                    onDismiss = nav::back,
                    actions = {
                        Btn(stringResource(R.string.form_movimiento_solo_este), nav::back, kind = BtnKind.Text)
                        Btn(stringResource(R.string.form_movimiento_ponerles_la_misma_categoria), {
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
                        stringResource(R.string.comun_categoria),
                        listOf<Pair<String, () -> Unit>>(stringResource(R.string.comun_sin_categoria) to { categoria = null }) +
                            (finance.categories(tipoCategoria) + finance.categories(CategoryKind.Transfer)).map { cat -> cat.name to { categoria = cat.id } },
                        cerrar,
                    )
                    "cuenta" -> SelectorSheet(stringResource(R.string.comun_cuenta), cuentas.map { (n, id) -> n to { cuenta = id } }, cerrar)
                    "cadaCompra" -> SelectorSheet(stringResource(R.string.form_movimiento_frecuencia), Recurrence.Common.map { rec -> rec.title to { cadaCompra = rec } }, cerrar)
                    else -> SelectorSheet(stringResource(R.string.form_movimiento_cuenta_de_destino), cuentas.map { (n, id) -> n to { destino = id } }, cerrar)
                }
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(
            if (form.movement != null) listOf(stringResource(R.string.form_movimiento_gasto), stringResource(R.string.form_movimiento_ingreso)) else listOf(stringResource(R.string.form_movimiento_gasto), stringResource(R.string.form_movimiento_ingreso), stringResource(R.string.form_movimiento_transferencia)),
            tipo,
            { nuevo ->
                // En una transferencia la salida es siempre un gasto y la entrada un ingreso.
                if (base?.transferId != null) return@Segmented
                tipo = nuevo
                // Una categoría de ingreso no vale para un gasto; las de transferencia sirven para los dos.
                val kind = elegida?.kind
                if (kind != null && kind != CategoryKind.Transfer && kind != (if (nuevo == 1) CategoryKind.Income else CategoryKind.Expense)) categoria = null
            },
        )
        if (base?.transferId != null) {
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.form_movimiento_nota_transferencia), style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        var enfocado by remember { mutableStateOf(false) }
        Column(
            Modifier.fillMaxWidth().heightIn(min = 116.dp).padding(top = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(stringResource(R.string.comun_importe), style = StmType.labelMedium, color = c.onSurfaceVariant)
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
        FilledField(stringResource(R.string.comun_concepto), concepto, { texto ->
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
            FilledField(stringResource(R.string.form_movimiento_cuenta_de_destino), finance.account(destino)?.name ?: stringResource(R.string.comun_elige_una_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "destino" })
        } else {
            FilledField(stringResource(R.string.comun_categoria), elegida?.name ?: stringResource(R.string.comun_sin_categoria), leading = iconoCategoria(elegida), trailing = StmIcons.arrowDropDown, onClick = { selector = "categoria" })
        }
        Spacer(Modifier.height(16.dp))
        FilledField(stringResource(R.string.comun_cuenta), finance.account(cuenta)?.name ?: stringResource(R.string.comun_elige_una_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
        if (enTarjeta) {
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.form_movimiento_tipo_de_compra), style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Segmented(listOf(stringResource(R.string.form_movimiento_normal), stringResource(R.string.form_movimiento_a_plazos), stringResource(R.string.form_movimiento_recurrente)), compra, { compra = it })
            if (compra == 1) {
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.form_movimiento_plazos), Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                    Stepper(
                        stringResource(R.string.form_movimiento_meses, plazos),
                        { plazos = (plazos - 1).coerceAtLeast(CardPurchase.MONTHS.first) },
                        { plazos = (plazos + 1).coerceAtMost(CardPurchase.MONTHS.last) },
                    )
                }
                Spacer(Modifier.height(8.dp))
                ChipRow(Modifier.fillMaxWidth()) {
                    CardInstallment.commonMonths.forEach { m -> Chip(stringResource(R.string.form_movimiento_meses, m), selected = m == plazos, onClick = { plazos = m }) }
                }
                val principal = Money.entered(importe)?.let(::abs) ?: 0L
                val tin = finance.cards.terms[cuenta]?.installmentRate ?: 14.0
                val cuota = CardPurchase.quote(principal, plazos, tin)
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.form_movimiento_al_mes_total_intereses_tin, Money.format(cuota.monthly), Money.format(cuota.total), Money.format(cuota.interest), tin.toString().removeSuffix(".0").replace('.', ',')),
                    style = StmType.bodyMedium, color = c.onSurface,
                )
                if (principal in 1 until CardPurchase.USUAL_MINIMUM) {
                    Text(stringResource(R.string.form_movimiento_muchos_contratos_solo_aplazan), style = StmType.bodySmall, color = c.error)
                }
            } else if (compra == 2) {
                Spacer(Modifier.height(16.dp))
                FilledField(stringResource(R.string.comun_cada), cadaCompra.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "cadaCompra" })
                Spacer(Modifier.height(4.dp))
                Text(
                    stringResource(R.string.form_movimiento_se_crea_un_pago_fijo_con),
                    style = StmType.bodySmall, color = c.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        FilledField(stringResource(R.string.comun_fecha), Fechas.largo(fecha, finance.today()), trailing = StmIcons.calendarToday, onClick = { eligeFecha = true })
        Spacer(Modifier.height(16.dp))
        FilledField(stringResource(R.string.form_movimiento_beneficiario_opcional), beneficiario, { beneficiario = it })
        val propuestos = if (beneficiario.isBlank()) emptyList() else finance.knownPayees
            .filter { it.contains(beneficiario.trim(), ignoreCase = true) && !it.equals(beneficiario.trim(), ignoreCase = true) }.take(4)
        if (propuestos.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            ChipRow(Modifier.fillMaxWidth()) { propuestos.forEach { p -> Chip(p, onClick = { beneficiario = p }, icon = StmIcons.person) } }
        }
        Spacer(Modifier.height(16.dp))
        FilledField(
            stringResource(R.string.form_movimiento_etiquetas_p_ej_viaje_regalos), etiquetas, { etiquetas = it },
            supporting = stringResource(R.string.form_movimiento_las_etiquetas_sirven_para_juntar),
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
            FilledField(stringResource(R.string.form_movimiento_notas), notas, { notas = it })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            if (form.movement != null) {
                FilaInterruptor(stringResource(R.string.form_movimiento_revisado), null, revisado) { revisado = it }
                Divider(inset = 16.dp)
            }
            FilaInterruptor(
                stringResource(R.string.form_movimiento_excluir_del_presupuesto_e_informes),
                stringResource(R.string.form_movimiento_un_movimiento_excluido_sigue),
                excluido,
            ) { excluido = it }
        }
    }
    if (eligeFecha) SelectorFecha(fecha, { fecha = it }) { eligeFecha = false }
}
