package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 02 Crear cuenta: nombre, usuario y contraseña repetida, sin correo. */
@Composable
fun Pantalla02(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    var name by rememberSaveable { mutableStateOf("") }
    var user by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeat by remember { mutableStateOf("") }
    val form = SignUpForm(user, name, password, repeat)
    // Los avisos salen en cuanto se escribe en el campo, como en el diseño.
    val userIssue = if (user.isEmpty()) null else Username.parse(user).exceptionOrNull()?.message
    val tooShort = password.isNotEmpty() && password.length < SignUpForm.MIN_PASSWORD
    val mismatch = repeat.isNotEmpty() && repeat != password
    StmScreen(
        topBar = { TopBar("Crear cuenta", onNav = nav::back) },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn(
                    "Crear cuenta", { action.run { session.signUp(form) } }, Modifier.fillMaxWidth(), large = true,
                    enabled = form.firstIssue == null && !action.busy,
                )
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Solo te pedimos un usuario y una contraseña. No usamos tu correo.", style = StmType.bodyLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        OutlinedField("Nombre", name, { name = it }, supporting = "Así te verá tu pareja en el hogar")
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Usuario", user, { user = it }, error = userIssue != null,
            supporting = userIssue ?: "Letras y números, sin espacios",
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Contraseña", password, { password = it }, password = true, error = tooShort,
            trailing = if (tooShort) StmIcons.error else null,
            supporting = if (tooShort) "Usa al menos ${SignUpForm.MIN_PASSWORD} caracteres" else null,
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Repite la contraseña", repeat, { repeat = it }, password = true, placeholder = "Contraseña",
            error = mismatch || action.error != null,
            supporting = action.error ?: if (mismatch) "Las contraseñas no coinciden." else null,
        )
    }
}
