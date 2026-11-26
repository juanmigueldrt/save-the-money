package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.ChangePasswordForm
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.NoNotifier
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.Profile
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.data.Username
import java.time.LocalDate
import kotlinx.coroutines.CancellationException

/** Estado de la sesión: quién ha entrado y en qué hogar está (SessionModel de iOS). */
class Session(
    val backend: Backend,
    val financeService: FinanceService,
    val isDemo: Boolean,
    private val today: () -> LocalDate = LocalDate::now,
    private val notifier: Notifier = NoNotifier,
    /** Borra lo que queda en el dispositivo de la cuenta: exportados y avisos mostrados. */
    private val borrarLocal: () -> Unit = {},
    /** El hogar que eligió cada persona en este dispositivo (id de usuario a id de hogar), en las preferencias. */
    private val hogarElegido: (String) -> String? = { null },
    private val eligeHogar: (String, String) -> Unit = { _, _ -> },
) {
    sealed interface State {
        data object Loading : State
        data object SignedOut : State

        /** Hay sesión guardada pero no se ha podido cargar (sin red o fallo del servidor); el texto es el aviso. */
        data class Offline(val message: String) : State
        data class NeedsHousehold(val profile: Profile) : State
        data class Ready(val profile: Profile, val household: Household) : State
    }

    var state by mutableStateOf<State>(State.Loading)
        private set

    /** Finanzas del hogar abierto; nulo si no hay ninguno. */
    var finance by mutableStateOf<FinanceModel?>(null)
        private set

    /** Código recibido por enlace o QR, pendiente de usar. */
    var pendingInvite by mutableStateOf<InviteCode?>(null)

    /** Los hogares de quien ha entrado, para elegir cuál abrir cuando hay más de uno. */
    var households by mutableStateOf<List<Household>>(emptyList())
        private set

    val profile: Profile? get() = when (val s = state) {
        is State.Ready -> s.profile
        is State.NeedsHousehold -> s.profile
        else -> null
    }
    val household: Household? get() = (state as? State.Ready)?.household

    /** Al abrir la app y en «Reintentar»: el fallo ya queda en el estado. */
    suspend fun start() {
        try {
            refresh()
        } catch (_: AppError) {
            // Ya se ve en el estado: login o «sin conexión».
        }
    }

    /** Cuándo recargó por última vez [resume] (reloj monótono, en ms); nulo si aún no. */
    private var lastResumeLoad: Long? = null

    /**
     * Al volver a primer plano: si se quedó «sin conexión» se reintenta; si no, se recargan las finanzas, como mucho una
     * vez cada [RESUME_INTERVAL_MS] y nunca con otra carga en marcha. [now] es el reloj monótono en ms.
     */
    suspend fun resume(now: Long) {
        if (state is State.Offline) return start()
        val model = finance ?: return
        if (model.isLoading || lastResumeLoad?.let { now - it < RESUME_INTERVAL_MS } == true) return
        lastResumeLoad = now
        model.load()
    }

    companion object {
        /** Lo mínimo entre dos recargas al volver a primer plano. */
        const val RESUME_INTERVAL_MS = 30_000L
    }

    /** Mientras la app está abierta: si la sesión se pierde (el servidor rechaza el refresco), vuelve al login. */
    suspend fun watchSession() {
        backend.sessionEnded.collect {
            if (state == State.Loading || state == State.SignedOut) return@collect
            notifier.replaceReminders(emptyList())
            borrarLocal()
            finance = null
            households = emptyList()
            state = State.SignedOut
            signOutNotice = AppError.NotSignedIn.message
        }
    }

    /**
     * Sólo AppError.NotSignedIn (no hay sesión o el servidor la rechaza) lleva al login.
     * Cualquier otro fallo no descarta la sesión guardada: se lanza como AppError para avisar y,
     * si aún no había un hogar abierto, se pasa a «sin conexión» con reintento.
     */
    suspend fun refresh() {
        signOutNotice = null
        val next = try {
            if (backend.currentUserId() == null) {
                State.SignedOut
            } else {
                val profile = backend.myProfile()
                val homes = backend.households()
                households = homes
                val elegido = hogarElegido(profile.id)
                val home = homes.firstOrNull { it.id == elegido } ?: homes.firstOrNull { it.id == profile.defaultHouseholdId } ?: homes.firstOrNull()
                if (home != null) State.Ready(profile, home) else State.NeedsHousehold(profile)
            }
        } catch (e: AppError.NotSignedIn) {
            State.SignedOut
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Cualquier otro fallo, también uno no previsto, se enseña en vez de cerrar la app.
            val error = e as? AppError ?: AppError.Unknown("app")
            // Con un hogar ya abierto se queda donde estaba; quien llamó enseña el aviso.
            if (state !is State.Ready) state = State.Offline(error.message)
            throw error
        }
        if (next is State.Ready) {
            // Se carga antes de cambiar de estado para que Inicio no aparezca a ceros. Otro día de inicio del mes
            // también da modelos nuevos: presupuestos e informes van por otros periodos.
            if (finance?.household?.id != next.household.id || finance?.household?.monthStartDay != next.household.monthStartDay) {
                finance = FinanceModel(next.household, financeService, today, notifier).also { it.load() }
            }
        } else if (next !is State.Loading) {
            finance = null
        }
        state = next
    }

    suspend fun signIn(username: String, password: String) {
        backend.signIn(Username.parse(username, forSignIn = true).getOrThrow(), password)
        refresh()
    }

    suspend fun signUp(form: SignUpForm) {
        form.firstIssue?.let { throw AppError.InvalidInput(it) }
        backend.signUp(Username.parse(form.username).getOrThrow(), form.password, form.trimmedDisplayName)
        refresh()
    }

    /** La sesión de este dispositivo sigue abierta; el servidor cierra las de los demás. */
    suspend fun changePassword(form: ChangePasswordForm) {
        form.firstIssue?.let { throw AppError.InvalidInput(it) }
        backend.changePassword(form.currentPassword, form.newPassword)
    }

    /** Se guarda en el perfil, así sigue a la persona en sus otros dispositivos. */
    suspend fun setTheme(theme: AppTheme) {
        val actual = profile ?: return
        val nuevo = backend.updateProfile(actual.displayName, theme)
        state = when (val s = state) {
            is State.Ready -> s.copy(profile = nuevo)
            is State.NeedsHousehold -> s.copy(profile = nuevo)
            else -> s
        }
    }

    /** Nombre visible: vacío vuelve al nombre de usuario; como al crear la cuenta, como mucho 60 caracteres. */
    suspend fun setDisplayName(name: String) {
        val actual = profile ?: return
        val nuevo = backend.updateProfile(SignUpForm(displayName = name).trimmedDisplayName, actual.theme)
        state = when (val s = state) {
            is State.Ready -> s.copy(profile = nuevo)
            is State.NeedsHousehold -> s.copy(profile = nuevo)
            else -> s
        }
    }

    /** Si el cierre no llegó al servidor. Este dispositivo ya está desconectado; el aviso se ve en la pantalla de entrar. */
    var signOutNotice by mutableStateOf<String?>(null)
        private set

    suspend fun signOut() {
        signOutNotice = null
        try {
            backend.signOut()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            signOutNotice = "No se ha podido cerrar la sesión en el servidor. " + ((e as? AppError)?.message ?: AppError.Unknown("app").message)
        }
        // Se borra aunque el servidor no haya contestado: el dispositivo ya no es de esa cuenta.
        notifier.replaceReminders(emptyList())
        borrarLocal()
        finance = null
        households = emptyList()
        state = State.SignedOut
    }

    suspend fun createHousehold(name: String) {
        backend.createHousehold(name)
        refresh()
    }

    /** Tras unirse se abre el hogar nuevo; si ya tenía otro, sigue en los dos y puede volver a él con [open]. */
    suspend fun join(code: InviteCode) {
        val joined = backend.acceptInvite(code)
        pendingInvite = null
        profile?.let { eligeHogar(it.id, joined.id) }
        refresh()
    }

    /**
     * Abre otro de sus hogares y lo recuerda en este dispositivo. Las finanzas son nuevas y se cargan antes de
     * cambiar de estado: nada del hogar anterior se ve con el nuevo.
     */
    suspend fun open(household: Household) {
        val s = state as? State.Ready ?: return
        if (s.household.id == household.id || households.none { it.id == household.id }) return
        eligeHogar(s.profile.id, household.id)
        refresh()
    }

    /** Sólo el dueño. No cambia ningún dato guardado: las finanzas se rehacen y todo se recalcula con los meses nuevos. */
    suspend fun setMonthStartDay(day: Int) {
        val h = household ?: return
        val updated = backend.setMonthStartDay(h.id, day)
        households = households.map { if (it.id == updated.id) updated else it }
        val s = state
        if (s is State.Ready && s.household.id == updated.id) {
            val nuevo = FinanceModel(updated, financeService, today, notifier).also { it.load() }
            // Si mientras cargaba se abrió otro hogar, no se pisa.
            val ahora = state
            if (ahora is State.Ready && ahora.household.id == updated.id) {
                finance = nuevo
                state = ahora.copy(household = updated)
            }
        }
    }

    /** Sólo el dueño; el nombre nuevo se ve enseguida en la app. */
    suspend fun renameHousehold(household: Household, name: String) {
        val renamed = backend.renameHousehold(household.id, name)
        val s = state
        households = households.map { if (it.id == renamed.id) renamed else it }
        if (s is State.Ready && s.household.id == renamed.id) {
            finance?.household = renamed
            state = s.copy(household = renamed)
        }
    }

    suspend fun leaveHousehold(household: Household) {
        backend.leave(household.id)
        refresh()
    }
}

val LocalSession = staticCompositionLocalOf<Session> { error("Sin sesión") }
