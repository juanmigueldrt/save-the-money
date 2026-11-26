package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

/** Cambiar la contraseña con la sesión abierta (ORC-57), sobre el backend en memoria. Datos inventados. */
class ChangePasswordTest {
    private val ana = Username.parse("ana").getOrThrow()

    private fun signedIn() = InMemoryBackend().also { runBlocking { it.signUp(ana, "contrasena-de-prueba", null) } }

    @Test
    fun cambiaLaContrasenaYLaSesionSigueAbierta() = runBlocking {
        val backend = signedIn()
        val id = backend.currentUserId()
        backend.changePassword("contrasena-de-prueba", "otra-contrasena-1")
        assertEquals(id, backend.currentUserId())

        backend.signOut()
        assertEquals(AppError.InvalidCredentials, runCatching { backend.signIn(ana, "contrasena-de-prueba") }.exceptionOrNull())
        assertEquals(id, backend.signIn(ana, "otra-contrasena-1"))
    }

    @Test
    fun laActualIncorrectaNoCambiaNadaNiCierraLaSesion() = runBlocking {
        val backend = signedIn()
        val id = backend.currentUserId()
        val error = runCatching { backend.changePassword("no-es-esta", "otra-contrasena-1") }.exceptionOrNull()
        assertEquals(AppError.WrongCurrentPassword, error)
        assertEquals("La contraseña actual no es correcta.", error?.message)
        assertEquals(id, backend.currentUserId())

        backend.signOut()
        assertEquals(id, backend.signIn(ana, "contrasena-de-prueba"))
    }

    @Test
    fun laNuevaSigueLaReglaDelRegistro() = runBlocking {
        val backend = signedIn()
        assertEquals(AppError.WeakPassword, runCatching { backend.changePassword("contrasena-de-prueba", "123456789") }.exceptionOrNull())
        val igual = runCatching { backend.changePassword("contrasena-de-prueba", "contrasena-de-prueba") }.exceptionOrNull()
        assertEquals(ChangePasswordForm.SAME_PASSWORD, igual?.message)
    }

    @Test
    fun sinSesionNoSePuede() = runBlocking {
        val backend = signedIn()
        backend.signOut()
        assertEquals(AppError.NotSignedIn, runCatching { backend.changePassword("contrasena-de-prueba", "otra-contrasena-1") }.exceptionOrNull())
    }

    @Test
    fun losErroresDelServidorNoDicenMasQueAntes() {
        // Mensajes reales de Supabase Auth (internal/api/user.go y el limitador de peticiones).
        assertEquals(
            ChangePasswordForm.SAME_PASSWORD,
            SupabaseBackend.authError("same_password New password should be different from the old password.").message,
        )
        assertEquals(AppError.TooManyAttempts, SupabaseBackend.authError("over_request_rate_limit Request rate limit reached"))
        assertEquals(AppError.WeakPassword, SupabaseBackend.authError("weak_password Password should be at least 10 characters."))
    }
}
