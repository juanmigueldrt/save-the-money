package com.savethemoney.android.data

import com.russhwolf.settings.Settings
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Servicios sobre Supabase. Toda la seguridad la pone el servidor (RLS y funciones);
 * aquí solo se llama a la API y se traducen los errores. La sesión la guarda [SesionCifrada].
 */
class SupabaseBackend(url: String, anonKey: String) : Backend {
    val client: SupabaseClient = createSupabaseClient(url, anonKey) {
        install(Auth) {
            // Mismo archivo de preferencias que usaba supabase-kt; la sesión en claro de antes se migra al arrancar.
            val ajustes = Settings()
            sessionManager = SesionCifrada(ajustes, SettingsSessionManager(ajustes, SesionCifrada.claveAntigua(url)))
        }
        install(Postgrest)
    }

    override suspend fun currentUserId(): String? = client.auth.usuarioConSesion()

    // supabase-kt borra la sesión si el servidor rechaza el refresco (y al cerrar sesión): la app vuelve al login.
    override val sessionEnded: Flow<Unit> = client.auth.sessionStatus.filterIsInstance<SessionStatus.NotAuthenticated>().map { }

    override suspend fun signUp(username: Username, password: String, displayName: String?): String = mapped {
        client.auth.signUpWith(Email) {
            email = username.authEmail
            this.password = password
            data = buildJsonObject {
                put("username", username.value)
                if (displayName != null) put("display_name", displayName)
            }
        }
        userId()
    }

    override suspend fun signIn(username: Username, password: String): String = mapped {
        client.auth.signInWith(Email) {
            email = username.authEmail
            this.password = password
        }
        userId()
    }

    /*
     * supabase-kt 3.2.6 no envía current_password y el proyecto puede pedir un inicio de sesión reciente
     * («secure password change»). Por eso se vuelve a iniciar sesión con la actual: la comprueba (con el
     * límite de intentos del servidor) y deja una sesión nueva con la que el cambio vale con ese ajuste
     * encendido o apagado. Si la actual no es, supabase-kt no toca la sesión guardada (solo la borra con
     * session_not_found). Tras el cambio, el servidor cierra todas las demás sesiones de la cuenta.
     */
    override suspend fun changePassword(currentPassword: String, newPassword: String) = mapped {
        val email = client.auth.currentUserOrNull()?.email ?: throw AppError.NotSignedIn
        try {
            client.auth.signInWith(Email) {
                this.email = email
                password = currentPassword
            }
        } catch (e: RestException) {
            val error = authError(listOfNotNull(e.error, e.description, e.message).joinToString(" "))
            throw if (error == AppError.InvalidCredentials) AppError.WrongCurrentPassword else error
        }
        client.auth.updateUser { password = newPassword }
        Unit
    }

    // supabase-kt 3.2.6 solo borra la sesión local si la llamada al servidor sale bien:
    // sin red quedaría guardada y la app volvería a entrar sola.
    override suspend fun signOut() = mapped {
        try {
            client.auth.signOut()
        } finally {
            client.auth.clearSession()
        }
    }

    private fun userId(): String = client.auth.currentUserOrNull()?.id ?: throw AppError.NotSignedIn

    override suspend fun myProfile(): Profile = mapped {
        client.from("profiles").select(Columns.raw(PROFILE)) { filter { eq("id", userId()) } }.decodeSingle()
    }

    override suspend fun updateProfile(displayName: String?, theme: AppTheme): Profile = mapped {
        client.from("profiles").update(buildJsonObject {
            // null explícito para poder borrar el nombre visible
            put("display_name", displayName)
            put("theme", theme.name.lowercase())
        }) {
            select(Columns.raw(PROFILE))
            filter { eq("id", userId()) }
        }.decodeSingle()
    }

