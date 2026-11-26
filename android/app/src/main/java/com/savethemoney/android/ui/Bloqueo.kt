package com.savethemoney.android.ui

import android.app.KeyguardManager
import android.content.Context
import android.content.SharedPreferences
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/**
 * Bloqueo de la app con huella, cara o el código del dispositivo (AppLock en iOS). Se guarda sólo
 * en este dispositivo y viene apagado. Protege la pantalla, no los datos.
 * Único sitio donde vive el estado; el diálogo del sistema lo pide MainActivity.
 */
class Bloqueo {
    private var prefs: SharedPreferences? = null

    /** Lo que ha elegido la persona en Más. */
    var activo by mutableStateOf(false)
        private set
    var bloqueada by mutableStateOf(false)
        private set
    private var fueraDesde: Long? = null
    private var arranque = true
    private var autenticando = false

    /** Enlaces que llegaron con la app bloqueada: se hacen al desbloquear. */
    private val pendientes = mutableListOf<() -> Unit>()

    /** `seguro`: el dispositivo tiene código. Se llama al crear la actividad, antes de pintar nada. */
    fun load(prefs: SharedPreferences, seguro: Boolean) {
        this.prefs = prefs
        arranca(prefs.getBoolean(KEY, false), seguro)
    }

    /** Al arrancar el proceso, si está activado, la app sale ya bloqueada: no se ve nada ni un instante. */
    internal fun arranca(activo: Boolean, seguro: Boolean) {
        this.activo = activo
        if (arranque) bloqueada = activo && seguro
    }

    fun activar(on: Boolean) {
        activo = on
        if (!on) abrir()
        prefs?.edit { putBoolean(KEY, on) }
    }

    /** La app deja de verse. El diálogo del sistema no cuenta como salir. */
    fun alSalir(ahora: Long) {
        if (fueraDesde == null && !autenticando) fueraDesde = ahora
    }

    /** La app vuelve a verse. `seguro`: el dispositivo tiene código. Devuelve si hay que pedir desbloqueo. */
    fun alVolver(ahora: Long, seguro: Boolean): Boolean {
        val desde = fueraDesde
        fueraDesde = null
        val pedir = activo && seguro && (arranque || debeBloquear(true, desde, ahora))
        arranque = false
        if (pedir) bloqueada = true
        // Nunca deja fuera: si ya no hay código en el dispositivo, se abre.
        if (!seguro) abrir()
        return pedir && !autenticando
    }

    /** Hace `accion` ya, o al desbloquear si la app está bloqueada o va a bloquearse al volver. */
    fun cuandoAbierta(ahora: Long, seguro: Boolean, accion: () -> Unit) {
        if (bloqueada || debeBloquear(activo && seguro, fueraDesde, ahora)) pendientes += accion else accion()
    }

    /** Devuelve si hay que lanzar el diálogo del sistema. */
    fun empiezaAutenticar(seguro: Boolean): Boolean {
        if (!seguro) {
            abrir()
            return false
        }
        if (autenticando) return false
        autenticando = true
        return true
    }

    fun terminaAutenticar(ok: Boolean) {
        autenticando = false
        if (ok) abrir()
    }

    private fun abrir() {
        bloqueada = false
        val acciones = pendientes.toList()
        pendientes.clear()
        acciones.forEach { it() }
    }

    companion object {
        /** Tiempo fuera de la app que se perdona antes de volver a pedir desbloqueo. */
        const val GRACIA_MS = 60_000L
        private const val KEY = "bloqueo.activo"

        /** La del proceso: sobrevive a que se recree la actividad. */
        val app = Bloqueo()

        /**
         * Regla del bloqueo. `fueraDesde` nulo: no ha salido de la app. Tiempos de un reloj monótono;
         * si aun así el tiempo va hacia atrás se bloquea: ante la duda, se pide.
         */
        fun debeBloquear(activo: Boolean, fueraDesde: Long?, ahora: Long, gracia: Long = GRACIA_MS): Boolean {
            if (!activo || fueraDesde == null) return false
            val fuera = ahora - fueraDesde
            return fuera < 0 || fuera >= gracia
        }

        /** Hay PIN, patrón o contraseña: sin eso no hay huella ni cara, y el bloqueo dejaría fuera. */
        fun seguro(context: Context): Boolean = context.getSystemService(KeyguardManager::class.java).isDeviceSecure
    }
}

/** Tapa la app bloqueada; el botón vuelve a lanzar el diálogo si se canceló. */
@Composable
fun PantallaBloqueo(desbloquear: () -> Unit) {
    BackHandler {}
    Column(
        Modifier
            .fillMaxSize()
            .background(Stm.colors.surface)
            // Que no pase ningún toque a la app de debajo.
            .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        StmIcon(StmIcons.lock, Stm.colors.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        Text("Save the Money está bloqueada", style = StmType.bodyLarge, color = Stm.colors.onSurface)
        Spacer(Modifier.height(16.dp))
        Btn("Desbloquear", desbloquear)
    }
}

/** Bloque «Seguridad» de Más: interruptor y explicación. */
@Composable
fun AjusteBloqueo() {
    val context = LocalContext.current
    val seguro = remember { Bloqueo.seguro(context) }
    val bloqueo = Bloqueo.app
    ListCard {
        ListHeader("Seguridad")
        ListItem(
            "Pedir huella, cara o código",
            if (seguro || bloqueo.activo) "Al abrir y al volver tras más de un minuto" else "Configura un bloqueo de pantalla en el dispositivo para usarlo",
            leading = { StmIcon(StmIcons.lock, Stm.colors.onSurfaceVariant) },
            trailing = { StmSwitch(bloqueo.activo, if (seguro || bloqueo.activo) bloqueo::activar else null) },
            supportingLines = 2,
            onClick = if (seguro || bloqueo.activo) ({ bloqueo.activar(!bloqueo.activo) }) else null,
        )
    }
    Text(
        "Sólo en este dispositivo. Tapa la app en las apps recientes y no deja hacer capturas de pantalla. " +
            "Protege la pantalla, no los datos: tu hogar los sigue viendo en los suyos.",
        Modifier.padding(start = 16.dp, top = 8.dp),
        style = StmType.bodySmall,
        color = Stm.colors.onSurfaceVariant,
    )
}
