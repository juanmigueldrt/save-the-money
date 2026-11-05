@file:OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)

package com.savethemoney.android.ui.theme

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.savethemoney.android.R

/** Colores de la paleta de marca que el diseño usa igual en claro y en oscuro. */
object Brand {
    val ink = Color(0xFF22201D)
    val paper = Color(0xFFFFFFFF)
    val ember = Color(0xFFFF692D)
}

private val Sans = FontFamily(
    Font(R.font.roboto_flex, FontWeight.W400, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.roboto_flex, FontWeight.W500, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    Font(R.font.roboto_flex, FontWeight.W600, variationSettings = FontVariation.Settings(FontVariation.weight(600))),
)
private val Serif = FontFamily(Font(R.font.source_serif_4, FontWeight.W400))

private fun style(serif: Boolean, weight: Int, size: Int, line: Int, spacing: Double) = TextStyle(
    fontFamily = if (serif) Serif else Sans,
    fontWeight = FontWeight(weight),
    fontSize = size.sp,
    lineHeight = line.sp,
    letterSpacing = spacing.sp,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
)

/** Estilos de texto del diseño (Source Serif 4 para títulos y cifras, Roboto Flex para el resto). */
object StmType {
    val displayLarge = style(true, 400, 57, 64, -1.5)
    val displayMedium = style(true, 400, 45, 52, -1.0)
    val displaySmall = style(true, 400, 36, 44, -0.6)
    val headlineLarge = style(true, 400, 32, 40, -0.5)
    val headlineMedium = style(true, 400, 28, 36, -0.4)
    val headlineMediumWide = style(true, 400, 28, 36, 0.5)
    val headlineSmall = style(true, 400, 24, 32, -0.2)
    val titleLarge = style(true, 400, 22, 28, 0.0)
    val appBarTitle = style(true, 400, 22, 28, 0.5)
    val titleMedium = style(false, 500, 16, 24, 0.15)
    val titleSmall = style(false, 500, 14, 20, 0.1)
    val titleSmallTall = style(false, 500, 14, 24, 0.15)
    val bodyLarge = style(false, 400, 16, 24, 0.5)
    val bodyMedium = style(false, 400, 14, 20, 0.25)
    val bodyMediumTight = style(false, 400, 14, 20, 0.1)
    val bodySmall = style(false, 400, 12, 16, 0.4)
    val labelLarge = style(false, 500, 14, 20, 0.1)
    val labelMedium = style(false, 500, 12, 16, 0.5)
    val labelSmall = style(false, 500, 11, 16, 0.5)
}

/** Medidas del diseño (colección Medidas). */
object Dimens {
    val screenPadding = 16.dp
    val cornerSmall = 8.dp
    val cornerMedium = 12.dp
    val cornerLarge = 16.dp
    val cornerExtraLarge = 28.dp
    val topAppBar = 64.dp
    val listItem1 = 56.dp
    val listItem2 = 72.dp
    val textField = 56.dp
    val chip = 32.dp
    val segmented = 40.dp
}

val LocalStmColors = staticCompositionLocalOf { Palettes.claro }

/** Atajo: `Stm.colors.primary`. */
object Stm {
    val colors: StmColors
        @Composable @ReadOnlyComposable get() = LocalStmColors.current
}

/** Contraste que pide el sistema (Android 14+): 0 normal, 1 medio, 2 alto. */
private fun systemContrast(context: Context): Int {
    if (Build.VERSION.SDK_INT < 34) return 0
    val c = context.getSystemService(UiModeManager::class.java)?.contrast ?: 0f
    return when {
        c >= 0.5f -> 2
        c >= 0.25f -> 1
        else -> 0
    }
}

fun palette(dark: Boolean, contrast: Int): StmColors = when (contrast) {
    2 -> if (dark) Palettes.oscuroAlto else Palettes.claroAlto
    1 -> if (dark) Palettes.oscuroMedio else Palettes.claroMedio
    else -> if (dark) Palettes.oscuro else Palettes.claro
}

@Composable
fun StmTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val c = palette(dark, systemContrast(LocalContext.current))
    val scheme = (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = c.primary, onPrimary = c.onPrimary,
        primaryContainer = c.primaryContainer, onPrimaryContainer = c.onPrimaryContainer,
        secondary = c.secondary, onSecondary = c.onSecondary,
        secondaryContainer = c.secondaryContainer, onSecondaryContainer = c.onSecondaryContainer,
        tertiary = c.tertiary, onTertiary = c.onTertiary,
        tertiaryContainer = c.tertiaryContainer, onTertiaryContainer = c.onTertiaryContainer,
        error = c.error, onError = c.onError, errorContainer = c.errorContainer, onErrorContainer = c.onErrorContainer,
        background = c.surface, onBackground = c.onSurface,
        surface = c.surface, onSurface = c.onSurface, onSurfaceVariant = c.onSurfaceVariant,
        surfaceVariant = c.surfaceContainerHighest, surfaceDim = c.surfaceDim, surfaceBright = c.surfaceBright,
        surfaceContainerLowest = c.surfaceContainerLowest, surfaceContainerLow = c.surfaceContainerLow,
        surfaceContainer = c.surfaceContainer, surfaceContainerHigh = c.surfaceContainerHigh,
        surfaceContainerHighest = c.surfaceContainerHighest,
        outline = c.outline, outlineVariant = c.outlineVariant,
        inverseSurface = c.inverseSurface, inverseOnSurface = c.inverseOnSurface, inversePrimary = c.inversePrimary,
        scrim = c.scrim,
    )
    CompositionLocalProvider(LocalStmColors provides c) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
