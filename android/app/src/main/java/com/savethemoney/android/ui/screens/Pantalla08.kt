package com.savethemoney.android.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.savethemoney.android.R
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementBulkEdit
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction

/** 08 Acciones del movimiento: la lista de 05 con la hoja de acciones abierta. */
@Composable
fun Pantalla08(nav: Nav, movementId: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val m = finance.movement(movementId) ?: return NoEncontrado(nav)
    val action = rememberAction()
    var confirmaTransferencia by remember { mutableStateOf(false) }
    val editar = {
        nav.go(Route.FormMovimiento(movementId = m.id))
    }
    StmScreen(
        topBar = { MovimientosTopBar(nav) },
        bottomBar = { NavBar(Tab.Inicio, nav::tab) },
        overlay = if (confirmaTransferencia) {
            { DialogoBorrarTransferencia(m, finance, action, { confirmaTransferencia = false }) { nav.back() } }
        } else {
            {
                BottomSheet(MovementText.display(m.description), "${Money.format(m.amountMinor, signed = true)} · ${Fechas.dia(m.day, finance.today())}", onDismiss = nav::back) {
                    SheetItem(StmIcons.category, stringResource(R.string.acciones_movimiento_cambiar_categoria), onClick = editar)
                    SheetItem(StmIcons.check, if (m.isReviewed) stringResource(R.string.acciones_movimiento_marcar_sin_revisar) else stringResource(R.string.acciones_movimiento_marcar_revisado)) {
                        action.run {
                            finance.update(MovementBulkEdit(reviewed = !m.isReviewed).changes(listOf(m)))
                            nav.back()
                        }
                    }
                    SheetItem(if (m.excluded) StmIcons.visibility else StmIcons.visibilityOff, if (m.excluded) stringResource(R.string.acciones_movimiento_volver_a_contar_en_el_presupuesto) else stringResource(R.string.acciones_movimiento_excluir_del_presupuesto)) {
                        action.run {
                            finance.update(MovementBulkEdit(excluded = !m.excluded).changes(listOf(m)))
                            nav.back()
                        }
                    }
                    SheetItem(StmIcons.eventRepeat, stringResource(R.string.acciones_movimiento_aplazar_con_la_tarjeta)) {
                        // Como antes: si no es de una tarjeta, se abre la primera tarjeta.
                        nav.go(Route.AplazarCompra(m.accountId.takeIf { finance.account(it)?.kind == AccountKind.CreditCard }, m.id))
                    }
                    SheetItem(StmIcons.delete, stringResource(R.string.comun_eliminar)) {
                        if (m.transferId != null) {
                            confirmaTransferencia = true
                        } else {
                            action.run {
                                finance.delete(m)
                                nav.back()
                            }
                        }
                    }
                }
            }
        },
    ) {
        ListaMovimientos(listOf(m), finance, totales = false) {}
    }
}