    override suspend fun households(): List<Household> = mapped {
        allPages { from, to ->
            client.from("households").select(Columns.raw(HOUSEHOLD)) {
                order("created_at", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Household>()
        }
    }

    override suspend fun createHousehold(name: String): Household = mapped {
        client.postgrest.rpc("create_household", buildJsonObject { put("household_name", name) }).decodeAs()
    }

    override suspend fun members(householdId: String): List<HouseholdMember> = mapped {
        val memberships = allPages { from, to ->
            client.from("household_members").select(Columns.raw("id,household_id,user_id,role")) {
                filter { eq("household_id", householdId) }
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Membership>()
        }
        if (memberships.isEmpty()) return@mapped emptyList()
        val profiles = allPages { from, to ->
            client.from("profiles").select(Columns.raw(PROFILE)) {
                filter { isIn("id", memberships.map { it.userId }) }
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Profile>()
        }.associateBy { it.id }
        memberships.mapNotNull { m -> profiles[m.userId]?.let { HouseholdMember(it, m.role) } }
    }

    override suspend fun pendingInvites(householdId: String): List<HouseholdInvite> = mapped {
        val now = Instant.now().toString()
        allPages { from, to ->
            client.from("household_invites").select(Columns.raw(INVITE)) {
                filter {
                    eq("household_id", householdId)
                    eq("status", "pending")
                    gt("expires_at", now)
                }
                order("created_at", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<HouseholdInvite>()
        }
    }

    override suspend fun createInvite(householdId: String): HouseholdInvite = mapped {
        client.postgrest.rpc("create_invite", buildJsonObject { put("target_household", householdId) }).decodeAs()
    }

    override suspend fun revokeInvite(inviteId: String) = mapped {
        client.from("household_invites").update(buildJsonObject { put("status", "revoked") }) {
            filter { eq("id", inviteId) }
        }
        Unit
    }

    // Un código que no sirve devuelve null en vez de un error, para que el servidor guarde el intento fallido.
    override suspend fun acceptInvite(code: InviteCode): Household = mapped {
        client.postgrest.rpc("accept_invite", buildJsonObject { put("invite_code", code.value) })
            .takeUnless { it.data.trim() == "null" }
            ?.decodeAs<Household>()
    } ?: throw AppError.InvalidOrExpiredInvite

    override suspend fun leave(householdId: String) = mapped {
        client.from("household_members").delete {
            filter {
                eq("household_id", householdId)
                eq("user_id", userId())
            }
        }
        Unit
    }

    override suspend fun renameHousehold(householdId: String, name: String): Household {
        val valid = validHouseholdName(name) ?: throw AppError.InvalidInput(HOUSEHOLD_NAME_ISSUE)
        // RLS: sólo el dueño puede actualizar; si no lo es, no vuelve ninguna fila.
        val rows = mapped {
            client.from("households").update(buildJsonObject { put("name", valid) }) {
                select(Columns.raw(HOUSEHOLD))
                filter { eq("id", householdId) }
            }.decodeList<Household>()
        }
        return rows.firstOrNull() ?: throw AppError.InvalidInput("Solo quien creó el hogar puede cambiarle el nombre.")
    }

    override suspend fun setMonthStartDay(householdId: String, day: Int): Household {
        if (day !in MONTH_START_DAYS) throw AppError.InvalidInput(MONTH_START_DAY_ISSUE)
        // RLS: sólo el dueño puede actualizar; si no lo es, no vuelve ninguna fila.
        val rows = mapped {
            client.from("households").update(buildJsonObject { put("month_start_day", day) }) {
                select(Columns.raw(HOUSEHOLD))
                filter { eq("id", householdId) }
            }.decodeList<Household>()
        }
        return rows.firstOrNull() ?: throw AppError.InvalidInput(MONTH_START_DAY_OWNER_ONLY)
    }

    override suspend fun removeMember(householdId: String, userId: String) = mapped {
        // Sin permiso, RLS no borra nada y no da error: se pide la fila borrada para saberlo.
        val removed = client.from("household_members").delete {
            select(Columns.raw("id"))
            filter {
                eq("household_id", householdId)
                eq("user_id", userId)
            }
        }.decodeList<kotlinx.serialization.json.JsonObject>()
        if (removed.isEmpty()) throw AppError.InvalidInput("Solo quien creó el hogar puede quitar a alguien.")
    }

    /** Convierte cualquier error en un AppError con mensaje en español. Nunca registra datos del usuario. */
    internal suspend fun <T> mapped(block: suspend () -> T): T = try {
        block()
    } catch (e: AppError) {
        throw e
    } catch (e: PostgrestRestException) {
        throw postgresError(e.code, e.message ?: "")
    } catch (e: RestException) {
        throw authError(listOfNotNull(e.error, e.description, e.message).joinToString(" "))
    } catch (e: HttpRequestException) {
        throw AppError.Network
    } catch (e: IOException) {
        throw AppError.Network
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        // Respuesta inesperada (un valor de enumerado nuevo, una fila que falta…): se avisa en vez de cerrar la app.
        throw AppError.Unknown("app")
    }

    companion object {
        private const val PROFILE = "id,username,display_name,theme,default_household_id"
        private const val HOUSEHOLD = "id,name,base_currency,month_start_day"
        private const val INVITE = "id,household_id,code,status,expires_at"

        fun postgresError(code: String?, message: String): AppError = when (code) {
            "P0002" -> AppError.InvalidOrExpiredInvite
            "23505" -> when {
                "already a member" in message -> AppError.AlreadyMember
                "categories_household_name_idx" in message -> AppError.InvalidInput("Ya hay una categoría con ese nombre.")
                // profiles.username es único: Postgres nombra la restricción en el mensaje.
                "profiles_username_key" in message -> AppError.UsernameTaken
                else -> AppError.InvalidInput("Ya hay un registro igual guardado. Revisa el formulario.")
            }
            "28000", "PGRST301" -> AppError.NotSignedIn
            "23503", "23514", "22P02" -> AppError.InvalidInput("Algún dato no es válido. Revisa el formulario.")
            // create_transfer: la transferencia ya estaba guardada con otra cuenta, otro importe u otro día.
            "STM01" -> AppError.InvalidInput(TransferDraft.STORED_WITH_OTHER_DATA)
            // El trigger de investment_trades: la posición quedaría en negativo en alguna fecha.
            "STM02" -> AppError.InvalidInput(InvestmentTrade.NOT_ENOUGH_SHARES)
            "STM03" -> AppError.InvalidInput(InvestmentTrade.NEEDED_BY_LATER_SALE)
            // accept_invite: demasiados códigos fallidos; el mensaje acaba en «retry in N min».
            // update_movement: el movimiento cambió (o se borró) después de leerlo.
            "STM05" -> AppError.MovementChanged
            "STM04" -> AppError.TooManyInviteAttempts(Regex("""retry in (\d+) min""").find(message)?.groupValues?.get(1)?.toInt() ?: 15)
            // El trigger de households: no se cambia base_currency con importes guardados.
            "STM06" -> AppError.InvalidInput(Money.BASE_CURRENCY_LOCKED)
            // Transferencias: la otra pata no se pudo cambiar o borrar a la vez.
            "STM07" -> AppError.InvalidInput(TransferDraft.OTHER_LEG_LOCKED)
            else -> AppError.Unknown(code ?: "postgrest")
        }

        fun authError(raw: String): AppError {
            val text = raw.lowercase()
            return when {
                "invalid login credentials" in text || "invalid_credentials" in text -> AppError.InvalidCredentials
                "already registered" in text || "user_already_exists" in text || "duplicate key" in text -> AppError.UsernameTaken
                // Antes que «password should be»: el mensaje de same_password también lo contiene.
                "same_password" in text || "should be different from the old" in text ->
                    AppError.InvalidInput(ChangePasswordForm.SAME_PASSWORD)
                "weak_password" in text || "password should be" in text -> AppError.WeakPassword
                "over_request_rate_limit" in text || "rate limit" in text -> AppError.TooManyAttempts
                "session" in text && ("missing" in text || "not found" in text) -> AppError.NotSignedIn
                else -> AppError.Unknown("auth")
            }
        }
    }
}

/** Filas por petición: el servidor devuelve como mucho 1000 (`max_rows` en supabase/config.toml). */
internal const val PAGE_SIZE = 1000

/**
 * Todas las filas de una consulta, pedidas por páginas. [page] recibe la primera y la última fila (incluidas)
 * y debe ordenar por una clave única (`id` al final) para que las páginas no salten ni repitan filas.
 * Un error en cualquier página hace fallar la carga entera: nunca se devuelve una lista a medias.
 */
internal suspend fun <T> allPages(page: suspend (from: Long, to: Long) -> List<T>): List<T> {
    val all = mutableListOf<T>()
    while (true) {
        val rows = page(all.size.toLong(), all.size + PAGE_SIZE - 1L)
        all += rows
        if (rows.size < PAGE_SIZE) return all
    }
}

/**
 * Usuario de la sesión guardada; nulo si no hay o el servidor la rechazó.
 * Lo comprobado en supabase-kt 3.2.6 (AuthImpl): con el token caducado y sin red, la sesión sigue guardada
 * pero el estado queda en RefreshFailure (o en Initializing mientras aún no ha caducado) y se reintenta cada
 * 10 s; si el servidor rechaza el refresco (4xx) borra la sesión y pasa a NotAuthenticated.
 * Sin red se lanza AppError.Network para enseñar «sin conexión» sin perder la sesión.
 */
internal suspend fun Auth.usuarioConSesion(espera: Duration = 10.seconds): String? {
    val antes = sessionStatus.value
    // Al pulsar «Reintentar» no se espera al siguiente reintento de la librería: se vuelve a refrescar ya.
    if (antes is SessionStatus.RefreshFailure) loadFromStorage()
    val estado = withTimeoutOrNull(espera) {
        sessionStatus.first { it !is SessionStatus.Initializing && !(antes is SessionStatus.RefreshFailure && it === antes) }
    }
    return when (estado) {
        is SessionStatus.Authenticated -> estado.session.user?.id
        is SessionStatus.NotAuthenticated -> null
        else -> throw AppError.Network
    }
}
