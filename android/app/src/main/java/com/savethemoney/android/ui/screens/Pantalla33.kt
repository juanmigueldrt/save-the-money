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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
                stringResource(R.string.borrar_datos_borrar_lo_que_creaste),
                stringResource(R.string.borrar_datos_borra_lo_que_creaste_tu_cuentas),
                icon = StmIcons.deleteForever,
                onDismiss = nav::back,
                actions = {
                    Btn(stringResource(R.string.comun_cancelar), nav::back, kind = BtnKind.Text)
                    Btn(
                        stringResource(R.string.comun_borrar),
                        {
                            action.run {
                                finance?.resetHousehold()
                                nav.reset(Route.Inicio)
                            }
                        },
                        kind = BtnKind.Error, enabled = confirm.trim().lowercase() == stringResource(R.string.borrar_datos_palabra) && !action.busy,
                    )
                },
            ) {
                Spacer(Modifier.height(16.dp))
                OutlinedField(stringResource(R.string.borrar_datos_escribe_para_confirmar, stringResource(R.string.borrar_datos_palabra)), confirm, { confirm = it }, labelBackground = c.surfaceContainerHigh, autoFocus = true)
            }
        },
    ) {
        ListCard {
            MenuRow(StmIcons.restartAlt, stringResource(R.string.borrar_datos_borrar_datos_y_empezar_de_cero), chevron = false, onClick = null)
        }
    }
}
