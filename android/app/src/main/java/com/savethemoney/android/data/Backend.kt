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

    /**
     * Borra la cuenta de quien tiene la sesión abierta y todo lo que apuntó, en todos sus hogares (ORC-74).
     * No se puede deshacer. Comprueba antes la contraseña: si no es, lanza [AppError.WrongCurrentPassword] y no borra nada.
     */
    suspend fun deleteAccount(currentPassword: String)
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
    /**
     * Sale del hogar y borra todo lo que esa persona apuntó en él (ORC-56). No se puede deshacer.
     * El dueño no puede salir mientras haya otros miembros; cuando sale el último, el hogar se borra (ORC-59).
     */
    suspend fun leave(householdId: String)
    /** Cambia el nombre del hogar. Sólo puede quien lo creó. */
    suspend fun renameHousehold(householdId: String, name: String): Household
    /**
     * Cambia el día en que empieza el mes del hogar ([MONTH_START_DAYS]). Sólo puede quien lo creó.
     * No toca ningún dato guardado: solo cambia qué días cuentan en cada mes de presupuestos e informes.
     */
    suspend fun setMonthStartDay(householdId: String, day: Int): Household
    /** Solo el dueño del hogar puede quitar a otro miembro. Sus datos se guardan [RemovedHousehold.EXPORT_DAYS] días. */
    suspend fun removeMember(householdId: String, userId: String)
    /** Traspasa el hogar a otro miembro, que pasa a ser el dueño; quien lo era queda como miembro. Sólo puede el dueño (ORC-59). */
    suspend fun transferHousehold(householdId: String, userId: String)
    /** Los hogares de los que han quitado a quien tiene la sesión y de los que aún puede exportar. */
    suspend fun removedHouseholds(): List<RemovedHousehold>
    /** Sus datos de uno de esos hogares. Fuera de plazo, o si no le quitaron de ese hogar, falla. */
    suspend fun removedHouseholdExport(householdId: String): RemovedHouseholdExport
}

// Los avisos de borrar la cuenta, salir, traspasar y quitar a un miembro son texto de pantalla: están en strings.xml (ORC-110).

