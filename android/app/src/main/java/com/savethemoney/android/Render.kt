package com.savethemoney.android

import android.graphics.BlurMaskFilter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ripple
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalTextApi::class)
private val Sans = FontFamily(
    Font(R.font.roboto_flex, FontWeight.W400, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.roboto_flex, FontWeight.W500, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
)
private val Serif = FontFamily(Font(R.font.source_serif_4, FontWeight.W400))

/** Colores de la colección Color en el modo activo (Claro u Oscuro). */
class Palette(private val values: Map<String, Long>) {
    fun color(p: DPaint): Color {
        val resolved = p.variable?.let { values[it] } ?: return Color(p.argb.toInt())
        val c = Color(resolved.toInt())
        return c.copy(alpha = c.alpha * p.opacity)
    }
}

private fun roundRect(n: DNode, size: Size, inset: Float): RoundRect {
    val r = n.radii
    fun cr(v: Float) = (v - inset).coerceIn(0f, minOf(size.width, size.height) / 2).let { CornerRadius(it, it) }
    return RoundRect(
        inset, inset, size.width - inset, size.height - inset,
        cr(r?.get(0) ?: 0f), cr(r?.get(1) ?: 0f), cr(r?.get(2) ?: 0f), cr(r?.get(3) ?: 0f),
    )
}

private fun shapeOf(n: DNode): Shape =
    n.radii?.let { RoundedCornerShape(it[0].dp, it[1].dp, it[2].dp, it[3].dp) } ?: RectangleShape

private fun DrawScope.drawShadows(n: DNode) {
    n.shadows.forEach { s ->
        val spread = s.spread.dp.toPx()
        val rect = roundRect(n, size, -spread)
        drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = Color(s.argb.toInt()).toArgb()
                if (s.blur > 0) maskFilter = BlurMaskFilter(s.blur.dp.toPx() * 0.866f, BlurMaskFilter.Blur.NORMAL)
            }
            val path = Path().apply { addRoundRect(rect.translate(Offset(s.x.dp.toPx(), s.y.dp.toPx()))) }
            canvas.nativeCanvas.drawPath((path as androidx.compose.ui.graphics.AndroidPath).internalPath, paint)
        }
    }
}

private fun DrawScope.drawStrokes(n: DNode, pal: Palette) {
    if (n.strokes.isEmpty()) return
    val sides = n.sideWeights
    n.strokes.forEach { p ->
        val c = pal.color(p)
        if (sides != null) {
            val (t, r, b, l) = sides.map { it.dp.toPx() }
            if (t > 0) drawRect(c, Offset.Zero, Size(size.width, t))
            if (r > 0) drawRect(c, Offset(size.width - r, 0f), Size(r, size.height))
            if (b > 0) drawRect(c, Offset(0f, size.height - b), Size(size.width, b))
            if (l > 0) drawRect(c, Offset.Zero, Size(l, size.height))
        } else {
            val sw = n.strokeWeight.dp.toPx()
            val inset = when (n.strokeAlign) { 'I' -> sw / 2; 'O' -> -sw / 2; else -> 0f }
            val path = Path().apply { addRoundRect(roundRect(n, size, inset)) }
            drawPath(path, c, style = Stroke(sw))
        }
    }
}

/** Pinta una capa del diseño y sus hijas, en coordenadas absolutas dentro de su madre. */
@Composable
fun DesignNode(n: DNode, pal: Palette, onAction: (Action) -> Unit) {
    if (n.name == "Tirador") return // la barra de gestos la pone el sistema
    val density = LocalDensity.current
    val vectors = remember(n) {
        n.paths.map { PathParser().parsePathString(it).toPath() }
    }
    val shape = remember(n) { shapeOf(n) }
    var mod = Modifier
        .absoluteOffset(n.x.dp, n.y.dp)
        .size(n.w.dp, n.h.dp)
    if (n.opacity < 1f) mod = mod.graphicsLayer(alpha = n.opacity)
    mod = mod.drawBehind {
        drawShadows(n)
        if (n.type == 'V') {
            val scale = density.density
            n.fills.forEach { p ->
                vectors.forEach { path ->
                    val scaled = Path().apply { addPath(path) }
                    scaled.transform(androidx.compose.ui.graphics.Matrix().apply { scale(scale, scale) })
                    drawPath(scaled, pal.color(p))
                }
            }
        } else if (n.type != 'T') {
            n.fills.forEach { p ->
                val path = Path().apply { addRoundRect(roundRect(n, size, 0f)) }
                drawPath(path, pal.color(p))
            }
        }
    }
    n.action?.let { action ->
        mod = mod.clip(shape).clickable(indication = ripple(), interactionSource = null) { onAction(action) }
    }
    mod = mod.drawWithContent {
        drawContent()
        drawStrokes(n, pal)
    }
    if (n.clip) mod = mod.clip(shape)

    Box(mod) {
        n.text?.let { DesignText(n, it, pal) }
        if (n.name == "Barra de estado") return@Box // hora e iconos los pone el sistema
        if (n.clip && n.contentHeight > n.h + 1f) {
            Box(Modifier.size(n.w.dp, n.h.dp).verticalScroll(rememberScrollState())) {
                Box(Modifier.size(n.w.dp, (n.contentHeight + 16f).dp)) {
                    n.children.forEach { DesignNode(it, pal, onAction) }
                }
            }
        } else {
            n.children.forEach { DesignNode(it, pal, onAction) }
        }
    }
}

@Composable
private fun DesignText(n: DNode, t: DText, pal: Palette) {
    val density = LocalDensity.current
    val style = with(density) {
        TextStyle(
            color = n.fills.firstOrNull()?.let(pal::color) ?: Color.Black,
            fontFamily = if (t.serif) Serif else Sans,
            fontWeight = FontWeight(t.weight),
            fontSize = t.size.dp.toSp(),
            lineHeight = (t.lineHeight ?: (t.size * 1.2f)).dp.toSp(),
            letterSpacing = t.letterSpacing.dp.toSp(),
            textAlign = when (t.align) { 'C' -> TextAlign.Center; 'R' -> TextAlign.End; else -> TextAlign.Start },
            platformStyle = PlatformTextStyle(includeFontPadding = false),
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
        )
    }
    if (t.autoResize == 'W') {
        val align = when (t.align) { 'C' -> Alignment.TopCenter; 'R' -> Alignment.TopEnd; else -> Alignment.TopStart }
        Text(t.text, Modifier.wrapContentSize(align, unbounded = true), style = style, softWrap = false)
    } else {
        Text(t.text, Modifier.width(n.w.dp), style = style)
    }
}
