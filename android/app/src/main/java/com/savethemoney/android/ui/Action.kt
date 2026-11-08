package com.savethemoney.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

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
                error = AppError.Unknown("app").message
            } finally {
                busy = false
            }
        }
    }
}

@Composable
fun rememberAction(): Action {
    val scope = rememberCoroutineScope()
    return remember { Action(scope) }
}
