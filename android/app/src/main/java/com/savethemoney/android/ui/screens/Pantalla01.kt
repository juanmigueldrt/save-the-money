package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 01 Iniciar sesión: marca, usuario y contraseña, entrar o crear cuenta. */
@Composable
fun Pantalla01(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    var user by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var hidden by remember { mutableStateOf(true) }
    val canSubmit = user.isNotBlank() && password.isNotEmpty() && !action.busy
    StmScreen {
        Column(Modifier.padding(start = 8.dp, end = 8.dp, top = 48.dp)) {
            Text("Save the Money", style = StmType.labelLarge, color = c.primary)
            Spacer(Modifier.height(8.dp))
            Text("Tu dinero, claro", style = StmType.displayMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Text("Entra con tu usuario y contraseña para ver las cuentas de tu hogar.", style = StmType.bodyLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            OutlinedField("Usuario", user, { user = it }, leading = StmIcons.person)
            Spacer(Modifier.height(16.dp))
            OutlinedField(
                "Contraseña", password, { password = it }, leading = StmIcons.lock,
                trailing = if (hidden) StmIcons.visibility else StmIcons.visibilityOff, onTrailing = { hidden = !hidden },
                password = hidden,
                error = action.error != null, supporting = action.error,
            )
            Spacer(Modifier.height(24.dp))
            Btn("Entrar", { action.run { session.signIn(user, password) } }, Modifier.fillMaxWidth(), large = true, enabled = canSubmit)
            session.signOutNotice?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) }
            Spacer(Modifier.height(24.dp))
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Btn("Crear cuenta", { nav.go(Route.CrearCuenta) }, kind = BtnKind.Text)
            }
        }
    }
}
