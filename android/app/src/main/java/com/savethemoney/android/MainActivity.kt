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
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.SupabaseBackend
import com.savethemoney.android.data.SupabaseFinance
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmTheme
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

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

    /** Al volver a la app, lo que haya apuntado la pareja. */
    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { session.finance?.load() }
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
        Session(backend, finance, isDemo = demo, capture = capture, today = today).also { session = it }
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
    finance.saveBudget(
        Budget(home.id, YearMonth.from(CAPTURE_DAY), expectedIncome = 240_000, limits = mapOf(comida.id to 45_000, categories.first { it.name == "Ocio" }.id to 20_000)),
    )
}
