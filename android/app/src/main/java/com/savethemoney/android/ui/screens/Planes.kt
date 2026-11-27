package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurrenceUnit
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** Sin céntimos si son redondos, como en el diseño. */
internal fun importe(minor: Long) = Money.format(minor, decimals = minor % 100 != 0L)

/** «1 mes», «3 meses», «1 año». */
@Composable internal fun periodo(r: Recurrence): String = when (r.unit) {
    RecurrenceUnit.Week -> pluralStringResource(R.plurals.planes_semanas, r.every, r.every)
    RecurrenceUnit.Month -> pluralStringResource(R.plurals.planes_meses, r.every, r.every)
    RecurrenceUnit.Year -> pluralStringResource(R.plurals.planes_anos, r.every, r.every)
}

@Composable
internal fun textoAviso(dias: Int) =
    if (dias == 0) stringResource(R.string.planes_el_mismo_dia) else pluralStringResource(R.plurals.planes_dias_antes, dias, dias)

/** «Contador» con borde: texto y botones − / + (56 dp). */
@Composable
internal fun Stepper(text: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    val c = Stm.colors
    Row(
        Modifier.width(194.dp).height(56.dp).border(1.dp, c.outline, RoundedCornerShape(4.dp)).padding(start = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
        IconBtn(StmIcons.remove, onMinus, contentDescription = stringResource(R.string.planes_menos))
        Spacer(Modifier.width(4.dp))
        IconBtn(StmIcons.add, onPlus, contentDescription = stringResource(R.string.planes_mas))
    }
}

/** «Progreso» grueso de las metas: 8 dp, hueco de 6 e indicador de parada. */
@Composable
internal fun GoalProgress(fraction: Float) {
    val bar = Stm.colors.primary
    val track = Stm.colors.secondaryContainer
    Canvas(Modifier.fillMaxWidth().height(8.dp)) {
        val r = CornerRadius(size.height / 2)
        val w = size.width * fraction
        val start = w + 6.dp.toPx()
        drawRoundRect(bar, size = Size(w, size.height), cornerRadius = r)
        drawRoundRect(track, Offset(start, 0f), Size(size.width - start, size.height), r)
        drawRoundRect(bar, Offset(size.width - size.height, 0f), Size(size.height, size.height), r)
    }
}
