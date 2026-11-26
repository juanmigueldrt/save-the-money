package com.savethemoney.android.data

import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.MemoryCodeVerifierCache
import io.github.jan.supabase.auth.MemorySessionManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserInfo
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.createSupabaseClient
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread
import kotlin.time.Clock
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime

/**
 * Lo que hace supabase-kt 3.2.6 de verdad con una sesión guardada cuyo token ya caducó,
 * contra un servidor local (sin red, rechazo o refresco correcto). Sin dispositivo ni Supabase real.
 */
@OptIn(ExperimentalTime::class)
class SesionSupabaseTest {
    private var servidor: ServerSocket? = null

    @After
    fun cerrar() {
        servidor?.close()
    }

    private val usuario = UserInfo(aud = "authenticated", id = "usuario-de-prueba")
    private val caducada = UserSession(
        accessToken = "token-caducado",
        refreshToken = "token-refresco-de-prueba",
        expiresIn = 3600,
        tokenType = "bearer",
        user = usuario,
        expiresAt = Clock.System.now() - 1.hours,
    )

    private fun cliente(url: String, guardada: UserSession?) = createSupabaseClient(url, "clave-anonima-de-prueba") {
        install(Auth) {
            sessionManager = MemorySessionManager(guardada)
            codeVerifierCache = MemoryCodeVerifierCache()
            // En la app los pone Android (ProcessLifecycleOwner); aquí no hay proceso Android.
            enableLifecycleCallbacks = false
        }
    }.auth

    /** Servidor de Auth local que responde siempre al refresco con [estado] y [cuerpo]. */
    private fun servidorAuth(estado: Int, cuerpo: String): String {
        val s = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
        servidor = s
        thread(isDaemon = true) {
            while (!s.isClosed) {
                val conexion = try { s.accept() } catch (_: IOException) { break }
                conexion.use { c ->
                    val entrada = c.getInputStream().bufferedReader()
                    var largo = 0
                    while (true) {
                        val linea = entrada.readLine() ?: break
                        if (linea.isEmpty()) break
                        if (linea.startsWith("Content-Length:", ignoreCase = true)) largo = linea.substringAfter(':').trim().toInt()
                    }
                    repeat(largo) { entrada.read() }
                    val bytes = cuerpo.toByteArray()
                    val cabecera = "HTTP/1.1 $estado X\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                    c.getOutputStream().apply {
                        write(cabecera.toByteArray())
                        write(bytes)
                        flush()
                    }
                }
            }
        }
        return "http://127.0.0.1:${s.localPort}"
    }

    private fun puertoSinServidor(): Int = ServerSocket(0).use { it.localPort }

    @Test
    fun tokenCaducadoSinRedConservaLaSesionYAvisaSinConexion() = runBlocking {
        val auth = cliente("http://127.0.0.1:${puertoSinServidor()}", caducada)
        try {
            auth.usuarioConSesion()
            fail("sin red no debería dar la sesión por perdida")
        } catch (e: AppError.Network) {
            // Se enseña «sin conexión» con reintento.
        }
        assertTrue("la librería deja ${auth.sessionStatus.value}", auth.sessionStatus.value is SessionStatus.RefreshFailure)
        assertEquals(caducada.refreshToken, auth.sessionManager.loadSession()?.refreshToken)

        // «Reintentar» sigue sin red: vuelve a avisar, no lleva al login.
        try {
            auth.usuarioConSesion()
            fail("sin red no debería dar la sesión por perdida")
        } catch (e: AppError.Network) {
            // Igual que antes.
        }
    }

    @Test
    fun refrescoRechazadoPorElServidorLlevaAlLogin() = runBlocking {
        val url = servidorAuth(400, """{"error":"invalid_grant","error_description":"Invalid Refresh Token: Refresh Token Not Found"}""")
        val auth = cliente(url, caducada)

        assertNull(auth.usuarioConSesion())
        assertTrue(auth.sessionStatus.value is SessionStatus.NotAuthenticated)
        assertNull(auth.sessionManager.loadSession())
    }

    @Test
    fun refrescoCorrectoEntraConLaSesionNueva() = runBlocking {
        val url = servidorAuth(
            200,
            """{"access_token":"token-nuevo","refresh_token":"refresco-nuevo","expires_in":3600,"token_type":"bearer",""" +
                """"user":{"aud":"authenticated","id":"usuario-de-prueba"}}""",
        )
        val auth = cliente(url, caducada)

        assertEquals("usuario-de-prueba", auth.usuarioConSesion())
        assertEquals("token-nuevo", auth.currentAccessTokenOrNull())
    }

    @Test
    fun sinSesionGuardadaNoHayUsuario() = runBlocking {
        val auth = cliente("http://127.0.0.1:${puertoSinServidor()}", null)
        assertNull(auth.usuarioConSesion(5.seconds))
    }
}