/** El propietario no puede salir con otros miembros dentro: el hogar se quedaría sin nadie que lo gestione. */
const val OWNER_MUST_TRANSFER = "Eres el propietario. Antes de salir, haz propietario a otro miembro o quita a los demás."

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

    /** A quién han quitado de qué hogar y cuándo, como `private.removed_members` en el servidor. */
    private data class Removal(val householdId: String, val userId: String)
    private val removals = mutableMapOf<Removal, Instant>()

    /** Donde están los datos de los hogares: [InMemoryFinance] se apunta aquí al crearse con este backend. */
    internal var finance: InMemoryFinance? = null
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

    /** Como `delete_my_account` en el servidor, con lo que hacen sus claves foráneas y los triggers de ORC-56 y ORC-59. */
    override suspend fun deleteAccount(currentPassword: String) {
        val user = requireUser()
        if (users[user]?.password != currentPassword) throw AppError.WrongCurrentPassword
        for (mine in memberships.filter { it.userId == user }) {
            memberships -= mine
            finance?.purgeData(user, mine.householdId)
            // El hogar no se queda sin propietario: pasa al miembro más antiguo.
            val next = memberships.indexOfFirst { it.householdId == mine.householdId }
            if (mine.role == MemberRole.Owner && next >= 0) memberships[next] = memberships[next].copy(role = MemberRole.Owner)
            deleteHouseholdIfEmpty(mine.householdId)
        }
        // Lo que guardara de hogares de los que le quitaron.
        for (removal in removals.keys.filter { it.userId == user }) {
            removals -= removal
            finance?.purgeData(user, removal.householdId)
            deleteHouseholdIfEmpty(removal.householdId)
        }
        finance?.purgeUser(user)
        users -= user
        currentUser = null
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
        // Si vuelve dentro del plazo recupera lo suyo; fuera de plazo ya no queda nada.
        purgeExpiredRemovals()
        removals -= Removal(household.id, user)
        invites[i] = invites[i].copy(status = InviteStatus.Accepted)
        setDefaultIfMissing(user, household.id)
        return household
    }

    override suspend fun leave(householdId: String) {
        val user = requireUser()
        val mine = memberships.firstOrNull { it.userId == user && it.householdId == householdId } ?: return
        if (mine.role == MemberRole.Owner && memberships.any { it.householdId == householdId && it.userId != user }) {
            throw AppError.InvalidInput(OWNER_MUST_TRANSFER)
        }
        memberships -= mine
        finance?.purgeData(user, householdId)
        deleteHouseholdIfEmpty(householdId)
        users[user]?.let { if (it.profile.defaultHouseholdId == householdId) it.profile = it.profile.copy(defaultHouseholdId = null) }
    }

    override suspend fun removedHouseholds(): List<RemovedHousehold> {
        val user = requireUser()
        purgeExpiredRemovals()
        return removals.filterKeys { it.userId == user }.entries.sortedByDescending { it.value }.mapNotNull { (removal, at) ->
            householdsById[removal.householdId]?.let { RemovedHousehold(it.id, it.name, exportUntil(at).toString()) }
        }
    }

    override suspend fun removedHouseholdExport(householdId: String): RemovedHouseholdExport {
        val user = requireUser()
        purgeExpiredRemovals()
        if (Removal(householdId, user) !in removals) throw AppError.InvalidInput("Ya no hay datos que exportar de ese hogar.")
        return finance?.exportOf(user, householdId) ?: RemovedHouseholdExport(emptyList(), emptyList(), emptyList())
    }

    private fun exportUntil(removedAt: Instant) = removedAt.plus(Duration.ofDays(RemovedHousehold.EXPORT_DAYS.toLong()))

    /** La purga diaria del servidor, hecha aquí al consultar. */
    private fun purgeExpiredRemovals() {
        val expired = removals.filterValues { exportUntil(it) <= now() }.keys
        expired.forEach { finance?.purgeData(it.userId, it.householdId) }
        removals -= expired
        expired.forEach { deleteHouseholdIfEmpty(it.householdId) }
    }

    /** Sin miembros y sin nadie con plazo para exportar, el hogar ya no es de nadie. */
    private fun deleteHouseholdIfEmpty(householdId: String) {
        if (memberships.any { it.householdId == householdId }) return
        // Aunque el hogar siga por el plazo de alguien, nadie debe entrar ya: no tendría propietario.
        invites.removeAll { it.householdId == householdId }
        if (removals.keys.any { it.householdId == householdId }) return
        householdsById -= householdId
    }

    override suspend fun transferHousehold(householdId: String, userId: String) {
        val user = requireUser()
        val mine = memberships.indexOfFirst { it.userId == user && it.householdId == householdId && it.role == MemberRole.Owner }
        if (mine < 0) throw AppError.InvalidInput("Solo el propietario puede traspasar el hogar.")
        if (userId == user) return
        val theirs = memberships.indexOfFirst { it.userId == userId && it.householdId == householdId }
        if (theirs < 0) throw AppError.InvalidInput("Esa persona no es miembro del hogar.")
        memberships[theirs] = memberships[theirs].copy(role = MemberRole.Owner)
        memberships[mine] = memberships[mine].copy(role = MemberRole.Member)
    }

    override suspend fun removeMember(householdId: String, userId: String) {
        val user = requireUser()
        if (memberships.none { it.userId == user && it.householdId == householdId && it.role == MemberRole.Owner }) {
            throw AppError.InvalidInput("Solo quien creó el hogar puede quitar a alguien.")
        }
        // Como el trigger del servidor: borrar la fila propia es salir, no ser quitado.
        if (userId == user) return leave(householdId)
        if (!memberships.removeAll { it.userId == userId && it.householdId == householdId }) return
        removals[Removal(householdId, userId)] = now()
        users[userId]?.let { if (it.profile.defaultHouseholdId == householdId) it.profile = it.profile.copy(defaultHouseholdId = null) }
    }

    private fun setDefaultIfMissing(user: String, household: String) {
        users[user]?.let { if (it.profile.defaultHouseholdId == null) it.profile = it.profile.copy(defaultHouseholdId = household) }
    }
}
