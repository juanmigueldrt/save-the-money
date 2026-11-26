package com.savethemoney.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.registrarError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.reflect.KMutableProperty0

/** Acción de un botón contra el servidor: una a la vez, con el mensaje de error listo para mostrar. */
class Action(private val scope: CoroutineScope) {
    var busy by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)

    fun run(block: suspend () -> Unit) {
        if (busy) return
        scope.launch {
            busy = true
            error = null
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: AppError) {
                error = e.message
            } catch (e: Exception) {
                // Los fallos del servidor ya los registra `mapped`; este no viene de ahí (ORC-72).
                registrarError("Action.run", e)
                error = AppError.Unknown("app").message
            } finally {
                busy = false
            }
        }
    }
}

/**
 * Recarga tras una escritura que ya se ha guardado. Nunca lanza: si fallara, [Action] lo daría por fallo de guardado,
 * el formulario seguiría abierto y «Guardar» otra vez podría duplicar. Devuelve el mensaje del fallo, para que el
 * modelo lo muestre como problema de carga (se reintenta cargando, no guardando).
 */
suspend fun reloadAfterSave(block: suspend () -> Unit): String? = try {
    block()
    null
} catch (e: CancellationException) {
    throw e
} catch (e: AppError) {
    e.message
} catch (e: Exception) {
    registrarError("reloadAfterSave", e)
    AppError.Unknown("app").message
}

/**
 * Una escritura y la recarga de lo que cambia (ORC-142). [reload] no lanza (usa [reloadAfterSave]). Si la escritura falla se
 * recarga igual: puede que otro dispositivo cambiara la fila antes (STM05) o que ya estuviera guardada con otros datos
 * (STM01); así se ve lo que hay detrás del aviso.
 */
suspend fun <T> guardarYRecargar(reload: suspend () -> Unit, write: suspend () -> T): T {
    val saved = try {
        write()
    } catch (e: AppError) {
        reload()
        throw e
    }
    reload()
    return saved
}

/** Padre de las escrituras en marcha: no es de ninguna pantalla, así que salir de una no las cancela. */
internal val escrituras = SupervisorJob()

/**
 * Una escritura y su recarga (ORC-122). Corre fuera de la pantalla que la lanza: si se sale de ella con la petición ya
 * enviada, termina igual y el modelo (que es de la sesión) se recarga. Quien espera sí se cancela, así que lo que la
 * pantalla hiciera después (cerrar, navegar, compartir) ya no ocurre. Sin pantalla, lo guardado queda en el modelo; un
 * fallo de la escritura se entrega a [huerfana] (la pantalla que lo enseñaría ya no está) y uno de la recarga queda en
 * el error del modelo, como siempre.
 */
suspend fun <T> escritura(huerfana: (Exception) -> Unit = {}, block: suspend () -> T): T {
    val pantalla = currentCoroutineContext()
    return CoroutineScope(pantalla.minusKey(Job) + escrituras).async {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Si ya no espera nadie, que no se pierda sin avisar: lo apuntado no se ha guardado.
            if (!pantalla.isActive) huerfana(e)
            throw e
        }
    }.await()
}

/**
 * Cada lectura toma un turno al empezar; lo que trae solo se guarda si nada que empezó después lo ha guardado ya
 * (ReadTurns de iOS, ORC-87). Así una respuesta antigua que llega tarde no pisa una más nueva.
 */
class ReadTurns {
    private var issued = 0L
    private val stored = HashMap<String, Long>()

    /** El turno de una lectura que empieza. */
    @Synchronized
    fun next(): Long = ++issued

    /** true (y lo apunta) si [turn] no es más antiguo que lo último guardado en [slice]. */
    @Synchronized
    private fun claim(slice: String, turn: Long): Boolean {
        if (turn < (stored[slice] ?: 0L)) return false
        stored[slice] = turn
        return true
    }

    /** true si lo leído en el turno [turn] puede guardarse en [slice]: la corrutina sigue viva y nada posterior lo ha guardado. */
    suspend fun mayStore(slice: KMutableProperty0<*>, turn: Long): Boolean = currentCoroutineContext().isActive && claim(slice.name, turn)

    /** Guarda [value] en [slice] si [mayStore] lo permite. */
    suspend fun <T> store(slice: KMutableProperty0<T>, value: T, turn: Long) {
        if (mayStore(slice, turn)) slice.set(value)
    }

    /** Un cambio que el servidor ya ha guardado: se ve ya y las lecturas que empezaron antes no lo pisan. */
    fun <T> changed(slice: KMutableProperty0<T>, value: T) {
        claim(slice.name, next())
        slice.set(value)
    }
}

/**
 * Lo que deja en [error] una carga que falla: el mensaje del [AppError] o el genérico. La cancelación se relanza antes que
 * nada: parar una lectura no es un fallo.
 */
suspend fun ReadTurns.fallaCarga(error: KMutableProperty0<String?>, turn: Long, e: Exception) {
    if (e is CancellationException) throw e
    store(error, (e as? AppError)?.message ?: AppError.Unknown("app").message, turn)
}

@Composable
fun rememberAction(): Action {
    val scope = rememberCoroutineScope()
    return remember { Action(scope) }
}
