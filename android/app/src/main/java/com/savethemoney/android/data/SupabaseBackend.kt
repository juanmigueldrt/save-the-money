package com.savethemoney.android.data

import com.russhwolf.settings.Settings
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.time.Instant

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

    override suspend fun currentUserId(): String? {
        client.auth.awaitInitialization()
        return client.auth.currentUserOrNull()?.id
    }

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
        client.from("households").select(Columns.raw(HOUSEHOLD)) { order("created_at", Order.ASCENDING) }.decodeList()
    }

    override suspend fun createHousehold(name: String): Household = mapped {
        client.postgrest.rpc("create_household", buildJsonObject { put("household_name", name) }).decodeAs()
    }

    override suspend fun members(householdId: String): List<HouseholdMember> = mapped {
        val memberships = client.from("household_members").select(Columns.raw("id,household_id,user_id,role")) {
            filter { eq("household_id", householdId) }
        }.decodeList<Membership>()
        if (memberships.isEmpty()) return@mapped emptyList()
        val profiles = client.from("profiles").select(Columns.raw(PROFILE)) {
            filter { isIn("id", memberships.map { it.userId }) }
        }.decodeList<Profile>().associateBy { it.id }
        memberships.mapNotNull { m -> profiles[m.userId]?.let { HouseholdMember(it, m.role) } }
    }

    override suspend fun pendingInvites(householdId: String): List<HouseholdInvite> = mapped {
        client.from("household_invites").select(Columns.raw(INVITE)) {
            filter {
                eq("household_id", householdId)
                eq("status", "pending")
                gt("expires_at", Instant.now().toString())
            }
            order("created_at", Order.DESCENDING)
        }.decodeList()
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
            "STM04" -> AppError.TooManyInviteAttempts(Regex("""retry in (\d+) min""").find(message)?.groupValues?.get(1)?.toInt() ?: 15)
            else -> AppError.Unknown(code ?: "postgrest")
        }

        fun authError(raw: String): AppError {
            val text = raw.lowercase()
            return when {
                "invalid login credentials" in text || "invalid_credentials" in text -> AppError.InvalidCredentials
                "already registered" in text || "user_already_exists" in text || "duplicate key" in text -> AppError.UsernameTaken
                "weak_password" in text || "password should be" in text -> AppError.WeakPassword
                "session" in text && ("missing" in text || "not found" in text) -> AppError.NotSignedIn
                else -> AppError.Unknown("auth")
            }
        }
    }
}
