package com.savethemoney.android

import android.Manifest
import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.res.stringResource
import androidx.core.content.edit
import androidx.core.view.WindowCompat
import com.savethemoney.android.data.AppTheme
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.SupabaseBackend
import com.savethemoney.android.data.SupabaseFinance
import com.savethemoney.android.ui.Bloqueo
import com.savethemoney.android.ui.LocalNotifier
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.PantallaBloqueo
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.borrarExportados
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.screens.SinConexion
import com.savethemoney.android.ui.screens.UnirseDesdeEnlace
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmTheme
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var session: Session
    private var cancelaDesbloqueo: CancellationSignal? = null

    /** Android 9: no hay diálogo con huella y código, se pide el código con la pantalla del sistema. */
    private val confirmaCodigo = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        Bloqueo.app.terminaAutenticar(it.resultCode == RESULT_OK)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Las capturas de pantalla no pasan por aquí: tienen su actividad en src/debug (CapturasActivity).
        session = (application as StmApp).session()
        // Antes de pintar nada y de abrir el enlace: si el bloqueo está activado, la app sale ya bloqueada.
        Bloqueo.app.load(getSharedPreferences("ajustes", MODE_PRIVATE), Bloqueo.seguro(this))
        handleLink(intent)
        com.savethemoney.android.ui.Vista.load(getSharedPreferences("ajustes", MODE_PRIVATE))
        setContent {
            val prefs = remember { getSharedPreferences("ajustes", MODE_PRIVATE) }
            // Hasta que carga el perfil se usa el último tema, para que no parpadee al abrir.
            val theme = session.profile?.theme ?: AppTheme.entries.firstOrNull { it.name == prefs.getString("tema", null) } ?: AppTheme.System
            val dark = when (theme) {
                AppTheme.Light -> false
                AppTheme.Dark -> true
                AppTheme.System -> isSystemInDarkTheme()
            }
            SideEffect {
                prefs.edit().putString("tema", theme.name).apply()
                WindowCompat.getInsetsController(window, window.decorView).run {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            // Tapa la app en recientes y no deja hacer capturas, sólo con el bloqueo activado.
            val pantallaSegura = Bloqueo.app.activo
            SideEffect {
                if (pantallaSegura) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            StmTheme(dark) {
                val bloqueada = Bloqueo.app.bloqueada
                val foco = LocalFocusManager.current
                // Que el teclado no siga escribiendo en el formulario de debajo (lo escrito se conserva).
                LaunchedEffect(bloqueada) { if (bloqueada) foco.clearFocus(force = true) }
                Box(Modifier.fillMaxSize()) {
                    // Bloqueada, lo de debajo no se lee con TalkBack ni se alcanza con el teclado.
                    val tapada = Modifier.clearAndSetSemantics {}.focusProperties { onEnter = { cancelFocusChange() } }.focusGroup()
                    Box(if (bloqueada) tapada else Modifier) {
                        CompositionLocalProvider(LocalSession provides session) { App() }
                    }
                    if (bloqueada) PantallaBloqueo(::pedirDesbloqueo)
                }
            }
        }
    }

    /** Al volver a la app, lo que haya apuntado la pareja; si estaba «sin conexión», se reintenta. */
    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { session.resume(SystemClock.elapsedRealtime()) }
    }

    override fun onStart() {
        super.onStart()
        if (Bloqueo.app.alVolver(SystemClock.elapsedRealtime(), Bloqueo.seguro(this))) {
            window.decorView.post { pedirDesbloqueo() }
        }
    }

    override fun onStop() {
        super.onStop()
        Bloqueo.app.alSalir(SystemClock.elapsedRealtime())
    }

    /** Si la actividad se recrea con el diálogo abierto, que el botón «Desbloquear» vuelva a funcionar. */
    override fun onDestroy() {
        cancelaDesbloqueo?.cancel()
        Bloqueo.app.terminaAutenticar(false)
        super.onDestroy()
    }

    /** Huella o cara y, si no hay o falla, el PIN, patrón o contraseña del dispositivo. */
    private fun pedirDesbloqueo() {
        if (!Bloqueo.app.empiezaAutenticar(Bloqueo.seguro(this))) return
        val titulo = getString(R.string.bloqueo_desbloquea_save_the_money)
        if (Build.VERSION.SDK_INT >= 29) {
            val prompt = BiometricPrompt.Builder(this).setTitle(titulo)
            if (Build.VERSION.SDK_INT >= 30) {
                prompt.setAllowedAuthenticators(Authenticators.BIOMETRIC_WEAK or Authenticators.DEVICE_CREDENTIAL)
            } else {
                @Suppress("DEPRECATION")
                prompt.setDeviceCredentialAllowed(true)
            }
            val cancela = CancellationSignal().also { cancelaDesbloqueo = it }
            prompt.build().authenticate(
                cancela,
                mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) = Bloqueo.app.terminaAutenticar(true)

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) = Bloqueo.app.terminaAutenticar(false)
                },
            )
        } else {
            @Suppress("DEPRECATION")
            val intent = getSystemService(KeyguardManager::class.java).createConfirmDeviceCredentialIntent(titulo, null)
            // Sin código no hay nada que pedir: nunca deja fuera.
            if (intent == null) Bloqueo.app.terminaAutenticar(true) else confirmaCodigo.launch(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLink(intent)
    }

    /** Enlace de invitación savethemoney://unirse/4K9Q2X: queda pendiente para la pantalla «Tu hogar». */
    private fun handleLink(intent: Intent) {
        val code = intent.dataString?.let(InviteCode::parse) ?: return
        // Con la app bloqueada, el enlace espera a que se desbloquee.
        Bloqueo.app.cuandoAbierta(SystemClock.elapsedRealtime(), Bloqueo.seguro(this)) { session.pendingInvite = code }
    }
}

