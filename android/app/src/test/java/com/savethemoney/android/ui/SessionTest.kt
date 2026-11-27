package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.MONTH_START_DAY_OWNER_ONLY
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.data.Username
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

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

    @Test
    fun signOutBorraLosDatosLocalesAunqueFalleElServidor() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        val offline = object : Backend by memory {
            override suspend fun signOut() {
                try {
                    throw AppError.Network
                } finally {
                    memory.signOut()
                }
            }
        }
        var borrados = 0
        val session = Session(offline, InMemoryFinance(), isDemo = true, borrarLocal = { borrados++ })
        session.refresh()

        session.signOut()

        assertEquals(1, borrados)
    }

    @Test
    fun signOutSinRedAvisaEnLaPantallaDeEntrar() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
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
        assertEquals("No se ha podido cerrar la sesión en el servidor. " + AppError.Network.message, session.signOutNotice)
    }

    @Test
    fun signOutCorrectoNoAvisa() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        val session = Session(memory, InMemoryFinance(), isDemo = true)
        session.refresh()

        session.signOut()

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(session.signOutNotice)
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
    fun errorNoPrevistoAlArrancarSeAvisaSinCerrarLaApp() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        // Como un valor de enumerado nuevo en el servidor que no se sabe leer.
        val raro = object : Backend by memory {
            override suspend fun myProfile() = throw NoSuchElementException("fila que falta")
        }
        val session = Session(raro, InMemoryFinance(), isDemo = true)

        session.start()

        assertEquals(Session.State.Offline(AppError.Unknown("app").message), session.state)
        try {
            session.refresh()
            fail("debería avisar del fallo")
        } catch (e: AppError.Unknown) {
            // Quien pulsó el botón recibe un AppError con mensaje, no la excepción cruda.
        }
    }

    @Test
    fun sinRedAlComprobarLaSesionMuestraSinConexion() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        // Como SupabaseBackend con el token caducado y sin red: la sesión sigue guardada.
        val caducada = object : Backend by memory {
            override suspend fun currentUserId() = throw AppError.Network
        }
        val session = Session(caducada, InMemoryFinance(), isDemo = true)

        session.start()

        assertEquals(Session.State.Offline(AppError.Network.message), session.state)
    }

    @Test
    fun alVolverAPrimerPlanoSinConexionReintenta() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        val backend = SinRed(memory).apply { offline = true }
        val session = Session(backend, InMemoryFinance(), isDemo = true)
        session.start()
        assertEquals(Session.State.Offline(AppError.Network.message), session.state)

        backend.offline = false
        session.resume(now = 0)

        assertTrue("al volver la red debería entrar, no ${session.state}", session.state is Session.State.Ready)
    }

    @Test
    fun sesionPerdidaConLaAppAbiertaVuelveAlLogin() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        val perdida = MutableSharedFlow<Unit>()
        val backend = object : Backend by memory {
            override val sessionEnded = perdida
        }
        val session = Session(backend, InMemoryFinance(), isDemo = true)
        session.start()
        assertTrue(session.state is Session.State.Ready)

        val vigilancia = launch { session.watchSession() }
        yield()
        perdida.emit(Unit)
        yield()
        vigilancia.cancel()

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(session.finance)
        assertEquals(AppError.NotSignedIn.message, session.signOutNotice)
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

    // ORC-112: día de inicio del mes, nombre visible, elegir hogar y unirse con un hogar abierto.

    /** Ana tiene su hogar y entra además en el de Bea con una invitación de Bea. El hogar elegido se guarda en [elegidos]. */
    private suspend fun anaConDosHogares(memory: InMemoryBackend, finance: InMemoryFinance, elegidos: MutableMap<String, String>): Session {
        memory.signUp(Username.parse("bea").getOrThrow(), "secreto123", null)
        val deBea = memory.createHousehold("Casa de Bea")
        val invite = memory.createInvite(deBea.id)
        memory.signOut()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de Ana")
        val session = Session(memory, finance, isDemo = true, hogarElegido = { elegidos[it] }, eligeHogar = { u, h -> elegidos[u] = h })
        session.refresh()
        session.join(InviteCode.parse(invite.code)!!)
        return session
    }

    @Test
    fun cambiarElDiaDeInicioRehaceLasFinanzasSinTocarMovimientos() = runBlocking {
        val memory = InMemoryBackend()
        val finance = InMemoryFinance(memory)
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        val casa = memory.createHousehold("Casa")
        val cuenta = finance.createAccount(AccountDraft("Corriente"), casa.id)
        finance.addMovement(MovementDraft(cuenta.id, bookedOn = LocalDate.of(2026, 11, 20), amountMinor = -4_250, description = "Compra"), casa.id)
        val antes = finance.movements(casa.id, null, 100)
        val session = Session(memory, finance, isDemo = true)
        session.refresh()
        val anterior = session.finance!!

        session.setMonthStartDay(25)

        val nuevo = session.finance!!
        assertNotSame(anterior, nuevo)
        assertEquals(25, nuevo.household.monthStartDay)
        assertEquals(25, nuevo.budgets.household.monthStartDay)
        assertEquals(25, session.household?.monthStartDay)
        assertEquals(listOf(25), session.households.map { it.monthStartDay })
        assertEquals(antes, finance.movements(casa.id, null, 100))
    }

    @Test
    fun soloElDuenoCambiaElDiaDeInicio() = runBlocking {
        val memory = InMemoryBackend()
        val session = anaConDosHogares(memory, InMemoryFinance(memory), mutableMapOf())
        assertEquals("Casa de Bea", session.household?.name)

        try {
            session.setMonthStartDay(10)
            fail("un miembro no debería poder cambiarlo")
        } catch (e: AppError.InvalidInput) {
            assertEquals(MONTH_START_DAY_OWNER_ONLY, e.message)
        }
        assertEquals(1, session.household?.monthStartDay)
    }

    @Test
    fun nombreVisibleRecortadoYVacioVuelveAlUsuario() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa")
        val session = Session(memory, InMemoryFinance(memory), isDemo = true)
        session.refresh()

        session.setDisplayName("  Ana María  ")
        assertEquals("Ana María", session.profile?.displayName)
        session.setDisplayName("   ")
        assertNull(session.profile?.displayName)
        assertEquals("ana", session.profile?.name)
    }

    @Test
    fun alUnirseConUnHogarAbiertoSeAbreElNuevoYSeSigueEnLosDos() = runBlocking {
        val memory = InMemoryBackend()
        val session = anaConDosHogares(memory, InMemoryFinance(memory), mutableMapOf())

        assertEquals(setOf("Casa de Ana", "Casa de Bea"), session.households.map { it.name }.toSet())
        assertEquals("Casa de Bea", session.household?.name)
        assertEquals(session.household?.id, session.finance?.household?.id)
        assertNull(session.pendingInvite)
    }

    @Test
    fun cambiarDeHogarDaFinanzasNuevasYSeRecuerdaEnElDispositivo() = runBlocking {
        val memory = InMemoryBackend()
        val finance = InMemoryFinance(memory)
        val elegidos = mutableMapOf<String, String>()
        val session = anaConDosHogares(memory, finance, elegidos)
        val deBea = session.household!!
        val deAna = session.households.first { it.id != deBea.id }
        val cuenta = finance.createAccount(AccountDraft("Solo de Bea"), deBea.id)
        val anterior = session.finance!!
        anterior.load()
        assertEquals(listOf(cuenta.id), anterior.accounts.map { it.id })

        session.open(deAna)

        val nuevo = session.finance!!
        assertNotSame(anterior, nuevo)
        assertEquals(deAna.id, session.household?.id)
        assertEquals(deAna.id, nuevo.household.id)
        assertTrue("no debe verse nada del otro hogar", nuevo.accounts.isEmpty())
        // Una carga del hogar anterior que acaba tarde se queda en sus finanzas, que ya no se ven.
        anterior.load()
        assertTrue(session.finance!!.accounts.isEmpty())

        // Otra sesión en el mismo dispositivo abre el que se eligió, no el predeterminado.
        val otra = Session(memory, finance, isDemo = true, hogarElegido = { elegidos[it] })
        otra.refresh()
        assertEquals(deAna.id, otra.household?.id)
    }

    /** ORC-56: si no se puede pedir la lista de hogares de los que te han quitado, se entra igual; al cerrar sesión se borra. */
    @Test
    fun losHogaresAnterioresNoBloqueanLaEntradaYSeBorranAlCerrarSesion() = runBlocking {
        val clave = "secreto123"
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("bea").getOrThrow(), clave, null)
        val bea = memory.myProfile().id
        memory.signUp(Username.parse("ana").getOrThrow(), clave, null)
        val casa = memory.createHousehold("Casa de Ana")
        val codigo = InviteCode.parse(memory.createInvite(casa.id).code)!!
        memory.signIn(Username.parse("bea").getOrThrow(), clave)
        memory.acceptInvite(codigo)
        memory.signIn(Username.parse("ana").getOrThrow(), clave)
        memory.removeMember(casa.id, bea)
        memory.signIn(Username.parse("bea").getOrThrow(), clave)

        // Un servidor que aún no tiene la función, o sin red justo en esa llamada.
        var falla = true
        val backend = object : Backend by memory {
            override suspend fun removedHouseholds() = if (falla) throw AppError.Unknown("PGRST202") else memory.removedHouseholds()
        }
        val session = Session(backend, InMemoryFinance(memory), isDemo = true)
        session.refresh()
        assertTrue(session.state is Session.State.NeedsHousehold)
        assertTrue(session.removedHouseholds.isEmpty())

        falla = false
        session.refresh()
        assertEquals(listOf("Casa de Ana"), session.removedHouseholds.map { it.name })

        session.signOut()
        assertTrue(session.removedHouseholds.isEmpty())
    }

    // ORC-74: borrar la cuenta.

    @Test
    fun borrarLaCuentaConOtraContrasenaDejaLaSesionComoEstaba() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        var borrados = 0
        val session = Session(memory, InMemoryFinance(memory), isDemo = true, borrarLocal = { borrados++ })
        session.refresh()
        val antes = session.state
        assertTrue(antes is Session.State.Ready)

        try {
            session.deleteAccount("no-es-esta")
            fail("con otra contraseña no debería borrar la cuenta")
        } catch (e: AppError.WrongCurrentPassword) {
            // Se avisa junto al campo de la contraseña.
        }

        assertEquals(antes, session.state)
        assertTrue("las finanzas del hogar siguen abiertas", session.finance != null)
        assertEquals(listOf("Casa de prueba"), session.households.map { it.name })
        assertEquals("no se borra nada del dispositivo", 0, borrados)
        assertEquals(session.profile?.id, memory.currentUserId())
    }

    @Test
    fun borrarLaCuentaBorraLoLocalYAcabaSinSesion() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        var borrados = 0
        val session = Session(memory, InMemoryFinance(memory), isDemo = true, borrarLocal = { borrados++ })
        session.refresh()

        session.deleteAccount("secreto123")

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(session.finance)
        assertTrue(session.households.isEmpty())
        assertEquals(1, borrados)
        assertNull(session.signOutNotice)
        assertNull(memory.currentUserId())
        // La cuenta ya no existe: no se puede volver a entrar con ella.
        try {
            session.signIn("ana", "secreto123")
            fail("la cuenta borrada no debería poder entrar")
        } catch (e: AppError.InvalidCredentials) {
            assertEquals(Session.State.SignedOut, session.state)
        }
    }

    /** Como SupabaseBackend: al borrar la sesión guardada, la librería avisa de que ya no hay sesión. No es una sesión caducada. */
    @Test
    fun borrarLaCuentaNoDejaElAvisoDeSesionCaducada() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        val perdida = MutableSharedFlow<Unit>()
        val backend = object : Backend by memory {
            override val sessionEnded = perdida

            override suspend fun deleteAccount(currentPassword: String) {
                memory.deleteAccount(currentPassword)
                perdida.emit(Unit)
                yield()
            }
        }
        val session = Session(backend, InMemoryFinance(memory), isDemo = true)
        session.start()
        val vigilancia = launch { session.watchSession() }
        yield()

        session.deleteAccount("secreto123")
        vigilancia.cancel()

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(session.signOutNotice)
    }
}
