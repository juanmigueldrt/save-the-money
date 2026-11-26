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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
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

    fun guardar() = action.run {
        val valor = if (precio.isBlank()) BigDecimal.ZERO else parseDecimal(precio, maxFractionDigits = 6) ?: throw AppError.InvalidInput("Escribe el precio con coma para los decimales, p. ej. 12,50.")
        val tasa = if (comision.isBlank()) BigDecimal.ZERO else parseDecimal(comision, maxFractionDigits = 3) ?: throw AppError.InvalidInput("Escribe la comisión con números, p. ej. 0,2.")
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
            TopBar(if (editando == null) "Nuevo activo" else "Editar activo", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            borrando -> {
                {
                    BottomSheet(
                        "¿Borrar este activo?", "Se borran también sus precios, operaciones y aportaciones automáticas, para todo el hogar. No se puede deshacer.",
                        onDismiss = { borrando = false },
                    ) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                            Btn("Cancelar", { borrando = false }, kind = BtnKind.Text)
                            Btn("Borrar activo", {
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
                        "tipo" -> SelectorSheet("Tipo", InvestmentKind.entries.map { k ->
                            k.title to {
                                tipo = k
                                if (editando == null) clase = k.defaultAssetClass
                            }
                        }, cerrar)
                        "clase" -> SelectorSheet("Clase", AssetClass.entries.map { a -> a.title to { clase = a } }, cerrar)
                        "dueno" -> SelectorSheet("De quién es", listOf<Pair<String, () -> Unit>>("Compartido" to { dueno = null }) + inv.members.map { m -> m.profile.name to { dueno = m.profile.id } }, cerrar)
                        else -> SelectorSheet("Dónde está", listOf<Pair<String, () -> Unit>>("Ninguna cuenta" to { cuenta = null }) + finance.activeAccounts.map { a -> a.name to { cuenta = a.id } }, cerrar)
                    }
                }
            }
            else -> null
        },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FilledField("Nombre", nombre, { nombre = it }, autoFocus = editando == null)
            FilledField("Ticker o ISIN (opcional)", simbolo, { simbolo = it })
            FilledField("Tipo", tipo.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "tipo" })
            FilledField("Clase", clase.title, trailing = StmIcons.arrowDropDown, onClick = { selector = "clase" })
            FilledField("Precio actual por participación", precio, { precio = it }, keyboard = KeyboardType.Decimal)
            FilledField("Comisión de compra en %", comision, { comision = it }, keyboard = KeyboardType.Decimal)
            Text("El precio lo apuntas tú: búscalo en tu bróker o banco cuando quieras actualizarlo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            FilledField("De quién es", inv.ownerName(dueno), trailing = StmIcons.arrowDropDown, onClick = { selector = "dueno" })
            FilledField("Dónde está", finance.account(cuenta)?.name ?: "Ninguna cuenta", trailing = StmIcons.arrowDropDown, onClick = { selector = "cuenta" })
            FilledField("Nota (opcional)", nota, { nota = it })
            Text("Todo el hogar ve las inversiones, como las cuentas.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            if (editando != null) {
                Btn(if (editando.isArchived) "Desarchivar" else "Archivar", {
                    action.run {
                        inv.save(editando.copy(archivedAt = if (editando.isArchived) null else Instant.now().toString()))
                        nav.back()
                    }
                }, Modifier.fillMaxWidth(), kind = BtnKind.Outlined)
                Btn("Borrar activo y sus operaciones", { borrando = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
            }
        }
    }
}
