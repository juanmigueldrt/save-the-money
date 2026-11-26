package com.savethemoney.android.data

import com.russhwolf.settings.Settings
import io.github.jan.supabase.annotations.SupabaseInternal
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.auth.createDefaultSettingsKey
import io.github.jan.supabase.auth.user.UserSession
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import kotlin.time.ExperimentalTime

// El Keystore de Android no existe en la JVM: aquí la clave AES es de software; el cifrado es el mismo.
@OptIn(ExperimentalTime::class)
class SesionCifradaTest {
    private val sesion = UserSession(accessToken = "token-acceso-de-prueba", refreshToken = "token-refresco-de-prueba", expiresIn = 3600, tokenType = "bearer", user = null)
    private val claveAntigua = "sb-ejemplo-supabase-co-session"

    private fun nuevaClave(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    // Settings en memoria: solo las operaciones de texto que usan SesionCifrada y SettingsSessionManager.
    private fun ajustes(datos: MutableMap<String, String>): Settings =
        Proxy.newProxyInstance(Settings::class.java.classLoader, arrayOf(Settings::class.java)) { _, metodo, args ->
            when (metodo.name) {
                "getStringOrNull" -> datos[args[0] as String]
                "putString" -> datos.put(args[0] as String, args[1] as String).let { }
                "remove" -> datos.remove(args[0] as String).let { }
                "hasKey" -> datos.containsKey(args[0] as String)
                else -> throw UnsupportedOperationException(metodo.name)
            }
        } as Settings

    @OptIn(SupabaseInternal::class)
    @Test
    fun laClaveAntiguaEsLaQueUsabaSupabaseKt() {
        assertEquals("sb-abcd-supabase-co-session", SesionCifrada.claveAntigua("https://abcd.supabase.co"))
        assertEquals("sb-10-0-2-2:54321-session", SesionCifrada.claveAntigua("http://10.0.2.2:54321/"))
        for (url in listOf("https://abcd.supabase.co", "http://10.0.2.2:54321/")) {
            assertEquals(createDefaultSettingsKey(url.split("//").last()) + "-session", SesionCifrada.claveAntigua(url))
        }
    }

    @Test
    fun guardaLaSesionCifradaYLaRecupera() = runBlocking {
        val datos = mutableMapOf<String, String>()
        val clave = nuevaClave()
        SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }.saveSession(sesion)

        val guardada = datos.getValue(SesionCifrada.CLAVE)
        assertFalse(guardada.contains("token-acceso-de-prueba"))
        assertFalse(guardada.contains("token-refresco-de-prueba"))
        assertFalse(datos.containsKey(claveAntigua))
        // Otra instancia (otro arranque) con la misma clave la lee.
        val leida = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }.loadSession()
        assertEquals("token-acceso-de-prueba", leida?.accessToken)
        assertEquals("token-refresco-de-prueba", leida?.refreshToken)
    }

    @Test
    fun migraLaSesionEnClaroDeVersionesAnteriores() = runBlocking {
        val datos = mutableMapOf<String, String>()
        // Así la dejaba supabase-kt con su guardado por defecto.
        SettingsSessionManager(ajustes(datos), claveAntigua).saveSession(sesion)
        assertTrue(datos.getValue(claveAntigua).contains("token-acceso-de-prueba"))

        val clave = nuevaClave()
        val leida = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }.loadSession()

        assertEquals("token-acceso-de-prueba", leida?.accessToken)
        assertFalse(datos.containsKey(claveAntigua))
        assertFalse(datos.getValue(SesionCifrada.CLAVE).contains("token-acceso-de-prueba"))
        // El siguiente arranque ya la lee cifrada.
        val otra = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }.loadSession()
        assertEquals("token-refresco-de-prueba", otra?.refreshToken)
    }

    @Test
    fun siNoSePuedeDescifrarArrancaSinSesion() = runBlocking {
        val datos = mutableMapOf<String, String>()
        SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { nuevaClave() }.saveSession(sesion)

        // Clave distinta: como un Keystore borrado o datos copiados de otro móvil.
        val leida = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { nuevaClave() }.loadSession()

        assertNull(leida)
        assertFalse(datos.containsKey(SesionCifrada.CLAVE))
    }

    @Test
    fun unValorCorruptoNoTumbaLaApp() = runBlocking {
        val datos = mutableMapOf(SesionCifrada.CLAVE to "esto no es base64 ni AES")
        val clave = nuevaClave()

        assertNull(SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }.loadSession())
        assertFalse(datos.containsKey(SesionCifrada.CLAVE))
    }

    @Test
    fun sinClaveNoGuardaNadaEnClaro() = runBlocking {
        val datos = mutableMapOf<String, String>()
        SettingsSessionManager(ajustes(datos), claveAntigua).saveSession(sesion)

        val sinKeystore = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { error("Keystore no disponible") }

        assertNull(sinKeystore.loadSession())
        assertTrue(datos.isEmpty())
        sinKeystore.saveSession(sesion)
        assertTrue(datos.isEmpty())
    }

    @Test
    fun cerrarSesionBorraLaCifradaYLaAntigua() = runBlocking {
        val datos = mutableMapOf<String, String>()
        val clave = nuevaClave()
        val gestor = SesionCifrada(ajustes(datos), SettingsSessionManager(ajustes(datos), claveAntigua)) { clave }
        gestor.saveSession(sesion)
        datos[claveAntigua] = "{}"

        gestor.deleteSession()

        assertTrue(datos.isEmpty())
    }
}
