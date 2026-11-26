package com.savethemoney.android.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.time.Duration
import java.time.Instant
import java.util.UUID

/** Registro, sesión, perfil, hogares e invitaciones (AuthService + HouseholdService de iOS). */
interface Backend {
    suspend fun currentUserId(): String?

    /** Avisa cuando la sesión se pierde sin que la persona la cierre (p. ej. el servidor rechaza el refresco). */
    val sessionEnded: Flow<Unit> get() = emptyFlow()
    suspend fun signUp(username: Username, password: String, displayName: String?): String
    suspend fun signIn(username: Username, password: String): String

    /**
     * Cambia la contraseña de quien tiene la sesión abierta, que sigue abierta en este dispositivo.
     * Comprueba antes la actual: si no es, lanza [AppError.WrongCurrentPassword] y no cambia nada.
     */
    suspend fun changePassword(currentPassword: String, newPassword: String)
    suspend fun signOut()

    suspend fun myProfile(): Profile
    suspend fun updateProfile(displayName: String?, theme: AppTheme): Profile
    suspend fun households(): List<Household>
    suspend fun createHousehold(name: String): Household
    suspend fun members(householdId: String): List<HouseholdMember>
    suspend fun pendingInvites(householdId: String): List<HouseholdInvite>
    suspend fun createInvite(householdId: String): HouseholdInvite
    suspend fun revokeInvite(inviteId: String)
    suspend fun acceptInvite(code: InviteCode): Household
    suspend fun leave(householdId: String)
    /** Cambia el nombre del hogar. Sólo puede quien lo creó. */
    suspend fun renameHousehold(householdId: String, name: String): Household
    /**
     * Cambia el día en que empieza el mes del hogar ([MONTH_START_DAYS]). Sólo puede quien lo creó.
     * No toca ningún dato guardado: solo cambia qué días cuentan en cada mes de presupuestos e informes.
     */
    suspend fun setMonthStartDay(householdId: String, day: Int): Household
    /** Solo el dueño del hogar puede quitar a otro miembro. */
    suspend fun removeMember(householdId: String, userId: String)
}

const val HOUSEHOLD_NAME_ISSUE = "El nombre del hogar tiene que tener entre 1 y 80 letras."

/** Días en que puede empezar el mes del hogar: del 1 al 28, que existen en todos los meses (igual que el servidor). */
val MONTH_START_DAYS = 1..28
const val MONTH_START_DAY_ISSUE = "El mes del hogar puede empezar entre el día 1 y el 28."
const val MONTH_START_DAY_OWNER_ONLY = "Solo quien creó el hogar puede cambiar el día en que empieza el mes."

// OffsetDateTime y no Instant.parse: el servidor manda «+00:00», que Instant.parse solo entiende desde Android 14.
// Si la fecha no se entiende, la invitación no vale.
fun HouseholdInvite.isUsable(now: Instant = Instant.now()): Boolean =
    status == InviteStatus.Pending &&
        runCatching { java.time.OffsetDateTime.parse(expiresAt).toInstant().isAfter(now) }.getOrDefault(false)

/**
 * Modo demo (sin clave de Supabase), capturas y pruebas: todo en memoria, se pierde al cerrar.
 * Imita las reglas del servidor (códigos de 48 horas y de un solo uso).
 * shortcut: sin bloqueo entre hilos; la app solo lo llama desde el hilo principal.
 */
class InMemoryBackend(private val now: () -> Instant = Instant::now) : Backend {
    private class UserRecord(var profile: Profile, var password: String)

    private val users = mutableMapOf<String, UserRecord>()
    private val householdsById = mutableMapOf<String, Household>()
    private val memberships = mutableListOf<Membership>()
    private val invites = mutableListOf<HouseholdInvite>()
    private var currentUser: String? = null

    private fun id() = UUID.randomUUID().toString()
    private fun requireUser() = currentUser ?: throw AppError.NotSignedIn
    private fun isMember(user: String, household: String) = memberships.any { it.userId == user && it.householdId == household }

    override suspend fun currentUserId() = currentUser

    override suspend fun signUp(username: Username, password: String, displayName: String?): String {
        if (users.values.any { it.profile.username == username.value }) throw AppError.UsernameTaken
        if (password.length < SignUpForm.MIN_PASSWORD) throw AppError.WeakPassword
        val profile = Profile(id(), username.value, displayName)
        users[profile.id] = UserRecord(profile, password)
        currentUser = profile.id
        return profile.id
    }

    override suspend fun signIn(username: Username, password: String): String {
        val account = users.values.firstOrNull { it.profile.username == username.value && it.password == password }
            ?: throw AppError.InvalidCredentials
        currentUser = account.profile.id
        return account.profile.id
    }

    // Como el servidor: la sesión sigue abierta; una actual que no es no cambia nada.
    override suspend fun changePassword(currentPassword: String, newPassword: String) {
        val record = users[requireUser()] ?: throw AppError.NotSignedIn
        if (record.password != currentPassword) throw AppError.WrongCurrentPassword
        if (newPassword.length < SignUpForm.MIN_PASSWORD) throw AppError.WeakPassword
        if (newPassword == currentPassword) throw AppError.InvalidInput(ChangePasswordForm.SAME_PASSWORD)
        record.password = newPassword
    }

