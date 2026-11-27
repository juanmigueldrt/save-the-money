package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.AssetClass
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo
import java.math.BigDecimal
import java.time.Instant

/** Crear o editar un activo. No está en el diseño: sigue el molde de los otros formularios y el de iOS. */
@Composable
fun Pantalla39(nav: Nav, holdingId: String?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val editando = rememberRow(holdingId, inv::holding)
    if (holdingId != null && editando == null) return NoEncontrado(nav)
    var nombre by rememberSaveable { mutableStateOf(editando?.name.orEmpty()) }
    var simbolo by rememberSaveable { mutableStateOf(editando?.symbol.orEmpty()) }
    var tipo by rememberSaveable { mutableStateOf(editando?.kind ?: InvestmentKind.Fund) }
    var clase by rememberSaveable { mutableStateOf(editando?.assetClass ?: AssetClass.Equity) }
    var dueno by rememberSaveable { mutableStateOf(editando?.ownerId) }
    var cuenta by rememberSaveable { mutableStateOf(editando?.accountId) }
    var precio by rememberSaveable { mutableStateOf(editando?.price?.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var comision by rememberSaveable { mutableStateOf(editando?.feeRate?.takeIf { it.signum() > 0 }?.let(InvestmentText::plain).orEmpty()) }
    var nota by rememberSaveable { mutableStateOf(editando?.note.orEmpty()) }
    var selector by remember { mutableStateOf<String?>(null) }
    var borrando by remember { mutableStateOf(false) }
    // Identificador del activo nuevo, uno por formulario: reintentar el alta con el mismo no crea otro.
    val idActivo = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val action = rememberAction()
    val resources = LocalResources.current

    fun guardar() = action.run {
        val valor = if (precio.isBlank()) BigDecimal.ZERO else parseDecimal(precio, maxFractionDigits = 6) ?: throw AppError.InvalidInput(resources.getString(R.string.form_activo_escribe_el_precio_con_coma_para))
        val tasa = if (comision.isBlank()) BigDecimal.ZERO else parseDecimal(comision, maxFractionDigits = 3) ?: throw AppError.InvalidInput(resources.getString(R.string.form_activo_escribe_la_comision_con_numeros_p))
        val hoy = finance.today()
        val cambiaPrecio = editando?.let { it.price.compareTo(valor) != 0 } ?: (valor.signum() > 0)
        val base = editando ?: Holding(
            idActivo, inv.householdId, nombre, price = valor, priceOn = if (valor.signum() > 0) hoy.toString() else null,
        )
        val item = base.copy(
            name = nombre, symbol = simbolo, kind = tipo, assetClass = clase, ownerId = dueno, accountId = cuenta, feeRate = tasa,
            note = nota.trim().ifEmpty { null },
        )
        item.issue?.let { throw AppError.InvalidInput(it) }
        // Un precio nuevo también queda en el histórico, para el gráfico: va en la misma escritura que el activo.
        inv.save(item, price = valor.takeIf { cambiaPrecio && it.signum() > 0 }, priceDay = hoy)
        nav.back()
    }

    StmScreen(
        topBar = {
            TopBar(if (editando == null) stringResource(R.string.form_activo_nuevo_activo) else stringResource(R.string.form_activo_editar_activo), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            borrando -> {
                {
                    BottomSheet(
                        stringResource(R.string.form_activo_borrar_este_activo), stringResource(R.string.form_activo_se_borran_tambien_sus_precios),
                        onDismiss = { borrando = false },
                    ) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn(stringResource(R.string.comun_cancelar), { borrando = false }, kind = BtnKind.Text)
                            Btn(stringResource(R.string.form_activo_borrar_activo), {
                                action.run {
                                    inv.delete(editando!!)
                                    nav.back()
                                    nav.back()
                                }
                            }, kind = BtnKind.Error)
                        }
                    }
                }
            }
            selector != null -> {
                {
                    val cerrar = { selector = null }
                    when (selector) {
                        "tipo" -> SelectorSheet(stringResource(R.string.form_activo_tipo), InvestmentKind.entries.map { k ->
                            stringResource(k.titulo) to {
                                tipo = k
                                if (editando == null) clase = k.defaultAssetClass
                            }
                        }, cerrar)
                        "clase" -> SelectorSheet(stringResource(R.string.form_activo_clase), AssetClass.entries.map { a -> stringResource(a.titulo) to { clase = a } }, cerrar)
                        "dueno" -> SelectorSheet(stringResource(R.string.form_activo_de_quien_es), listOf<Pair<String, () -> Unit>>(stringResource(R.string.inversiones_compartido) to { dueno = null }) + inv.members.map { m -> m.profile.name to { dueno = m.profile.id } }, cerrar)
                        else -> SelectorSheet(stringResource(R.string.form_activo_donde_esta), listOf<Pair<String, () -> Unit>>(stringResource(R.string.form_activo_ninguna_cuenta) to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField(stringResource(R.string.comun_nombre), nombre, { nombre = it }, autoFocus = editando == null)
            FilledField(stringResource(R.string.form_activo_ticker_o_isin_opcional), simbolo, { simbolo = it })
            FilledField(stringResource(R.string.form_activo_tipo), stringResource(tipo.titulo), trailing = StmIcons.arrowDropDown, onClick = { selector = "tipo" })
            FilledField(stringResource(R.string.form_activo_clase), stringResource(clase.titulo), trailing = StmIcons.arrowDropDown, onClick = { selector = "clase" })
            FilledField(stringResource(R.string.form_activo_precio_actual_por_participacion), precio, { precio = it }, keyboard = KeyboardType.Decimal)
            FilledField(stringResource(R.string.form_activo_comision_de_compra_en), comision, { comision = it }, keyboard = KeyboardType.Decimal)
            Text(stringResource(R.string.form_activo_el_precio_lo_apuntas_tu_buscalo), style = StmType.bodySmall, color = c.onSurfaceVariant)
            FilledField(stringResource(R.string.form_activo_de_quien_es), nombreDueno(inv, dueno), trailing = StmIcons.arrowDropDown, onClick = { selector = "dueno" })
            FilledField(stringResource(R.string.form_activo_donde_esta), finance.account(cuenta)?.name ?: stringResource(R.string.form_activo_ninguna_cuenta), trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField(stringResource(R.string.comun_nota_opcional), nota, { nota = it })
            Text(stringResource(R.string.form_activo_todo_el_hogar_ve_las_inversiones), style = StmType.bodySmall, color = c.onSurfaceVariant)
            if (editando != null) {
                Btn(if (editando.isArchived) stringResource(R.string.comun_desarchivar) else stringResource(R.string.comun_archivar), {
                    action.run {
                        inv.save(editando.copy(archivedAt = if (editando.isArchived) null else Instant.now().toString()))
                        nav.back()
                    }
                }, Modifier.fillMaxWidth(), kind = BtnKind.Outlined)
                Btn(stringResource(R.string.form_activo_borrar_activo_y_sus_operaciones), { borrando = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
            }
        }
    }
}
