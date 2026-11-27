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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
        topBar = { TopBar(stringResource(R.string.acceso_crear_cuenta), onNav = nav::back) },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn(
                    stringResource(R.string.acceso_crear_cuenta), { action.run { session.signUp(form) } }, Modifier.fillMaxWidth(), large = true,
                    enabled = form.firstIssue == null && !action.busy,
                )
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.crear_cuenta_solo_te_pedimos_un_usuario_y), style = StmType.bodyLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        OutlinedField(stringResource(R.string.comun_nombre), name, { name = it }, supporting = stringResource(R.string.crear_cuenta_asi_te_vera_tu_pareja_en))
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            stringResource(R.string.comun_usuario), user, { user = it }, error = userIssue != null,
            supporting = userIssue ?: stringResource(R.string.crear_cuenta_letras_y_numeros_sin_espacios),
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            stringResource(R.string.comun_contrasena), password, { password = it }, password = true, error = tooShort,
            trailing = if (tooShort) StmIcons.error else null,
            supporting = if (tooShort) stringResource(R.string.crear_cuenta_usa_al_menos_caracteres, SignUpForm.MIN_PASSWORD) else null,
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            stringResource(R.string.crear_cuenta_repite_la_contrasena), repeat, { repeat = it }, password = true, placeholder = stringResource(R.string.comun_contrasena),
            error = mismatch || action.error != null,
            supporting = action.error ?: if (mismatch) stringResource(R.string.crear_cuenta_las_contrasenas_no_coinciden) else null,
        )
    }
}
