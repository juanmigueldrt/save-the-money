package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.BudgetModel
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch

/** Puntos de 0 a 1 para el gráfico: de la cifra más baja a la más alta del periodo. */
internal fun normalizar(valores: List<Long>): List<Float> {
    val min = valores.minOrNull() ?: return emptyList()
    val max = valores.max()
    return valores.map { if (max == min) 0.5f else (it - min).toFloat() / (max - min) }
}

internal fun euros(minor: Long, signed: Boolean = false) = Money.format(minor, decimals = minor % 100 != 0L, signed = signed)

// ───────────────────────── Piezas privadas ─────────────────────────

/** «Elemento de leyenda»: punto de 8 dp y texto. */
@Composable
internal fun LegendItem(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(label, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

@Composable
internal fun colorGrupo(group: BudgetGroup): Color = when (group) {
    BudgetGroup.Needs -> Stm.colors.primary
    BudgetGroup.Wants -> Stm.colors.tertiary
    BudgetGroup.Savings -> Stm.colors.secondary
}

@Composable
internal fun BoxScope.SelectorPeriodos(budgets: BudgetModel, cerrar: () -> Unit) {
    val scope = rememberCoroutineScope()
    SelectorSheet(stringResource(R.string.analisis_elegir_periodo), budgets.periods().map { p -> p.title to { scope.launch { budgets.show(p) }; Unit } }, onDismiss = cerrar)
}

/** Importe final de una fila, en gris. */
@Composable
private fun Amount(text: String) {
    Text(text, style = StmType.bodyMediumTight, color = Stm.colors.onSurfaceVariant, textAlign = TextAlign.End)
}

/**
 * «Botón segmentado» que se ajusta al texto: 12 dp a cada lado (16 en los extremos),
 * segmentos de 48 dp como mínimo y divisores de 1 dp sin ancho propio.
 */
@Composable
internal fun SegmentedWrap(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Row(
                Modifier.fillMaxHeight().widthIn(min = 48.dp)
                    .let { if (on) it.background(c.secondaryContainer) else it }
                    .drawBehind { if (i > 0) drawRect(c.outline, size = Size(1.dp.toPx(), size.height)) }
                    .tap(role = Role.RadioButton) { onSelect(i) }
                    .padding(start = if (i == 0) 16.dp else 12.dp, end = if (i == options.lastIndex) 16.dp else 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (on) {
                    StmIcon(StmIcons.check, c.onSecondaryContainer, size = 18.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(label, style = StmType.labelLarge, color = if (on) c.onSecondaryContainer else c.onSurface, maxLines = 1)
            }
        }
    }
}
