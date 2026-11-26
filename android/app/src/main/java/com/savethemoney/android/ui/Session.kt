package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.AppError
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
    /** Modo captura: datos de muestra y fecha fija para comparar con el diseño. */
    val capture: Boolean = false,
    private val today: () -> LocalDate = LocalDate::now,
    private val notifier: Notifier = NoNotifier,
    /** Borra lo que queda en el dispositivo de la cuenta: exportados y avisos mostrados. */
    private val borrarLocal: () -> Unit = {},
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

    /** Al volver a primer plano: si se quedó «sin conexión» se reintenta; si no, se recargan las finanzas. */
    suspend fun resume() {
        if (state is State.Offline) start() else finance?.load()
    }

    /** Mientras la app está abierta: si la sesión se pierde (el servidor rechaza el refresco), vuelve al login. */
    suspend fun watchSession() {
        backend.sessionEnded.collect {
            if (state == State.Loading || state == State.SignedOut) return@collect
            notifier.replaceReminders(emptyList())
            borrarLocal()
            finance = null
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
                val home = homes.firstOrNull { it.id == profile.defaultHouseholdId } ?: homes.firstOrNull()
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
            // Se carga antes de cambiar de estado para que Inicio no aparezca a ceros.
            if (finance?.household?.id != next.household.id) {
                finance = FinanceModel(next.household, financeService, today, notifier).also { it.load() }
            }
        } else if (next !is State.Loading) {
            finance = null
        }
        state = next
    }

    suspend fun signIn(username: String, password: String) {
        backend.signIn(Username.parse(username).getOrThrow(), password)
        refresh()
    }

    suspend fun signUp(form: SignUpForm) {
        form.firstIssue?.let { throw AppError.InvalidInput(it) }
        backend.signUp(Username.parse(form.username).getOrThrow(), form.password, form.trimmedDisplayName)
        refresh()
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
        state = State.SignedOut
    }

    suspend fun createHousehold(name: String) {
        backend.createHousehold(name)
        refresh()
    }

    suspend fun join(code: InviteCode) {
        backend.acceptInvite(code)
        pendingInvite = null
        refresh()
    }

    /** Sólo el dueño; el nombre nuevo se ve enseguida en la app. */
    suspend fun renameHousehold(household: Household, name: String) {
        val renamed = backend.renameHousehold(household.id, name)
        val s = state
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
