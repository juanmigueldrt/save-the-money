package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.MovementsCsv
import com.savethemoney.android.data.RemovedHousehold
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate

/**
 * Hogares de los que te han quitado (ORC-56): hasta cuándo se guardan tus datos y cómo llevártelos.
 * Una tarjeta por hogar, con 16 dp encima; no pinta nada si no hay ninguno.
 */
@Composable
internal fun HogaresAnteriores() {
    LocalSession.current.removedHouseholds.forEach { quitado ->
        key(quitado.householdId) {
            Spacer(Modifier.height(16.dp))
            HogarAnterior(quitado)
        }
    }
}

@Composable
private fun HogarAnterior(quitado: RemovedHousehold) {
    val c = Stm.colors
    val session = LocalSession.current
    val context = LocalContext.current
    val action = rememberAction()
    val hasta = quitado.exportDay()?.let { "${it.dayOfMonth} de ${Fechas.mes(it)} de ${it.year}" } ?: quitado.exportUntil.take(10)
    StmCard {
        Text("Ya no estás en ${quitado.name}", style = StmType.titleMedium, color = c.onSurface)
        Spacer(Modifier.height(8.dp))
        Text(
            "Lo que apuntaste allí se guarda hasta el $hasta y después se borra. Hasta entonces puedes exportar tus movimientos.",
            style = StmType.bodyMedium, color = c.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        // Igual que «CSV para Excel» de Más opciones, con lo que devuelve el servidor a quien ya no es miembro.
        Btn("Exportar mis movimientos (CSV)", {
            action.run {
                val datos = session.backend.removedHouseholdExport(quitado.householdId)
                val fichero = ficheroExportar(context, MovementsCsv.fileName(LocalDate.now()))
                withContext(Dispatchers.IO) { fichero.writeBytes(MovementsCsv.bytes(datos.movements, datos.accounts, datos.categories)) }
                compartir(context, fichero, "text/csv")
            }
        }, Modifier.fillMaxWidth(), kind = BtnKind.Tonal, enabled = !action.busy)
        action.error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
    }
}