    override suspend fun signOut() { currentUser = null }

    override suspend fun myProfile(): Profile = users[requireUser()]?.profile ?: throw AppError.NotSignedIn

    override suspend fun updateProfile(displayName: String?, theme: AppTheme): Profile {
        val record = users[requireUser()] ?: throw AppError.NotSignedIn
        record.profile = record.profile.copy(displayName = displayName, theme = theme)
        return record.profile
    }

    override suspend fun households(): List<Household> {
        val user = requireUser()
        return memberships.filter { it.userId == user }.mapNotNull { householdsById[it.householdId] }
    }

    override suspend fun createHousehold(name: String): Household {
        val user = requireUser()
        val valid = validHouseholdName(name) ?: throw AppError.Unknown("nombre")
        val household = Household(id(), valid)
        householdsById[household.id] = household
        memberships += Membership(id(), household.id, user, MemberRole.Owner)
        setDefaultIfMissing(user, household.id)
        return household
    }

    override suspend fun renameHousehold(householdId: String, name: String): Household {
        val user = requireUser()
        if (memberships.none { it.userId == user && it.householdId == householdId && it.role == MemberRole.Owner }) {
            throw AppError.InvalidInput("Solo quien creó el hogar puede cambiarle el nombre.")
        }
        val valid = validHouseholdName(name) ?: throw AppError.InvalidInput(HOUSEHOLD_NAME_ISSUE)
        val household = householdsById[householdId]?.copy(name = valid) ?: throw AppError.Unknown("hogar")
        householdsById[householdId] = household
        return household
    }

    override suspend fun setMonthStartDay(householdId: String, day: Int): Household {
        val user = requireUser()
        if (memberships.none { it.userId == user && it.householdId == householdId && it.role == MemberRole.Owner }) {
            throw AppError.InvalidInput(MONTH_START_DAY_OWNER_ONLY)
        }
        if (day !in MONTH_START_DAYS) throw AppError.InvalidInput(MONTH_START_DAY_ISSUE)
        val household = householdsById[householdId]?.copy(monthStartDay = day) ?: throw AppError.Unknown("hogar")
        householdsById[householdId] = household
        return household
    }

    override suspend fun members(householdId: String): List<HouseholdMember> {
        val user = requireUser()
        if (!isMember(user, householdId)) return emptyList()
        return memberships.filter { it.householdId == householdId }
            .mapNotNull { m -> users[m.userId]?.let { HouseholdMember(it.profile, m.role) } }
    }

    override suspend fun pendingInvites(householdId: String): List<HouseholdInvite> {
        val user = requireUser()
        if (!isMember(user, householdId)) return emptyList()
        return invites.filter { it.householdId == householdId && it.isUsable(now()) }
    }

    override suspend fun createInvite(householdId: String): HouseholdInvite {
        val user = requireUser()
        if (!isMember(user, householdId)) throw AppError.Unknown("no es miembro")
        var code: String
        do {
            code = String(CharArray(InviteCode.LENGTH) { InviteCode.ALPHABET.random() })
        } while (invites.any { it.code == code })
        val invite = HouseholdInvite(id(), householdId, code, expiresAt = now().plus(Duration.ofHours(48)).toString())
        invites += invite
        return invite
    }

    override suspend fun revokeInvite(inviteId: String) {
        val user = requireUser()
        val i = invites.indexOfFirst { it.id == inviteId }
        if (i < 0 || !isMember(user, invites[i].householdId) || invites[i].status != InviteStatus.Pending) return
        invites[i] = invites[i].copy(status = InviteStatus.Revoked)
    }

    override suspend fun acceptInvite(code: InviteCode): Household {
        val user = requireUser()
        val i = invites.indexOfFirst { it.code == code.value }
        val household = invites.getOrNull(i)?.takeIf { it.isUsable(now()) }?.let { householdsById[it.householdId] }
            ?: throw AppError.InvalidOrExpiredInvite
        if (isMember(user, household.id)) throw AppError.AlreadyMember
        memberships += Membership(id(), household.id, user, MemberRole.Member)
        invites[i] = invites[i].copy(status = InviteStatus.Accepted)
        setDefaultIfMissing(user, household.id)
        return household
    }

    override suspend fun leave(householdId: String) {
        val user = requireUser()
        memberships.removeAll { it.userId == user && it.householdId == householdId }
        users[user]?.let { if (it.profile.defaultHouseholdId == householdId) it.profile = it.profile.copy(defaultHouseholdId = null) }
    }

    override suspend fun removeMember(householdId: String, userId: String) {
        val user = requireUser()
        if (memberships.none { it.userId == user && it.householdId == householdId && it.role == MemberRole.Owner }) {
            throw AppError.InvalidInput("Solo quien creó el hogar puede quitar a alguien.")
        }
        memberships.removeAll { it.userId == userId && it.householdId == householdId }
        users[userId]?.let { if (it.profile.defaultHouseholdId == householdId) it.profile = it.profile.copy(defaultHouseholdId = null) }
    }

    private fun setDefaultIfMissing(user: String, household: String) {
        users[user]?.let { if (it.profile.defaultHouseholdId == null) it.profile = it.profile.copy(defaultHouseholdId = household) }
    }
}
