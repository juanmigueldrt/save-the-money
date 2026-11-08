package com.savethemoney.android.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
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
 * aquí solo se llama a la API y se traducen los errores. La sesión la guarda supabase-kt.
 */
class SupabaseBackend(url: String, anonKey: String) : Backend {
    val client: SupabaseClient = createSupabaseClient(url, anonKey) {
        install(Auth)
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

    override suspend fun signOut() = mapped { client.auth.signOut() }

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

    override suspend fun acceptInvite(code: InviteCode): Household = mapped {
        client.postgrest.rpc("accept_invite", buildJsonObject { put("invite_code", code.value) }).decodeAs()
    }

    override suspend fun leave(householdId: String) = mapped {
        client.from("household_members").delete {
            filter {
                eq("household_id", householdId)
                eq("user_id", userId())
            }
        }
        Unit
    }

    /** Convierte cualquier error en un AppError con mensaje en español. Nunca registra datos del usuario. */
    private suspend fun <T> mapped(block: suspend () -> T): T = try {
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
                else -> AppError.UsernameTaken
            }
            "28000", "PGRST301" -> AppError.NotSignedIn
            "23503", "23514", "22P02" -> AppError.InvalidInput("Algún dato no es válido. Revisa el formulario.")
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
