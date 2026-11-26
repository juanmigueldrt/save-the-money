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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Budget
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CardPaymentMode
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalKind
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.MovementForm
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import com.savethemoney.android.ui.screens.ScreenFor
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmTheme
import java.math.BigDecimal
import java.time.LocalDate
import java.time.YearMonth

/**
 * Solo depuración: abre la pantalla N del diseño con datos de muestra, para tools/capturar.sh.
 * adb shell am start -n com.savethemoney.android/.CapturasActivity --ei pantalla 14
 *
 * Usa su propia sesión en memoria, con fecha fija: nunca la del usuario, ni su bloqueo, su vista,
 * sus avisos o el aviso de modo demo. Las pantallas no saben que es una captura.
 */
class CapturasActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val pantalla = capturaPedida(BuildConfig.CAPTURAS, intent.getIntExtra("pantalla", 0))
        if (pantalla == null) {
            finish()
            return
        }
        setContent {
            val dark = isSystemInDarkTheme()
            SideEffect {
                WindowCompat.getInsetsController(window, window.decorView).run {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            StmTheme(dark) {
                CompositionLocalProvider(LocalSession provides sesionCapturas) { Capturas(pantalla) }
            }
        }
    }
}

/** Pantalla que pide el extra de capturas, o nulo si el gancho no va compilado (-Pentrega) o el número no existe. */
internal fun capturaPedida(habilitado: Boolean, extra: Int): Int? = extra.takeIf { habilitado && it in 1..SCREEN_COUNT }

/** Día que muestra el diseño. */
internal val CAPTURE_DAY: LocalDate = LocalDate.of(2026, 11, 5)

/** Una por proceso, como la de StmApp; tools/capturar.sh cierra la app antes de cada pantalla. */
private val sesionCapturas by lazy { sesionDeMuestra() }

internal fun sesionDeMuestra() = Session(InMemoryBackend(), InMemoryFinance(), isDemo = true, today = { CAPTURE_DAY })

@Composable
private fun Capturas(pantalla: Int) {
    val session = LocalSession.current
    val nav = remember { Nav(pantalla) }
    var listo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        seedSample(session)
        session.start()
        session.finance?.let { prepararPantalla(it, pantalla) }
        listo = true
    }
    if (!listo) {
        Box(Modifier.fillMaxSize().background(Stm.colors.surface))
        return
    }
    BackHandler(enabled = nav.canGoBack) { nav.back() }
    AnimatedContent(nav.current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "pantalla") { number ->
        ScreenFor(number, nav)
    }
}

/** Lo que el diseño enseña ya elegido o abierto en cada pantalla, puesto en los modelos como lo haría la app al tocar. */
internal suspend fun prepararPantalla(finance: FinanceModel, pantalla: Int) {
    val primero = finance.recent.first()
    finance.categories.firstOrNull { it.name == "Comida" }?.let { finance.movementFilter = finance.movementFilter.copy(categoryId = it.id) }
    val visa = finance.accounts.first { it.name == "Visa" }
    when (pantalla) {
        5 -> {
            // El aviso «Movimiento eliminado» con «Deshacer».
            finance.add(MovementDraft(finance.activeAccounts.first().id, primero.categoryId, CAPTURE_DAY, -350, "Café"))
            finance.delete(finance.recent.first { it.description == "Café" })
        }
        6 -> finance.selectedAccountId = finance.activeAccounts.first().id
        7 -> finance.movementForm = MovementForm(accountId = primero.accountId, amountMinor = -primero.amountMinor, description = primero.description)
        8, 34 -> finance.tappedMovement = primero
        9 -> finance.newAccountKind = AccountKind.Savings
        11, 12 -> finance.cards.selectedId = visa.id
        13 -> {
            finance.cards.selectedId = visa.id
            finance.cards.purchaseId = finance.recent.first { it.description == "Restaurante Sol" }.id
        }
        21 -> finance.planning.seriesToEdit = finance.planning.series.first { it.name == "Streaming" }
        23 -> finance.planning.selectedGoalId = finance.planning.goals.first().id
        24 -> finance.planning.goalToEdit = finance.planning.goals.first { it.name == "Viaje a Lisboa" }
        26 -> finance.investments.selectedId = finance.investments.holdings.first { it.name == "Fondo indexado mundial" }.id
    }
}

/** Datos de muestra del diseño, solo en memoria: Ana y Leo comparten hogar y entra Ana. */
internal suspend fun seedSample(session: Session) {
    val backend = session.backend
    val finance = session.financeService
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
    val movimientos = sample.map { finance.addMovement(it, home.id) }
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
    // Tarjetas (10–13): la Visa con sus condiciones y el Restaurante Sol aplazado a 3 meses; la compartida con cuota fija.
    finance.saveCreditCard(CreditCardTerms(visa.id, home.id, creditLimit = 300_000, payFromAccountId = main.id))
    finance.saveCreditCard(CreditCardTerms(card.id, home.id, creditLimit = 150_000, paymentMode = CardPaymentMode.Fixed, fixedPayment = 10_000, payFromAccountId = main.id))
    val restaurante = movimientos.first { it.description == "Restaurante Sol" }
    finance.saveInstallment(CardInstallment("", home.id, visa.id, restaurante.id, months = 3, rate = 14.0))
    // Inversiones (25–27): un fondo indexado con su historial de precios y dos aportaciones periódicas, una en pausa.
    val indexado = finance.createHolding(Holding("", home.id, "Fondo indexado mundial", kind = InvestmentKind.Fund))
    val bonos = finance.createHolding(Holding("", home.id, "Fondo de bonos", kind = InvestmentKind.Bond))
    finance.addTrade(InvestmentTrade("", home.id, indexado.id, "2025-11-03", quantity = BigDecimal("112.4"), price = BigDecimal("154.34")))
    listOf("2026-05-04" to "158.10", "2026-07-01" to "163.40", "2026-09-01" to "168.95", "2026-11-04" to "174.85", "2026-11-05" to "176.25")
        .forEach { (dia, precio) -> finance.recordPrice(BigDecimal(precio), LocalDate.parse(dia), indexado.id) }
    finance.createPlan(InvestmentPlan("", home.id, indexado.id, main.id, amountMinor = 30_000, startsOn = "2026-12-01"))
    finance.createPlan(InvestmentPlan("", home.id, bonos.id, main.id, amountMinor = 10_000, startsOn = "2026-11-20", pausedAt = "2026-11-01T00:00:00Z"))
    // Score crediticio (19): tres apuntes del banco.
    listOf("2026-10-15" to 742, "2026-07-15" to 730, "2026-04-15" to 735)
        .forEach { (dia, score) -> finance.addCreditScore(CreditScore("", score, provider = "Informe del banco", recordedOn = dia)) }
}
