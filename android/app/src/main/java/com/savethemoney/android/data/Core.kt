package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Modelos y reglas de Packages/STMCore (iOS), con los mismos nombres de columna que Supabase.

/** Errores con el mensaje en español que ve la persona (AppError de iOS). */
sealed class AppError(override val message: String) : Exception(message) {
    data object InvalidCredentials : AppError("Usuario o contraseña incorrectos.")
    data object UsernameTaken : AppError("Ese nombre de usuario ya existe. Prueba con otro.")
    data object WeakPassword : AppError("La contraseña es demasiado débil. Usa al menos ${SignUpForm.MIN_PASSWORD} caracteres.")
    data object NotSignedIn : AppError("Tu sesión ha caducado. Vuelve a iniciar sesión.")
    data object InvalidOrExpiredInvite : AppError("Ese código no es válido o ha caducado. Pide uno nuevo.")
    data object AlreadyMember : AppError("Ya formas parte de ese hogar.")
    data object Network : AppError("No hay conexión. Inténtalo de nuevo en un momento.")
    class InvalidInput(text: String) : AppError(text)
    class Unknown(val code: String) : AppError("Algo ha fallado. Inténtalo de nuevo.")
}

/**
 * Nombre de usuario. Supabase Auth necesita un email, así que cada usuario se registra con uno
 * sintético que nunca recibe correo (el dominio `.invalid` está reservado).
 */
@JvmInline
value class Username private constructor(val value: String) {
    val authEmail: String get() = "$value@$AUTH_EMAIL_DOMAIN"

    enum class Issue(val message: String) {
        TooShort("El usuario necesita al menos 3 caracteres."),
        TooLong("El usuario puede tener como mucho 30 caracteres."),
        InvalidCharacters("Usa solo letras sin tilde, números, punto, guion o guion bajo."),
    }

    companion object {
        const val AUTH_EMAIL_DOMAIN = "savethemoney.invalid"
        private val allowed = ('a'..'z').toSet() + ('0'..'9') + setOf('.', '_', '-')

        /** Normaliza (minúsculas, sin espacios alrededor) y valida; devuelve el problema si lo hay. */
        fun parse(raw: String): Result<Username> {
            val v = raw.trim().lowercase()
            val issue = when {
                v.length < 3 -> Issue.TooShort
                v.length > 30 -> Issue.TooLong
                !v.all { it in allowed } -> Issue.InvalidCharacters
                else -> return Result.success(Username(v))
            }
            return Result.failure(AppError.InvalidInput(issue.message))
        }
    }
}

/** Código para unirse a un hogar, como "4K9Q2X". Lo genera el servidor. */
@JvmInline
value class InviteCode private constructor(val value: String) {
    /** Enlace que codifica el QR. */
    val link: String get() = "$SCHEME://unirse/$value"

    companion object {
        /** Sin 0/O ni 1/I/L para que no se confundan al dictarlo. */
        const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        const val LENGTH = 6
        const val SCHEME = "savethemoney"

        /** Acepta "4k9 q2x", "4K9-Q2X" o un enlace `savethemoney://unirse/4K9Q2X`. */
        fun parse(raw: String): InviteCode? {
            var text = raw.trim()
            if (text.startsWith("$SCHEME://")) text = text.substringAfterLast('/')
            val cleaned = text.uppercase().filter { !it.isWhitespace() && it != '-' }
            return if (cleaned.length == LENGTH && cleaned.all { it in ALPHABET }) InviteCode(cleaned) else null
        }
    }
}

/** Validación del formulario de crear cuenta, antes de llamar al servidor. */
data class SignUpForm(
    val username: String = "",
    val displayName: String = "",
    val password: String = "",
    val passwordConfirmation: String = "",
) {
    /** Primer problema que impide enviar el formulario, o null si está bien. */
    val firstIssue: String?
        get() = Username.parse(username).exceptionOrNull()?.message
            ?: if (password.length < MIN_PASSWORD) "La contraseña necesita al menos $MIN_PASSWORD caracteres."
            else if (password != passwordConfirmation) "Las contraseñas no coinciden."
            else null

    val trimmedDisplayName: String? get() = displayName.trim().take(60).ifEmpty { null }

    companion object { const val MIN_PASSWORD = 10 }
}

/** Nombre del hogar: entre 1 y 80 caracteres, sin espacios alrededor. */
fun validHouseholdName(raw: String): String? = raw.trim().takeIf { it.length in 1..80 }

@Serializable
enum class AppTheme(val title: String) {
    @SerialName("system") System("Automático"),
    @SerialName("light") Light("Claro"),
    @SerialName("dark") Dark("Oscuro"),
}

@Serializable
data class Household(
    val id: String,
    val name: String,
    @SerialName("base_currency") val baseCurrency: String = "EUR",
    @SerialName("month_start_day") val monthStartDay: Int = 1,
)

@Serializable
data class Profile(
    val id: String,
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    val theme: AppTheme = AppTheme.System,
    @SerialName("default_household_id") val defaultHouseholdId: String? = null,
) {
    /** Nombre para mostrar: el visible si lo hay, si no el de usuario. */
    val name: String get() = displayName?.takeIf { it.isNotEmpty() } ?: username
}

@Serializable
enum class MemberRole { @SerialName("owner") Owner, @SerialName("member") Member }

@Serializable
data class Membership(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("user_id") val userId: String,
    val role: MemberRole,
)

data class HouseholdMember(val profile: Profile, val role: MemberRole)

@Serializable
enum class InviteStatus { @SerialName("pending") Pending, @SerialName("accepted") Accepted, @SerialName("revoked") Revoked }

@Serializable
data class HouseholdInvite(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val code: String,
    val status: InviteStatus = InviteStatus.Pending,
    /** ISO 8601, como lo devuelve Postgres. */
    @SerialName("expires_at") val expiresAt: String,
)
