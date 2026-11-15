package com.savethemoney.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.theme.Stm

/**
 * «Gráfico de línea»: 4 guías, área al 12 % y línea de 2,5 dp con punto final de 10 dp.
 * [values] van de 0 (abajo) a 1 (arriba), repartidos a lo ancho. El área ocupa [plotHeight];
 * el lienzo deja 4 dp arriba y 16 abajo, como en el diseño.
 */
@Composable
fun LineChart(
    values: List<Float>,
    modifier: Modifier = Modifier.fillMaxWidth(),
    plotHeight: Dp = 120.dp,
    color: Color = Stm.colors.primary,
    guide: Color = Stm.colors.outlineVariant,
) {
    Canvas(modifier.height(plotHeight + 20.dp)) {
        val top = 4.dp.toPx()
        val inset = 4.dp.toPx()
        val h = plotHeight.toPx()
        val w = size.width - 2 * inset
        repeat(4) { i ->
            val y = top + (h - top) * i / 3f // como el diseño: guías en 4, 42,7, 81,3 y 120 de 124
            drawRect(guide, Offset(0f, y), Size(size.width, 1.dp.toPx()))
        }
        if (values.size < 2) return@Canvas
        val pts = values.mapIndexed { i, v -> Offset(inset + w * i / (values.size - 1), top + h * (1f - v.coerceIn(0f, 1f))) }
        val line = Path().apply { moveTo(pts[0].x, pts[0].y); pts.drop(1).forEach { lineTo(it.x, it.y) } }
        val area = Path().apply { addPath(line); lineTo(pts.last().x, top + h); lineTo(pts[0].x, top + h); close() }
        drawPath(area, color.copy(alpha = 0.12f))
        drawPath(line, color, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawCircle(color, 5.dp.toPx(), pts.last())
    }
}

/** Tramo de un gráfico circular: fracción del total (0–1) y color. */
data class Slice(val fraction: Float, val color: Color)

/**
 * «Semicírculo»: pista de 180° y tramos desde la izquierda, separados por un hueco.
 * El ancho es el diámetro; el alto, la mitad.
 */
@Composable
fun SemicircleGauge(slices: List<Slice>, width: Dp = 300.dp, thickness: Dp = 24.dp, track: Color = Stm.colors.surfaceContainerHighest, gapDegrees: Float = 2f) {
    Canvas(Modifier.size(width, width / 2)) {
        val t = thickness.toPx()
        val box = Size(size.width - t, size.width - t)
        val origin = Offset(t / 2, t / 2)
        val stroke = Stroke(t)
        drawArc(track, 180f, 180f, false, origin, box, style = stroke)
        var start = 180f
        slices.forEach { s ->
            val sweep = 180f * s.fraction
            if (sweep > gapDegrees) drawArc(s.color, start, sweep - gapDegrees, false, origin, box, style = stroke)
            start += sweep
        }
    }
}

/** «Anillo»: tramos en sentido horario desde arriba, con hueco entre ellos. */
@Composable
fun Donut(slices: List<Slice>, size: Dp = 112.dp, thickness: Dp = 16.dp, gapDegrees: Float = 3f) {
    Canvas(Modifier.size(size)) {
        val t = thickness.toPx()
        val box = Size(this.size.width - t, this.size.height - t)
        val origin = Offset(t / 2, t / 2)
        var start = -90f
        slices.forEach { s ->
            val sweep = 360f * s.fraction
            if (sweep > gapDegrees) drawArc(s.color, start + gapDegrees / 2, sweep - gapDegrees, false, origin, box, style = Stroke(t))
            start += sweep
        }
    }
}
