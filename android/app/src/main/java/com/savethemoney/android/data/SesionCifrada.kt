package com.savethemoney.android.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.russhwolf.settings.Settings
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.user.UserSession
import kotlinx.serialization.json.Json
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.coroutines.cancellation.CancellationException

/**
 * Guarda la sesión de supabase-kt cifrada con AES-GCM y una clave de Android Keystore,
 * que nunca sale del dispositivo. Sustituye al guardado por defecto de la librería, que la
 * deja en claro en las preferencias de la app.
 *
 * [antigua] es ese guardado en claro: si al arrancar queda una sesión ahí (versiones
 * anteriores), se pasa una sola vez al almacén cifrado y se borra. Si algo no se puede
 * descifrar (clave perdida, datos corruptos, copia de otro móvil), la sesión se descarta
 * y la app arranca sin sesión: nunca se cae ni vuelve a guardar el token en claro.
 */
class SesionCifrada(
    private val guardado: Settings,
    private val antigua: SessionManager,
    private val clave: () -> SecretKey = ::claveKeystore,
) : SessionManager {
    override suspend fun saveSession(session: UserSession) {
        val cifrada = try {
            cifrar(json.encodeToString(UserSession.serializer(), session))
        } catch (e: Exception) {
            // Sin Keystore la sesión solo vive en memoria: mejor volver a entrar que guardarla en claro.
            guardado.remove(CLAVE)
            return
        }
        guardado.putString(CLAVE, cifrada)
    }

    override suspend fun loadSession(): UserSession? {
        val cifrada = guardado.getStringOrNull(CLAVE) ?: return migrar()
        borrarAntigua()
        return try {
            json.decodeFromString(UserSession.serializer(), descifrar(cifrada))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            guardado.remove(CLAVE)
            null
        }
    }

    override suspend fun deleteSession() {
        guardado.remove(CLAVE)
        borrarAntigua()
    }

    // Primero se guarda cifrada y después se borra la de en claro: si la app se cierra a medias, se repite.
    private suspend fun migrar(): UserSession? {
        val vieja = try {
            antigua.loadSession()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        if (vieja != null) saveSession(vieja)
        borrarAntigua()
        return vieja?.takeIf { guardado.getStringOrNull(CLAVE) != null }
    }

    private suspend fun borrarAntigua() {
        try {
            antigua.deleteSession()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // No impide seguir: se vuelve a intentar en el siguiente arranque.
        }
    }

    // Formato guardado: Base64(IV de 12 bytes + texto cifrado con la etiqueta GCM).
    private fun cifrar(texto: String): String {
        val cipher = Cipher.getInstance(TRANSFORMACION)
        cipher.init(Cipher.ENCRYPT_MODE, clave())
        return Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(texto.toByteArray(Charsets.UTF_8)))
    }

    private fun descifrar(guardada: String): String {
        val bytes = Base64.getDecoder().decode(guardada)
        val cipher = Cipher.getInstance(TRANSFORMACION)
        cipher.init(Cipher.DECRYPT_MODE, clave(), GCMParameterSpec(128, bytes, 0, IV))
        return String(cipher.doFinal(bytes, IV, bytes.size - IV), Charsets.UTF_8)
    }

    companion object {
        const val CLAVE = "sesion-cifrada"
        private const val ALIAS = "sesion-supabase"
        private const val TRANSFORMACION = "AES/GCM/NoPadding"
        private const val IV = 12
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Clave con la que supabase-kt 3.2.6 guardaba la sesión en claro: "sb-" + la URL sin esquema
         * (el cliente se queda con lo que va tras "//"), con "/" y "." cambiados por "-", + "-session".
         * La función de la librería es interna; la prueba comprueba que ambas coinciden.
         */
        fun claveAntigua(url: String): String =
            "sb-" + url.substringAfterLast("//").removeSuffix("/").replace('/', '-').replace('.', '-') + "-session"

        private fun claveKeystore(): SecretKey {
            val almacen = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (almacen.getKey(ALIAS, null) as? SecretKey)?.let { return it }
            val generador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generador.init(
                KeyGenParameterSpec
                    .Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            return generador.generateKey()
        }
    }
}
