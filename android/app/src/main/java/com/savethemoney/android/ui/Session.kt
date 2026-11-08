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

/** Estado de la sesión: quién ha entrado y en qué hogar está (SessionModel de iOS). */
class Session(
    val backend: Backend,
    val financeService: FinanceService,
    val isDemo: Boolean,
    /** Modo captura: datos de muestra y fecha fija para comparar con el diseño. */
    val capture: Boolean = false,
    private val today: () -> LocalDate = LocalDate::now,
    private val notifier: Notifier = NoNotifier,
) {
    sealed interface State {
        data object Loading : State
        data object SignedOut : State
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

    suspend fun refresh() {
        if (backend.currentUserId() == null) {
            finance = null
            state = State.SignedOut
            return
        }
        val next = try {
            val profile = backend.myProfile()
            val homes = backend.households()
            val home = homes.firstOrNull { it.id == profile.defaultHouseholdId } ?: homes.firstOrNull()
            if (home != null) State.Ready(profile, home) else State.NeedsHousehold(profile)
        } catch (e: AppError.NotSignedIn) {
            State.SignedOut
        } catch (e: AppError) {
            // Sin conexión con sesión abierta: se queda donde estaba si ya había cargado.
            if (state == State.Loading) State.SignedOut else state
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

    suspend fun signOut() {
        runCatching { backend.signOut() }
        notifier.replaceReminders(emptyList())
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

    suspend fun leaveHousehold(household: Household) {
        backend.leave(household.id)
        refresh()
    }
}

val LocalSession = staticCompositionLocalOf<Session> { error("Sin sesión") }
