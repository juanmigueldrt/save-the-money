package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Chip
import com.savethemoney.android.ui.components.ChipRow
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.util.UUID

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
            TopBar(stringResource(R.string.categorias_categorias), onNav = nav::back) {
                IconBtn(StmIcons.add, {
                    editando = BudgetCategory(
                        UUID.randomUUID().toString(), finance.household.id, "", kind,
                        if (income) null else BudgetGroup.Needs,
                    )
                }, contentDescription = stringResource(R.string.categorias_anadir_categoria))
            }
        },
        overlay = editando?.let { cat -> { DialogoCategoria(cat, finance) { editando = null } } },
    ) {
        ChipRow {
            Chip(stringResource(R.string.categorias_gastos), selected = !income, onClick = { income = false })
            Chip(stringResource(R.string.categorias_ingresos), selected = income, onClick = { income = true })
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            val grupos = lista.groupBy { it.budgetGroup }
            (BudgetGroup.entries + listOf(null)).forEach { grupo ->
                val filas = grupos[grupo] ?: return@forEach
                when {
                    grupo != null -> ListHeader(grupo.title)
                    !income -> ListHeader(stringResource(R.string.categorias_sin_grupo))
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
            stringResource(R.string.categorias_borrar, inicial.name),
            if (usos > 0) stringResource(R.string.categorias_movimientos_recientes_se_quedaran, usos) else stringResource(R.string.categorias_no_hay_movimientos_recientes_con),
            icon = StmIcons.deleteForever,
            onDismiss = { borrando = false },
            actions = {
                Btn(stringResource(R.string.comun_cancelar), { borrando = false }, kind = BtnKind.Text)
                Btn(stringResource(R.string.comun_borrar), {
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
        if (existe) stringResource(R.string.categorias_editar_categoria) else stringResource(R.string.categorias_nueva_categoria),
        onDismiss = onDismiss,
        actions = {
            if (existe) Btn(stringResource(R.string.comun_borrar), { borrando = true }, kind = BtnKind.Error)
            Btn(stringResource(R.string.comun_cancelar), onDismiss, kind = BtnKind.Text)
            Btn(stringResource(R.string.comun_guardar), {
                action.run {
                    finance.save(inicial.copy(name = nombre, budgetGroup = grupo))
                    onDismiss()
                }
            }, kind = BtnKind.Text)
        },
    ) {
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            stringResource(R.string.comun_nombre), nombre, { nombre = it }, labelBackground = c.surfaceContainerHigh, autoFocus = !existe,
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
        trailing = { StmIcon(StmIcons.dragIndicator, Stm.colors.onSurfaceVariant, contentDescription = stringResource(R.string.categorias_reordenar)) },
    )
}
