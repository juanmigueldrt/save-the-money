package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm

/** 33 Borrar datos: diálogo de confirmación sobre Más opciones. */
@Composable
fun Pantalla33(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance
    var confirm by remember { mutableStateOf("") }
    val action = rememberAction()
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = {
            StmDialog(
                "¿Borrar lo que creaste?",
                "Borra lo que creaste tú: cuentas, tarjetas, movimientos, presupuestos, pagos fijos, metas e inversiones. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo. Esta acción no se puede deshacer.",
                icon = StmIcons.deleteForever,
                onDismiss = nav::back,
                actions = {
                    Btn("Cancelar", nav::back, kind = BtnKind.Text)
                    Btn(
                        "Borrar",
                        {
                            action.run {
                                finance?.resetHousehold()
                                nav.reset(Route.Inicio)
                            }
                        },
                        kind = BtnKind.Error, enabled = confirm.trim().lowercase() == "borrar" && !action.busy,
                    )
                },
            ) {
                Spacer(Modifier.height(16.dp))
                OutlinedField("Escribe «borrar» para confirmar", confirm, { confirm = it }, labelBackground = c.surfaceContainerHigh, autoFocus = true)
            }
        },
    ) {
        ListCard {
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false, onClick = null)
        }
    }
}
