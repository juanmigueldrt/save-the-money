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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.Budget
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.NoNotifier
import com.savethemoney.android.data.Recurrence
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.SupabaseBackend
import com.savethemoney.android.data.SupabaseFinance
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.Bloqueo
import com.savethemoney.android.ui.LocalNotifier
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.PantallaBloqueo
import com.savethemoney.android.ui.borrarExportados
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.screens.SinConexion
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmTheme
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

class MainActivity : ComponentActivity() {
    private lateinit var session: Session
    private var capture: Int? = null
    private var cancelaDesbloqueo: CancellationSignal? = null

    /** Android 9: no hay diálogo con huella y código, se pide el código con la pantalla del sistema. */
    private val confirmaCodigo = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        Bloqueo.app.terminaAutenticar(it.resultCode == RESULT_OK)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Para capturas: adb shell am start -n …/.MainActivity --ei pantalla 14 (modo demo con datos de muestra)
        val requested = capturaPedida(BuildConfig.CAPTURAS, intent.getIntExtra("pantalla", 0))
        session = (application as StmApp).session(requested != null)
        // La actividad es exportada: si el proceso ya tenía una sesión real, el extra no abre pantallas ni siembra datos.
        val capture = requested.takeIf { session.capture }
        this.capture = capture
        // Antes de pintar nada y de abrir el enlace: si el bloqueo está activado, la app sale ya bloqueada.
        // Ni bloqueo ni FLAG_SECURE en capturas: el diseño las necesita.
        if (capture == null) Bloqueo.app.load(getSharedPreferences("ajustes", MODE_PRIVATE), Bloqueo.seguro(this))
        handleLink(intent)
        // Las capturas comparan con el diseño: siempre con la vista normal.
        if (capture == null) com.savethemoney.android.ui.Vista.load(getSharedPreferences("ajustes", MODE_PRIVATE))
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
            val pantallaSegura = capture == null && Bloqueo.app.activo
            SideEffect {
                if (pantallaSegura) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            StmTheme(dark) {
                val bloqueada = capture == null && Bloqueo.app.bloqueada
                val foco = LocalFocusManager.current
                // Que el teclado no siga escribiendo en el formulario de debajo (lo escrito se conserva).
                LaunchedEffect(bloqueada) { if (bloqueada) foco.clearFocus(force = true) }
                Box(Modifier.fillMaxSize()) {
                    // Bloqueada, lo de debajo no se lee con TalkBack ni se alcanza con el teclado.
                    val tapada = Modifier.clearAndSetSemantics {}.focusProperties { onEnter = { cancelFocusChange() } }.focusGroup()
                    Box(if (bloqueada) tapada else Modifier) {
                        CompositionLocalProvider(LocalSession provides session) { App(capture) }
                    }
                    if (bloqueada) PantallaBloqueo(::pedirDesbloqueo)
                }
            }
        }
    }

    /** Al volver a la app, lo que haya apuntado la pareja; si estaba «sin conexión», se reintenta. */
    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { session.resume() }
    }

    override fun onStart() {
        super.onStart()
        if (capture == null && Bloqueo.app.alVolver(SystemClock.elapsedRealtime(), Bloqueo.seguro(this))) {
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
        val titulo = "Desbloquea Save the Money"
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

/** Pantalla que pide el extra de capturas, o nulo si el gancho no va compilado o el número no existe. */
internal fun capturaPedida(habilitado: Boolean, extra: Int): Int? = extra.takeIf { habilitado && it in 1..SCREEN_COUNT }

/** Una sola sesión por proceso, para que sobreviva a girar la pantalla o recrear la actividad. */
class StmApp : android.app.Application() {
    private var session: Session? = null

    override fun onCreate() {
        super.onCreate()
        // Lo exportado en una sesión anterior no debe seguir en la caché.
        borrarExportados(this)
    }

    fun session(capture: Boolean): Session = session ?: run {
        val demo = capture || BuildConfig.SUPABASE_ANON_KEY.isBlank() || BuildConfig.SUPABASE_URL.isBlank()
        val backend: Backend
        val finance: FinanceService
        if (demo) {
            backend = InMemoryBackend()
            finance = InMemoryFinance()
        } else {
            val remote = SupabaseBackend(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
            backend = remote
            finance = SupabaseFinance(remote)
        }
        val today: () -> LocalDate = if (capture) ({ CAPTURE_DAY }) else LocalDate::now
        val avisos = if (capture) null else LocalNotifier(this)
        Session(backend, finance, isDemo = demo, capture = capture, today = today, notifier = avisos ?: NoNotifier,
            borrarLocal = { borrarExportados(this); avisos?.borrarTodo() }).also { session = it }
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
        if (capture != null) seedSample(session.backend, session.financeService)
        session.start()
    }
    LaunchedEffect(Unit) { session.watchSession() }
    if (capture == null) {
        LaunchedEffect(session.state) {
            when (session.state) {
                Session.State.Loading -> Unit
                Session.State.SignedOut -> if (nav.current !in 1..2) nav.reset(1)
                is Session.State.Offline -> Unit
                is Session.State.NeedsHousehold -> nav.reset(3)
                is Session.State.Ready -> if (nav.current in 1..3) nav.reset(4)
            }
        }
    }
    // Se pide el permiso cuando hay algo de lo que avisar, no al abrir la app.
    val activity = LocalContext.current as ComponentActivity
    val hayAvisos = capture == null && (
        session.finance?.planning?.activeSeries.orEmpty().any { it.remindDaysBefore != null } ||
            session.finance?.cards?.terms.orEmpty().values.any { it.remindDaysBefore != null || it.alertPercent != null }
    )
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
        if (session.isDemo && capture == null) AvisoDemo()
        Box(Modifier.weight(1f)) {
            AnimatedContent(nav.current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "pantalla") { number ->
                ScreenFor(number, nav)
            }
        }
    }
}

/** Modo demo (sin Supabase en la compilación de depuración): avisa de que nada se guarda. */
@Composable
private fun AvisoDemo() {
    Text(
        "Modo demo: los datos no se guardan y se pierden al cerrar la app.",
        Modifier.fillMaxWidth().background(Stm.colors.errorContainer).statusBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp),
        color = Stm.colors.onErrorContainer,
        style = StmType.bodySmall,
        textAlign = TextAlign.Center,
    )
}

/** Día que muestra el diseño. */
private val CAPTURE_DAY: LocalDate = LocalDate.of(2026, 11, 5)

/** Datos de muestra del diseño, solo en memoria: Ana y Leo comparten hogar y entra Ana. */
private suspend fun seedSample(backend: Backend, finance: FinanceService) {
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

    val categories = finance.categories(home.id)
    val comida = finance.createCategory(BudgetCategory("", home.id, "Comida", CategoryKind.Expense, BudgetGroup.Needs, "cart"))
    fun cat(name: String) = categories.first { it.name == name }.id
    // Saldos iniciales para que el total y cada cuenta den las cifras del diseño.
    val main = finance.createAccount(AccountDraft("Cuenta principal", AccountKind.Checking, 341258L - 114_475L - 27_000L), home.id)
    val card = finance.createAccount(AccountDraft("Tarjeta compartida", AccountKind.CreditCard), home.id)
    val visa = finance.createAccount(AccountDraft("Visa", AccountKind.CreditCard, -31200L + 19_835L), home.id)
    val cash = finance.createAccount(AccountDraft("Efectivo", AccountKind.Cash, 4_519_362L + 1_620L), home.id)
    val sample = listOf(
        MovementDraft(card.id, comida.id, CAPTURE_DAY, -6420, "Supermercado Día"),
        MovementDraft(cash.id, comida.id, CAPTURE_DAY, -380, "Panadería La Espiga"),
        MovementDraft(visa.id, comida.id, CAPTURE_DAY.minusDays(1), -8235, "Mercadona"),
        MovementDraft(cash.id, comida.id, CAPTURE_DAY.minusDays(1), -1240, "Frutería Lola"),
        MovementDraft(visa.id, comida.id, CAPTURE_DAY.minusDays(2), -5600, "Restaurante Sol"),
        MovementDraft(visa.id, cat("Transporte"), CAPTURE_DAY.minusDays(3), -6000, "Repsol"),
        MovementDraft(main.id, cat("Suministros"), CAPTURE_DAY.minusDays(2), -6120, "Luz"),
        MovementDraft(main.id, cat("Vivienda"), CAPTURE_DAY.minusDays(4), -85000, "Alquiler"),
        MovementDraft(main.id, cat("Compras"), CAPTURE_DAY.minusDays(4), -9405, "Compras varias"),
        MovementDraft(main.id, cat("Otros ingresos"), CAPTURE_DAY.minusDays(4), 27000, "Bizum familia"),
        MovementDraft(main.id, cat("Nómina"), CAPTURE_DAY.minusDays(4), 215000, "Nómina"),
    )
    sample.forEach { finance.addMovement(it, home.id) }
    val serie = RecurringSeries("", home.id, "", amountMinor = 0, startsOn = "", remindDaysBefore = 2)
    listOf(
        serie.copy(name = "Alquiler", kind = RecurringKind.Essential, amountMinor = 85_000, startsOn = "2026-12-01"),
        serie.copy(name = "Streaming", amountMinor = 1_299, startsOn = "2026-12-08", introMinor = 599, introCharges = 3),
        serie.copy(name = "Gimnasio", amountMinor = 3_990, startsOn = "2026-12-10"),
        serie.copy(name = "Agua", kind = RecurringKind.Essential, amountMinor = 4_210, startsOn = "2026-12-15", every = 2),
        serie.copy(name = "Nómina", kind = RecurringKind.Income, amountMinor = 215_000, startsOn = "2026-12-01"),
    ).forEach { finance.createRecurring(it) }
    val fondo = finance.createGoal(Goal("", home.id, "Fondo de emergencia", targetMinor = 600_000, startingMinor = 315_000, monthlyPlanMinor = 30_000))
    finance.createGoal(Goal("", home.id, "Viaje a Lisboa", targetMinor = 120_000, startingMinor = 78_000, targetOn = "2027-06-30"))
    finance.createGoal(Goal("", home.id, "Préstamo del coche", GoalKind.Debt, targetMinor = 900_000, startingMinor = 410_000, monthlyPlanMinor = 27_300))
    finance.addContribution(GoalContribution("", home.id, fondo.id, 30_000, "2026-11-01", "Mensual"))
    finance.addContribution(GoalContribution("", home.id, fondo.id, 15_000, "2026-10-15", "Extra"))
    finance.saveBudget(
        Budget(home.id, YearMonth.from(CAPTURE_DAY), expectedIncome = 240_000, limits = mapOf(comida.id to 45_000, categories.first { it.name == "Ocio" }.id to 20_000)),
    )
}
