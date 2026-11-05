package com.savethemoney.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    private val design by lazy {
        Design.parse(assets.open("screens.json").bufferedReader().use { it.readText() }).also(::wireNavigation)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Para capturas y pruebas: adb shell am start -n …/.MainActivity --ei pantalla 14
        val start = intent.getIntExtra("pantalla", 1).coerceIn(1, design.screens.size)
        setContent { App(design, start) }
    }
}

private const val DESIGN_W = 412f
private const val DESIGN_H = 917f

@Composable
fun App(design: Design, start: Int = 1) {
    val dark = isSystemInDarkTheme()
    val palette = remember(dark) { Palette(if (dark) design.dark else design.light) }
    var stack by rememberSaveable { mutableStateOf(listOf(start)) }

    fun handle(action: Action) {
        stack = when (action) {
            is Action.Go -> stack + action.screen
            is Action.Tab -> listOf(action.screen)
            is Action.Reset -> listOf(action.screen)
            Action.Back -> if (stack.size > 1) stack.dropLast(1) else stack
        }
    }
    BackHandler(enabled = stack.size > 1) { handle(Action.Back) }

    val current = design.screen(stack.last())
    val background = current.fills.firstOrNull()?.let(palette::color)
    BoxWithConstraints(Modifier.fillMaxSize().let { m -> background?.let { m.background(it) } ?: m }) {
        // Escala el lienzo de 412 × 917 dp del diseño al ancho del móvil (o al alto, si no cabe).
        val scale = minOf(maxWidth.value / DESIGN_W, maxHeight.value / DESIGN_H).coerceAtLeast(0.5f)
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density * scale, 1f)) {
            AnimatedContent(
                targetState = stack.last(),
                transitionSpec = { fadeIn() togetherWith fadeOut() },
                modifier = Modifier.align(Alignment.TopCenter),
                label = "pantalla",
            ) { number ->
                Box(Modifier.requiredSize(DESIGN_W.dp, DESIGN_H.dp)) {
                    val screen = design.screen(number)
                    DesignNode(screen, palette, ::handle)
                }
            }
        }
    }
}
