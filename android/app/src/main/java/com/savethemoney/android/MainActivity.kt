package com.savethemoney.android

import android.content.Intent
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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.SupabaseBackend
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmTheme

class MainActivity : ComponentActivity() {
    private lateinit var session: Session

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Para capturas: adb shell am start -n …/.MainActivity --ei pantalla 14 (modo demo con datos de muestra)
        val capture = intent.getIntExtra("pantalla", 0).takeIf { it in 1..SCREEN_COUNT }
        session = (application as StmApp).session(capture != null)
        handleLink(intent)
        setContent {
            StmTheme {
                CompositionLocalProvider(LocalSession provides session) { App(capture) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLink(intent)
    }

    /** Enlace de invitación savethemoney://unirse/4K9Q2X: queda pendiente para la pantalla «Tu hogar». */
    private fun handleLink(intent: Intent) {
        intent.dataString?.let(InviteCode::parse)?.let { session.pendingInvite = it }
    }
}

/** Una sola sesión por proceso, para que sobreviva a girar la pantalla o recrear la actividad. */
class StmApp : android.app.Application() {
    private var session: Session? = null

    fun session(capture: Boolean): Session = session ?: run {
        val demo = capture || BuildConfig.SUPABASE_ANON_KEY.isBlank() || BuildConfig.SUPABASE_URL.isBlank()
        val backend: Backend = if (demo) InMemoryBackend() else SupabaseBackend(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
        Session(backend, isDemo = demo).also { session = it }
    }
}

/**
 * Raíz: sin sesión lleva a «Iniciar sesión» (01), sin hogar a «Tu hogar» (03) y con hogar a «Inicio» (04).
 * En modo captura abre directamente la pantalla pedida, con Ana y Leo ya en un hogar de muestra.
 */
@Composable
fun App(capture: Int? = null) {
    val session = LocalSession.current
    val nav = remember { Nav(capture ?: 1) }
    LaunchedEffect(Unit) {
        if (capture != null) seedSample(session.backend)
        session.refresh()
    }
    if (capture == null) {
        LaunchedEffect(session.state) {
            when (session.state) {
                Session.State.Loading -> Unit
                Session.State.SignedOut -> if (nav.current !in 1..2) nav.reset(1)
                is Session.State.NeedsHousehold -> nav.reset(3)
                is Session.State.Ready -> if (nav.current in 1..3) nav.reset(4)
            }
        }
    }
    if (session.state == Session.State.Loading) {
        Box(Modifier.fillMaxSize().background(Stm.colors.surface))
        return
    }
    BackHandler(enabled = nav.canGoBack) { nav.back() }
    AnimatedContent(nav.current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "pantalla") { number ->
        ScreenFor(number, nav)
    }
}

/** Datos de muestra del diseño, solo en memoria: Ana y Leo comparten hogar y entra Ana. */
private suspend fun seedSample(backend: Backend) {
    if (backend.currentUserId() != null) return
    val password = "muestra-capturas"
    backend.signUp(Username.parse("ana").getOrThrow(), password, "Ana")
    val home = backend.createHousehold("Casa de Ana")
    val code = InviteCode.parse(backend.createInvite(home.id).code)!!
    backend.signOut()
    backend.signUp(Username.parse("leo").getOrThrow(), password, "Leo")
    backend.acceptInvite(code)
    backend.signOut()
    backend.signIn(Username.parse("ana").getOrThrow(), password)
}