/** Una sola sesión por proceso, para que sobreviva a girar la pantalla o recrear la actividad. */
class StmApp : android.app.Application() {
    private var session: Session? = null

    override fun onCreate() {
        super.onCreate()
        // Lo exportado en una sesión anterior no debe seguir en la caché.
        borrarExportados(this)
    }

    fun session(): Session = session ?: run {
        val demo = BuildConfig.SUPABASE_ANON_KEY.isBlank() || BuildConfig.SUPABASE_URL.isBlank()
        val backend: Backend
        val finance: FinanceService
        if (demo) {
            backend = InMemoryBackend()
            finance = InMemoryFinance(backend)
        } else {
            val remote = SupabaseBackend(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
            backend = remote
            finance = SupabaseFinance(remote)
        }
        val avisos = LocalNotifier(this)
        // El hogar elegido se recuerda por persona en este dispositivo, con el resto de ajustes.
        val ajustes = getSharedPreferences("ajustes", MODE_PRIVATE)
        Session(
            backend, finance, isDemo = demo, notifier = avisos, borrarLocal = { borrarExportados(this); avisos.borrarTodo() },
            hogarElegido = { usuario -> ajustes.getString("hogar_abierto_$usuario", null) },
            eligeHogar = { usuario, hogar -> ajustes.edit { putString("hogar_abierto_$usuario", hogar) } },
        ).also { session = it }
    }
}

/** Raíz: sin sesión lleva a «Iniciar sesión» (01), sin hogar a «Tu hogar» (03) y con hogar a «Inicio» (04). */
@Composable
fun App() {
    val session = LocalSession.current
    val nav = rememberSaveable(saver = Nav.Saver) { Nav(Route.IniciarSesion) }
    LaunchedEffect(Unit) { session.start() }
    LaunchedEffect(Unit) { session.watchSession() }
    LaunchedEffect(session.state) {
        when (session.state) {
            Session.State.Loading -> Unit
            Session.State.SignedOut -> if (nav.current.screen !in 1..2) nav.reset(Route.IniciarSesion)
            is Session.State.Offline -> Unit
            is Session.State.NeedsHousehold -> nav.reset(Route.TuHogar)
            is Session.State.Ready -> if (nav.current.screen in 1..3) nav.reset(Route.Inicio)
        }
    }
    // Se pide el permiso cuando hay algo de lo que avisar, no al abrir la app.
    val activity = LocalContext.current as ComponentActivity
    val hayAvisos = session.finance?.planning?.activeSeries.orEmpty().any { it.remindDaysBefore != null } ||
        session.finance?.cards?.terms.orEmpty().values.any { it.remindDaysBefore != null || it.alertPercent != null }
    LaunchedEffect(hayAvisos) {
        val permiso = Manifest.permission.POST_NOTIFICATIONS
        if (hayAvisos && Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(permiso) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(permiso), 1)
        }
    }
    if (session.state == Session.State.Loading) {
        Box(Modifier.fillMaxSize().background(Stm.colors.surface))
        return
    }
    (session.state as? Session.State.Offline)?.let {
        SinConexion(it.message)
        return
    }
    BackHandler(enabled = nav.canGoBack) { nav.back() }
    Column(Modifier.fillMaxSize()) {
        if (session.isDemo) AvisoDemo()
        Box(Modifier.weight(1f)) {
            AnimatedContent(nav.current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "pantalla") { route ->
                ScreenFor(route, nav)
            }
            // Un enlace de invitación con un hogar ya abierto: nunca se une solo, pregunta antes.
            if (session.state is Session.State.Ready && session.pendingInvite != null) UnirseDesdeEnlace()
        }
    }
}

/** Modo demo (sin Supabase en la compilación de depuración): avisa de que nada se guarda. */
@Composable
private fun AvisoDemo() {
    Text(
        stringResource(R.string.app_modo_demo),
        Modifier.fillMaxWidth().background(Stm.colors.errorContainer).statusBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp),
        color = Stm.colors.onErrorContainer,
        style = StmType.bodySmall,
        textAlign = TextAlign.Center,
    )
}
