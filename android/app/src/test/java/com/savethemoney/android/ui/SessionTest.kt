package com.savethemoney.android.ui

import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.data.Username
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SessionTest {
    @Test
    fun signOutWithoutNetworkEndsSignedOut() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        // Como SupabaseBackend: borra la sesión local aunque falle la llamada al servidor.
        val offline = object : Backend by memory {
            override suspend fun signOut() {
                try {
                    throw AppError.Network
                } finally {
                    memory.signOut()
                }
            }
        }
        val session = Session(offline, InMemoryFinance(), isDemo = true)
        session.refresh()

        session.signOut()

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(offline.currentUserId())
        session.refresh()
        assertEquals(Session.State.SignedOut, session.state)
    }

    /** Como SupabaseBackend sin red: la sesión sigue guardada pero las llamadas de datos fallan. */
    private class SinRed(val memory: InMemoryBackend) : Backend by memory {
        var offline = false
        var failProfile = false
        override suspend fun myProfile() = if (offline || failProfile) throw AppError.Network else memory.myProfile()
        override suspend fun households() = if (offline) throw AppError.Network else memory.households()
    }

    @Test
    fun arrancarSinRedConSesionMuestraSinConexionYReintenta() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        val backend = SinRed(memory).apply { offline = true }
        val session = Session(backend, InMemoryFinance(), isDemo = true)

        session.start()
        assertEquals(Session.State.Offline(AppError.Network.message), session.state)
        assertEquals(memory.currentUserId(), backend.currentUserId())

        backend.offline = false
        session.start()
        val ready = session.state
        assertTrue("al volver la red debería entrar, no $ready", ready is Session.State.Ready)
        assertEquals("Casa de prueba", (ready as Session.State.Ready).household.name)
    }

    @Test
    fun falloAlCargarTrasCrearHogarSeAvisa() = runBlocking {
        val memory = InMemoryBackend()
        val backend = SinRed(memory)
        val session = Session(backend, InMemoryFinance(), isDemo = true)
        session.signUp(SignUpForm(username = "ana", password = "secreto123", passwordConfirmation = "secreto123"))

        backend.failProfile = true
        try {
            session.createHousehold("Casa de prueba")
            fail("debería avisar del fallo")
        } catch (e: AppError.Network) {
            // Se avisa a quien pulsó el botón.
        }
        assertEquals(Session.State.Offline(AppError.Network.message), session.state)
    }

    @Test
    fun falloAlCargarTrasEntrarSeAvisa() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.signOut()
        val backend = SinRed(memory).apply { offline = true }
        val session = Session(backend, InMemoryFinance(), isDemo = true)
        session.start()
        assertEquals(Session.State.SignedOut, session.state)

        try {
            session.signIn("ana", "secreto123")
            fail("debería avisar del fallo")
        } catch (e: AppError.Network) {
            // Se avisa en el formulario de entrar.
        }
        assertEquals(Session.State.Offline(AppError.Network.message), session.state)
    }

    @Test
    fun sesionRechazadaLlevaAlLogin() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        val rechazada = object : Backend by memory {
            override suspend fun myProfile() = throw AppError.NotSignedIn
        }
        val session = Session(rechazada, InMemoryFinance(), isDemo = true)
        session.start()
        assertEquals(Session.State.SignedOut, session.state)
    }
}
