package com.savethemoney.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MonthlyBills
import com.savethemoney.android.ui.CamaraQr
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.escribirPdfPagos
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.YearMonth

/** Pagos del mes (no está en el diseño, sí en iOS): resumen y PDF para compartir o imprimir. */
@Composable
fun Pantalla36(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val c = Stm.colors
    val context = LocalContext.current
    val hoy = finance.today()
    var offset by remember { mutableIntStateOf(0) }
    val mes = YearMonth.from(hoy).plusMonths(offset.toLong())
    val bills = MonthlyBills(finance.planning.series, mes, finance.accounts)
    val action = rememberAction()
    StmScreen(
        topBar = { TopBar("Pagos del mes", onNav = nav::back) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("Este mes", "El mes que viene"), offset, { offset = it })
            StmCard {
                Text("Pagos de ${Fechas.mes(mes.atDay(1))}", style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(bills.total), style = StmType.titleLarge, color = c.onSurface)
                if (offset == 0) {
                    Spacer(Modifier.height(4.dp))
                    Text("Quedan ${Money.format(bills.pending(hoy))} por pagar", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
            if (bills.lines.isEmpty()) {
                Text("No hay pagos fijos este mes. Añádelos en Pagos fijos.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            } else {
                ListCard {
                    bills.lines.forEachIndexed { i, l ->
                        if (i > 0) Divider()
                        ListItem(
                            l.name, listOfNotNull("${l.due.dayOfMonth} de ${Fechas.mes(l.due)}", l.accountName).joinToString(" · "),
                            trailingText = Money.format(l.amount),
                        )
                    }
                }
            }
            Btn(
                "Crear PDF",
                {
                    action.run {
                        val fichero = ficheroExportar(context, bills.fileName)
                        withContext(Dispatchers.IO) { escribirPdfPagos(bills, finance.household.name, hoy, fichero) }
                        compartir(context, fichero, "application/pdf")
                    }
                },
                Modifier.fillMaxWidth(), large = true, enabled = bills.lines.isNotEmpty() && !action.busy,
            )
            Text(
                "Salen los cargos de suscripciones y gastos esenciales de Pagos fijos. El PDF se crea en este dispositivo.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
}

/** Escanear el QR de invitación; al leerlo, vuelve a «Tu hogar» con el código escrito. */
@Composable
fun Pantalla37(nav: Nav) {
    val session = LocalSession.current
    val c = Stm.colors
    val context = LocalContext.current
    var permiso by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var leido by remember { mutableStateOf(false) }
    val pedir = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { concedido ->
        permiso = concedido
        if (!concedido) aviso = "Sin permiso de cámara no se puede escanear. Puedes escribir el código a mano."
    }
    LaunchedEffect(Unit) { if (!permiso) pedir.launch(Manifest.permission.CAMERA) }
    StmScreen(
        topBar = { TopBar("Escanear QR", navIcon = StmIcons.close, onNav = nav::back) },
        scroll = false,
    ) {
        if (permiso && aviso == null) {
            Text("Apunta al QR de tu pareja.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))
            CamaraQr(
                Modifier.fillMaxWidth().weight(1f).padding(bottom = 16.dp),
                onTexto = { texto ->
                    val codigo = InviteCode.parse(texto)
                    if (codigo != null && !leido) {
                        leido = true
                        session.pendingInvite = codigo
                        nav.back()
                    }
                },
                onError = { aviso = "Este dispositivo no tiene cámara trasera. Puedes escribir el código a mano." },
            )
        } else {
            Box(Modifier.fillMaxSize()) {
                aviso?.let { Text(it, style = StmType.bodyMedium, color = c.onSurfaceVariant) }
            }
        }
    }
}
