package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.monthEndBalances
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.Instant

/** 06 Cuenta: saldo, acciones, evolución en 6 meses y sus movimientos por mes. */
@Composable
fun Pantalla06(nav: Nav, accountId: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val account = finance.account(accountId) ?: return NoEncontrado(nav)
    val c = Stm.colors
    var lista by remember(account.id) { mutableStateOf(emptyList<Movement>()) }
    var opciones by remember { mutableStateOf(false) }
    var confirmar by remember { mutableStateOf(false) }
    var ajustando by remember { mutableStateOf(false) }
    val action = rememberAction()
    var fallo by remember(account.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(account.id) { finance.showList(account.id, "") }
    LaunchedEffect(account.id, finance.recent) {
        try {
            lista = finance.movements(account)
            fallo = null
        } catch (e: AppError) {
            // Se queda la lista que había, con el aviso: no es lo mismo que una cuenta sin movimientos.
            fallo = "No se han podido cargar los movimientos del gráfico. ${e.message}"
        }
    }
    val hoy = finance.today()
    val serie = monthEndBalances(finance.balance(account), lista, hoy)
    val alto = serie.max()
    val bajo = serie.min()
    StmScreen(
        topBar = {
            TopBar(account.name, onNav = nav::back) {
                IconBtn(StmIcons.edit, {
                    nav.go(Route.FormCuenta(account.id))
                }, contentDescription = "Editar")
                IconBtn(StmIcons.moreVert, { opciones = true }, contentDescription = "Más opciones")
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = when {
            ajustando -> { { HojaAjusteSaldo(finance, account) { ajustando = false } } }
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
                        SheetItem(StmIcons.syncAlt, "Actualizar saldo") {
                            opciones = false
                            ajustando = true
                        }
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
                nav.go(Route.ImportarCsv(account.id))
            }, kind = BtnKind.Tonal, icon = StmIcons.uploadFile)
            Btn("Transferir", {
                nav.go(Route.FormMovimiento(accountId = account.id, transfer = true))
            }, kind = BtnKind.Outlined, icon = StmIcons.syncAlt)
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Text("Saldo en 6 meses", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            LineChart(serie.map { if (alto == bajo) 0.5f else (it - bajo).toFloat() / (alto - bajo) })
        }
        Spacer(Modifier.height(16.dp))
        fallo?.let { Text(it, Modifier.padding(vertical = 8.dp), style = StmType.bodyMedium, color = Stm.colors.error) }
        // La lista de la cuenta va por páginas (ORC-85); [lista] solo alimenta el gráfico.
        val filas = if (finance.list.accountId == account.id) finance.list.rows else emptyList()
        if (filas.isEmpty() && finance.listError == null) {
            Vacio(if (finance.isLoadingList || finance.list.accountId != account.id) "Cargando…" else "Todavía no hay movimientos en esta cuenta.")
        }
        filas.groupBy { it.day.withDayOfMonth(1) }.forEach { (mes, items) ->
            ListCard {
                ListHeader(Fechas.mesTitulo(mes) + if (mes.year != hoy.year) " ${mes.year}" else "")
                items.forEachIndexed { i, m ->
                    if (i > 0) Divider()
                    FilaMovimiento(m, finance, Fechas.corto(m.day)) {
                        finance.tappedMovement = m
                        nav.go(Route.DetalleMovimiento(m.id))
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        if (finance.list.accountId == account.id) PieLista(finance)
    }
}

/** «Actualizar saldo»: escribes lo que marca el banco y se apunta hoy un «AJUSTE DE SALDO» por la diferencia. */
@Composable
private fun BoxScope.HojaAjusteSaldo(finance: FinanceModel, account: Account, cerrar: () -> Unit) {
    val c = Stm.colors
    var real by remember { mutableStateOf("") }
    val action = rememberAction()
    val actual = finance.balance(account)
    val diferencia = Money.entered(real)?.let { it - actual }
    BottomSheet("Actualizar saldo", "Saldo en la app: ${Money.format(actual)}", onDismiss = cerrar) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            FilledField("Saldo real", real, { real = it }, suffix = "€", keyboard = KeyboardType.Decimal, autoFocus = true, calculator = true)
            Spacer(Modifier.height(8.dp))
            Text(
                if (diferencia != null && diferencia != 0L) "Ajuste: ${Money.format(diferencia, signed = true, options = Money.display.copy(plusSign = true))}"
                else "Se apunta un movimiento «Ajuste de saldo» por la diferencia, hoy. No cuenta como gasto ni como ingreso.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            action.error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, style = StmType.bodySmall, color = c.error)
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Btn("Cancelar", cerrar, kind = BtnKind.Text)
                Btn("Guardar", {
                    action.run {
                        val valor = Money.entered(real) ?: throw AppError.InvalidInput("Escribe el saldo, por ejemplo 1.250,00.")
                        finance.adjustBalance(account, valor)
                        cerrar()
                    }
                })
            }
        }
    }
}
