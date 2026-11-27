package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime

/** Hay sesión guardada pero no se ha podido cargar: aviso y «Reintentar», sin pedir entrar otra vez. */
@Composable
fun SinConexion(message: String) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    StmScreen {
        Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(message, style = StmType.bodyLarge, color = c.onSurface, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            Btn(stringResource(R.string.comun_reintentar), { action.run { session.start() } }, Modifier.fillMaxWidth(), large = true, enabled = !action.busy)
            Spacer(Modifier.height(8.dp))
            // Salida por si el fallo no se arregla reintentando.
            Btn(stringResource(R.string.acceso_cerrar_sesion), { action.run { session.signOut() } }, kind = BtnKind.Text, enabled = !action.busy)
        }
    }
}

/** Enlace de invitación con un hogar ya abierto: pregunta antes de unirse; nunca se une solo. */
@Composable
fun BoxScope.UnirseDesdeEnlace() {
    val session = LocalSession.current
    val code = session.pendingInvite ?: return
    val action = rememberAction()
    StmDialog(
        stringResource(R.string.acceso_unirte_a_otro_hogar),
        stringResource(R.string.acceso_con_el_codigo_entraras_en_otro, code.value, session.household?.name.orEmpty()),
        onDismiss = { session.pendingInvite = null },
        actions = {
            Btn(stringResource(R.string.acceso_ahora_no), { session.pendingInvite = null }, kind = BtnKind.Text)
            Btn(stringResource(R.string.tu_hogar_unirme), { action.run { session.join(code) } }, kind = BtnKind.Text, enabled = !action.busy)
        },
    ) { action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = Stm.colors.error) } }
}

/**
 * Horas hasta la caducidad de la invitación. El servidor manda ISO 8601 con desfase y microsegundos
 * («2026-11-26T10:00:00.123456+00:00»); si no se entiende, null y no se muestra nada.
 */
internal fun horasHasta(caduca: String, ahora: Instant = Instant.now()): Long? =
    runCatching { OffsetDateTime.parse(caduca).toInstant() }.getOrNull()
        ?.let { Duration.between(ahora, it).toHours().coerceAtLeast(1) }
