package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 03 Tu hogar: crear un hogar nuevo o unirse con código o QR. */
@Composable
fun Pantalla03(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val create = rememberAction()
    val join = rememberAction()
    var code by rememberSaveable { mutableStateOf(session.pendingInvite?.value ?: "") }
    val parsed = InviteCode.parse(code)
    var borraCuenta by rememberSaveable { mutableStateOf(false) }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null)
            LargeTitle("Tu hogar", "Un hogar reúne las cuentas que compartís")
        },
        overlay = if (borraCuenta) {
            { HojaBorrarCuenta { borraCuenta = false } }
        } else {
            null
        },
    ) {
        OptionCard(StmIcons.homeWork, c.secondaryContainer, c.onSecondaryContainer, "Crear un hogar nuevo",
            "Empieza de cero y después invita a tu pareja con un código o un QR.") {
            create.error?.let { Text(it, Modifier.weight(1f), style = StmType.bodySmall, color = c.error) }
            Btn("Crear hogar", { create.run { session.createHousehold("Casa de ${session.profile?.name ?: "todos"}") } }, enabled = !create.busy)
        }
        Spacer(Modifier.height(16.dp))
        OptionCard(StmIcons.qrCodeScanner, c.tertiaryContainer, c.onTertiaryContainer, "Unirme a un hogar",
            "Escanea el QR de tu pareja o escribe su código de 6 letras.",
            field = {
                OutlinedField(
                    "Código", code, { code = it }, labelBackground = c.surfaceContainerLowest,
                    error = join.error != null, supporting = join.error,
                )
            },
        ) {
            Btn("Escanear QR", { nav.go(Route.EscanerQr) }, kind = BtnKind.Outlined, icon = StmIcons.qrCodeScanner)
            Btn("Unirme", { parsed?.let { join.run { session.join(it) } } }, kind = BtnKind.Tonal, enabled = parsed != null && !join.busy)
        }
        HogaresAnteriores()
        Spacer(Modifier.height(16.dp))
        // Quien aún no tiene hogar también tiene que poder borrar su cuenta (ORC-74).
        Btn("Borrar mi cuenta", { borraCuenta = true }, Modifier.fillMaxWidth(), kind = BtnKind.Error)
    }
}

/** Tarjeta de opción de la pantalla 03: icono, título, texto, campo opcional y botones a la derecha. */
@Composable
private fun OptionCard(
    icon: ImageVector,
    container: Color,
    tint: Color,
    title: String,
    text: String,
    field: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit,
) {
    val c = Stm.colors
    StmCard {
        LeadIcon(icon, container, tint)
        Spacer(Modifier.height(12.dp))
        Text(title, style = StmType.titleMedium, color = c.onSurface)
        Spacer(Modifier.height(16.dp))
        Text(text, style = StmType.bodyMedium, color = c.onSurfaceVariant)
        if (field != null) {
            Spacer(Modifier.height(12.dp))
            field()
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) { actions() }
    }
}
