package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo

/** 09 Nueva o editar cuenta: nombre, tipo, saldo inicial y si se comparte con el hogar. */
@Composable
fun Pantalla09(nav: Nav, accountId: String?, kind: AccountKind?) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val c = Stm.colors
    val editando = rememberRow(accountId, finance::account)
    if (accountId != null && editando == null) return NoEncontrado(nav)
    var nombre by rememberSaveable { mutableStateOf(editando?.name ?: "") }
    var tipo by rememberSaveable { mutableStateOf(editando?.kind ?: kind ?: AccountKind.Checking) }
    var saldo by rememberSaveable {
        mutableStateOf(editando?.openingMinor?.takeIf { it != 0L }?.let(Money::input) ?: "")
    }
    var compartir by rememberSaveable { mutableStateOf(editando?.isShared ?: true) }
    var predeterminada by rememberSaveable { mutableStateOf(editando?.isDefault ?: false) }
    var patrimonio by rememberSaveable { mutableStateOf(editando?.includeInNetWorth ?: true) }
    val action = rememberAction()
    // Identificador de la cuenta nueva, uno por formulario: reintentar el alta con el mismo no crea otra.
    val idCuenta = rememberSaveable { java.util.UUID.randomUUID().toString() }
    // Una tarjeta ya creada no puede cambiar de tipo (el servidor también lo rechaza).
    val tarjetaFija = editando?.kind == AccountKind.CreditCard
    val tipos = listOf(AccountKind.Checking, AccountKind.Savings, AccountKind.CreditCard, AccountKind.Cash, AccountKind.Investment)
        .let { if (tipo in it) it else it + tipo }
        .filter { !tarjetaFija || it == AccountKind.CreditCard }
    val resources = LocalResources.current

    fun guardar() = action.run {
        val apertura = if (saldo.isBlank()) 0L else Money.entered(saldo) ?: throw AppError.InvalidInput(resources.getString(R.string.form_cuenta_el_saldo_inicial_no_es_un))
        val dueno = if (compartir) null else editando?.ownerId ?: session.profile?.id
        val draft = AccountDraft(nombre, tipo, apertura, dueno, idCuenta)
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
            TopBar(if (editando != null) stringResource(R.string.form_cuenta_editar_cuenta) else stringResource(R.string.form_cuenta_nueva_cuenta), navIcon = StmIcons.close, onNav = nav::back) {
                Btn(stringResource(R.string.comun_guardar), ::guardar, kind = BtnKind.Text)
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        FilledField(stringResource(R.string.comun_nombre), nombre, { nombre = it }, autoFocus = true)
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.form_cuenta_tipo), style = StmType.labelLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        ChipRow(Modifier.fillMaxWidth()) {
            tipos.forEach { t ->
                Chip(if (t == AccountKind.Checking) stringResource(R.string.form_cuenta_corriente) else stringResource(t.titulo), selected = t == tipo, onClick = { tipo = t })
            }
        }
        if (tarjetaFija) {
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.form_cuenta_una_tarjeta_de_credito_no_puede), style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        FilledField(stringResource(R.string.form_cuenta_saldo_inicial), saldo, { saldo = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                stringResource(R.string.form_cuenta_compartir_con_el_hogar), stringResource(R.string.form_cuenta_tu_pareja_vera_el_saldo_y),
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
            FilaInterruptor(stringResource(R.string.form_cuenta_cuenta_predeterminada), null, predeterminada) { predeterminada = it }
            Divider(inset = 16.dp)
            FilaInterruptor(stringResource(R.string.form_cuenta_contar_en_el_patrimonio), null, patrimonio) { patrimonio = it }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.form_cuenta_la_predeterminada_sale_elegida_al),
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
    }
}
