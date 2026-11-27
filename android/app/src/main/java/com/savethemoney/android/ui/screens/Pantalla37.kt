package com.savethemoney.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.savethemoney.android.R
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.ui.CamaraQr
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.launch

/** Escanear el QR de invitación; al leerlo, vuelve a «Tu hogar» con el código escrito. */
@Composable
fun Pantalla37(nav: Nav) {
    val session = LocalSession.current
    val c = Stm.colors
    val context = LocalContext.current
    val resources = LocalResources.current
    var permiso by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var leido by remember { mutableStateOf(false) }
    val pedir = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { concedido ->
        permiso = concedido
        if (!concedido) aviso = resources.getString(R.string.escaner_qr_sin_permiso_de_camara_no_se)
    }
    LaunchedEffect(Unit) { if (!permiso) pedir.launch(Manifest.permission.CAMERA) }
    StmScreen(
        topBar = { TopBar(stringResource(R.string.escaner_qr_escanear_qr), navIcon = StmIcons.close, onNav = nav::back) },
        scroll = false,
    ) {
        if (permiso && aviso == null) {
            Text(stringResource(R.string.escaner_qr_apunta_al_qr_de_tu_pareja), style = StmType.bodyMedium, color = c.onSurfaceVariant)
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
                onError = { aviso = resources.getString(R.string.escaner_qr_este_dispositivo_no_tiene_camara) },
            )
        } else {
            Box(Modifier.fillMaxSize()) {
                aviso?.let { Text(it, style = StmType.bodyMedium, color = c.onSurfaceVariant) }
            }
        }
    }
}
