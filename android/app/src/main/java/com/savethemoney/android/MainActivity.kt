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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.theme.StmTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Para capturas y pruebas: adb shell am start -n …/.MainActivity --ei pantalla 14
        val start = intent.getIntExtra("pantalla", 1).coerceIn(1, SCREEN_COUNT)
        setContent { StmTheme { App(start) } }
    }
}

@Composable
fun App(start: Int = 1) {
    val nav = remember { Nav(start) }
    BackHandler(enabled = nav.canGoBack) { nav.back() }
    AnimatedContent(nav.current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "pantalla") { number ->
        ScreenFor(number, nav)
    }
}
