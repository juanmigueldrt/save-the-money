package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementBulkEdit
import com.savethemoney.android.data.MovementText
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 34 Detalle de movimiento con el menú de acciones abierto. */
@Composable
fun Pantalla34(nav: Nav, movementId: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val m = finance.movement(movementId) ?: return NoEncontrado(nav)
    var menu by remember { mutableStateOf(true) }
    var confirmaTransferencia by remember { mutableStateOf(false) }
    val action = rememberAction()
    val cat = finance.category(m.categoryId)
    val editar = {
        nav.go(Route.FormMovimiento(movementId = m.id))
    }
    StmScreen(
        topBar = {
            TopBar(MovementText.display(m.description), onNav = nav::back) {
                IconBtn(StmIcons.edit, editar, contentDescription = stringResource(R.string.comun_editar))
                IconBtn(StmIcons.moreVert, { menu = !menu }, contentDescription = stringResource(R.string.comun_mas_opciones))
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (confirmaTransferencia) {
            { DialogoBorrarTransferencia(m, finance, action, { confirmaTransferencia = false }) { nav.back() } }
        } else if (menu) {
            {
                Box(
                    Modifier.matchParentSize()
                        .clickable(remember { MutableInteractionSource() }, indication = null) { menu = false },
                )
                // Barra superior (64) + 96 del diseño, a 12 dp del borde derecho.
                MenuDesplegable(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 160.dp, end = 12.dp)) {
                    ElementoMenu(StmIcons.edit, stringResource(R.string.comun_editar), onClick = editar)
                    // Duplicar una pata apuntaría solo un lado de la transferencia.
                    if (m.transferId == null) {
                        ElementoMenu(StmIcons.contentCopy, stringResource(R.string.detalle_movimiento_duplicar)) {
                            action.run {
                                finance.add(m.toDraft().copy(importHash = null))
                                nav.back()
                            }
                        }
                    }
                    ElementoMenu(StmIcons.check, if (m.isReviewed) stringResource(R.string.detalle_movimiento_sin_revisar) else stringResource(R.string.acciones_movimiento_marcar_revisado)) {
                        menu = false
                        action.run { finance.update(MovementBulkEdit(reviewed = !m.isReviewed).changes(listOf(m))) }
                    }
                    ElementoMenu(if (m.excluded) StmIcons.visibility else StmIcons.visibilityOff, if (m.excluded) stringResource(R.string.movimientos_volver_a_contar) else stringResource(R.string.movimientos_excluir)) {
                        menu = false
                        action.run { finance.update(MovementBulkEdit(excluded = !m.excluded).changes(listOf(m))) }
                    }
                    ElementoMenu(StmIcons.eventRepeat, stringResource(R.string.detalle_movimiento_aplazar)) {
                        // Como antes: si no es de una tarjeta, se abre la primera tarjeta.
                        nav.go(Route.AplazarCompra(m.accountId.takeIf { finance.account(it)?.kind == AccountKind.CreditCard }, m.id))
                    }
                    Spacer(Modifier.height(8.dp))
                    Divider(inset = 0.dp, endInset = 0.dp)
                    Spacer(Modifier.height(8.dp))
                    ElementoMenu(StmIcons.delete, stringResource(R.string.comun_eliminar), Stm.colors.error, Stm.colors.error) {
                        if (m.transferId != null) {
                            menu = false
                            confirmaTransferencia = true
                        } else {
                            // Sin borrar lastDeleted: la lista muestra «Deshacer» como con el resto de borrados.
                            action.run {
                                finance.delete(m)
                                nav.back()
                            }
                        }
                    }
                }
            }
        } else null,
    ) {
        CifraCuenta(
            listOfNotNull(cat?.name ?: stringResource(R.string.comun_sin_categoria), finance.account(m.accountId)?.name).joinToString(" · "),
            Money.format(m.amountMinor, signed = true),
            Fechas.largo(m.day, finance.today()),
        )
        Spacer(Modifier.height(16.dp))
        ChipsMovimiento(!m.notes.isNullOrEmpty(), editar)
        m.notes?.takeIf { it.isNotEmpty() }?.let {
            Spacer(Modifier.height(16.dp))
            Text(it, style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        }
        val extra = listOfNotNull(
            m.payee,
            m.tags.takeIf { it.isNotEmpty() }?.joinToString(" ") { "#$it" },
            if (m.isReviewed) stringResource(R.string.detalle_movimiento_revisado) else null,
            if (m.excluded) stringResource(R.string.movimientos_excluido_del_presupuesto) else null,
        )
        if (extra.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text(extra.joinToString(" · "), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        }
    }
}

/** «Menú» desplegable de 200 dp en `surface-container`. */
@Composable
private fun MenuDesplegable(modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Column(
        modifier.width(200.dp).shadow(3.dp, shape).clip(shape).background(Stm.colors.surfaceContainer)
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .padding(vertical = 8.dp),
        content = content,
    )
}

/** «Elemento de menú» (48 dp): icono de 24 y texto. */
@Composable
private fun ElementoMenu(
    icon: ImageVector,
    label: String,
    color: Color = Stm.colors.onSurface,
    iconTint: Color = Stm.colors.onSurfaceVariant,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).tap(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(icon, iconTint)
        Spacer(Modifier.width(12.dp))
        Text(label, style = StmType.bodyMedium, color = color)
    }
}
