package com.savethemoney.android.ui.screens

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.ChangePasswordForm
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MovementsCsv
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.ui.AjusteBloqueo
import com.savethemoney.android.ui.LocalNotifier
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.Vista
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.SheetItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 30 Más opciones: menú de secciones, datos y preferencias. */
@Composable
fun Pantalla30(nav: Nav) {
    val finance = LocalSession.current.finance
    val categorias = finance?.categories?.size ?: 0
    val session = LocalSession.current
    val context = LocalContext.current
    val tema = session.profile?.theme ?: AppTheme.System
    val oscuro = when (tema) {
        AppTheme.Light -> false
        AppTheme.Dark -> true
        AppTheme.System -> isSystemInDarkTheme()
    }
    var eligeTema by remember { mutableStateOf(false) }
    val action = rememberAction()
    var alerts by remember(finance) { mutableStateOf(finance?.planning?.alertsEnabled ?: true) }
    var limites by remember(finance) { mutableStateOf(finance?.planning?.budgetAlertsEnabled ?: true) }
    var habitos by remember(finance) { mutableStateOf(finance?.planning?.habits ?: HabitSettings()) }
    var eligeHabito by remember { mutableStateOf(false) }
    var cambiaClave by remember { mutableStateOf(false) }
    var claveCambiada by remember { mutableStateOf(false) }
    var borraCuenta by remember { mutableStateOf(false) }
    val cambiaHabitos = { nuevos: HabitSettings ->
        habitos = nuevos
        finance?.planning?.habits = nuevos
    }
    StmScreen(
        topBar = { MasHeader() },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligeTema) {
            {
                SelectorSheet(
                    stringResource(R.string.mas_tema), AppTheme.entries.map { t -> stringResource(t.titulo) to { action.run { session.setTheme(t) } } }, { eligeTema = false },
                )
            }
        } else if (eligeHabito) {
            {
                SelectorSheet(
                    stringResource(R.string.mas_recordarme_apuntar_gastos),
                    HabitSettings.LogReminder.entries.map { r -> stringResource(r.titulo) to { cambiaHabitos(habitos.copy(logReminder = r)) } },
                    { eligeHabito = false },
                )
            }
        } else if (cambiaClave) {
            { DialogoContrasena({ claveCambiada = true }) { cambiaClave = false } }
        } else if (borraCuenta) {
            { HojaBorrarCuenta { borraCuenta = false } }
        } else {
            null
        },
    ) {
        ListCard {
            MenuRow(StmIcons.creditCard, stringResource(R.string.tarjetas_tarjetas)) { nav.go(Route.Tarjetas) }
            MenuRow(StmIcons.eventRepeat, stringResource(R.string.pagos_fijos_pagos_fijos), count = LocalSession.current.finance?.planning?.activeSeries?.size?.toString()) { nav.go(Route.PagosFijos) }
            MenuRow(StmIcons.monitoring, stringResource(R.string.mas_patrimonio_informes_y_score)) { nav.go(Route.Patrimonio) }
            MenuRow(StmIcons.candlestickChart, stringResource(R.string.mas_inversiones)) { nav.go(Route.Cartera) }
            MenuRow(StmIcons.group, stringResource(R.string.hogar_hogar)) { nav.go(Route.Hogar) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.mas_datos))
            MenuRow(StmIcons.uploadFile, stringResource(R.string.importar_csv_importar_csv)) { nav.go(Route.ImportarCsv()) }
            MenuRow(StmIcons.pictureAsPdf, stringResource(R.string.mas_pdf_de_pagos_del_mes)) { nav.go(Route.PagosDelMes) }
            MenuRow(StmIcons.tableView, stringResource(R.string.mas_csv_para_excel)) {
                action.run {
                    val modelo = finance ?: return@run
                    val datos = modelo.exportCsv()
                    val fichero = ficheroExportar(context, MovementsCsv.fileName(modelo.today()))
                    withContext(Dispatchers.IO) { fichero.writeBytes(datos) }
                    compartir(context, fichero, "text/csv")
                }
            }
            MenuRow(StmIcons.category, stringResource(R.string.categorias_categorias), count = categorias.toString()) { nav.go(Route.Categorias) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.mas_preferencias))
            ListItem(
                stringResource(R.string.mas_tema_oscuro), if (tema == AppTheme.System) stringResource(R.string.mas_igual_que_el_sistema) else stringResource(tema.titulo),
                leading = { StmIcon(StmIcons.darkMode, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(oscuro) { activo -> action.run { session.setTheme(if (activo) AppTheme.Dark else AppTheme.Light) } }
                },
                onClick = { eligeTema = true },
            )
            // Dos interruptores, como en iOS y Mac.
            ListItem(
                stringResource(R.string.mas_avisos_de_pagos_fijos), stringResource(R.string.mas_antes_de_cada_cargo),
                leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(alerts) {
                        alerts = it
                        finance?.planning?.alertsEnabled = it
                        finance?.cards?.reschedule()
                        finance?.investments?.reschedule()
                    }
                },
            )
            ListItem(
                stringResource(R.string.mas_avisos_de_limites_del_presupuesto), stringResource(R.string.mas_al_llegar_al_80_o_pasarse),
                leading = { StmIcon(StmIcons.donutLarge, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(limites) {
                        limites = it
                        finance?.planning?.budgetAlertsEnabled = it
                    }
                },
            )
            MenuRow(StmIcons.restartAlt, stringResource(R.string.borrar_datos_borrar_datos_y_empezar_de_cero), chevron = false) { nav.go(Route.BorrarDatos) }
        }
        // Sin permiso, Android descarta los avisos sin decir nada: que se vea aquí.
        if (!LocalNotifier(context).canShow) {
            Text(
                stringResource(R.string.mas_android_no_deja_mostrar),
                Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.error,
            )
        }
        // Fase D, como en iOS: recordatorio para apuntar gastos y resumen semanal. Sólo en este dispositivo.
        if (finance != null) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader(stringResource(R.string.mas_recordatorios))
                ListItem(
                    stringResource(R.string.mas_recordarme_apuntar_gastos), stringResource(habitos.logReminder.titulo),
                    leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                    trailing = { StmIcon(StmIcons.arrowDropDown, Stm.colors.onSurfaceVariant) },
                    onClick = { eligeHabito = true },
                )
                if (habitos.logReminder != HabitSettings.LogReminder.Off) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.mas_hora), Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
                        Stepper(
                            stringResource(R.string.mas_a_las_00, habitos.logHour),
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour - 1).coerceAtLeast(6))) },
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour + 1).coerceAtMost(23))) },
                        )
                    }
                }
                ListItem(
                    stringResource(R.string.mas_resumen_semanal_los_lunes), stringResource(R.string.mas_a_las_9_00_con_la),
                    leading = { StmIcon(StmIcons.calendarMonth, Stm.colors.onSurfaceVariant) },
                    trailing = { StmSwitch(habitos.weeklySummary) { cambiaHabitos(habitos.copy(weeklySummary = it)) } },
                )
            }
        }
        // No está en el diseño; va al final para no mover lo anterior. Sólo en este dispositivo.
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.mas_vista))
            InterruptorVista(StmIcons.visibilityOff, stringResource(R.string.mas_modo_incognito), stringResource(R.string.mas_oculta_los_importes_tambien_con_el), Vista.incognito, Vista::setIncognito)
            InterruptorVista(StmIcons.savings, stringResource(R.string.mas_sin_centimos), stringResource(R.string.mas_1_235_en_vez_de_1), Vista.sinCentimos, Vista::setSinCentimos)
            InterruptorVista(StmIcons.add, stringResource(R.string.mas_mostrar_en_los_ingresos), "+1.200,00 €", Vista.signoMas, Vista::setSignoMas)
            InterruptorVista(StmIcons.trendingUp, stringResource(R.string.mas_ingresos_en_verde), stringResource(R.string.mas_en_las_listas_de_movimientos), Vista.ingresosEnVerde, Vista::setIngresosEnVerde)
        }
        Text(
            stringResource(R.string.mas_solo_en_este_dispositivo_los_pdf),
            Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
        )
        // Bloqueo con huella, cara o código (ORC-111). Sólo en este dispositivo.
        Spacer(Modifier.height(16.dp))
        AjusteBloqueo()
        Spacer(Modifier.height(16.dp))
        // Cambiar la contraseña con la sesión abierta (ORC-57).
        ListCard {
            MenuRow(StmIcons.lock, stringResource(R.string.mas_cambiar_la_contrasena)) { cambiaClave = true }
        }
        Text(
            if (claveCambiada) stringResource(R.string.mas_contrasena_cambiada_esta_sesion)
            else stringResource(R.string.mas_pide_la_contrasena_actual_al),
            Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
        )
        HogaresAnteriores()
        Spacer(Modifier.height(16.dp))
        ListCard {
            MenuRow(StmIcons.logout, stringResource(R.string.acceso_cerrar_sesion), chevron = false) { action.run { session.signOut() } }
        }
        Spacer(Modifier.height(16.dp))
        // Borrar la cuenta (ORC-74): en rojo, como las demás acciones que no se pueden deshacer.
        ListCard {
            SheetItem(StmIcons.deleteForever, stringResource(R.string.mas_borrar_mi_cuenta), Stm.colors.error, Stm.colors.error) { borraCuenta = true }
        }
        Text(
            stringResource(R.string.mas_borra_tu_usuario_y_todo_lo),
            Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun InterruptorVista(icon: androidx.compose.ui.graphics.vector.ImageVector, titulo: String, detalle: String, activo: Boolean, cambia: (Boolean) -> Unit) {
    ListItem(
        titulo, detalle,
        leading = { StmIcon(icon, Stm.colors.onSurfaceVariant) },
        trailing = { StmSwitch(activo, cambia) },
        onClick = { cambia(!activo) },
    )
}

/** Cambiar la contraseña (ORC-57): la actual y la nueva dos veces, con la misma regla que al crear la cuenta. */
@Composable
private fun BoxScope.DialogoContrasena(onChanged: () -> Unit, onDismiss: () -> Unit) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    var actual by remember { mutableStateOf("") }
    var nueva by remember { mutableStateOf("") }
    var repite by remember { mutableStateOf("") }
    val form = ChangePasswordForm(actual, nueva, repite)
    // Los avisos salen en cuanto se escribe en el campo, como al crear la cuenta.
    val tooShort = nueva.isNotEmpty() && nueva.length < SignUpForm.MIN_PASSWORD
    val mismatch = repite.isNotEmpty() && repite != nueva
    StmDialog(
        stringResource(R.string.mas_cambiar_la_contrasena),
        onDismiss = onDismiss,
        actions = {
            Btn(stringResource(R.string.comun_cancelar), onDismiss, kind = BtnKind.Text)
            Btn(stringResource(R.string.mas_cambiar), {
                action.run {
                    session.changePassword(form)
                    onChanged()
                    onDismiss()
                }
            }, kind = BtnKind.Text, enabled = form.firstIssue == null && !action.busy)
        },
    ) {
        Spacer(Modifier.height(16.dp))
        OutlinedField(stringResource(R.string.mas_contrasena_actual), actual, { actual = it }, password = true, labelBackground = c.surfaceContainerHigh, autoFocus = true)
        Spacer(Modifier.height(12.dp))
        OutlinedField(
            stringResource(R.string.mas_nueva_contrasena), nueva, { nueva = it }, password = true, labelBackground = c.surfaceContainerHigh, error = tooShort,
            supporting = if (tooShort) stringResource(R.string.crear_cuenta_usa_al_menos_caracteres, SignUpForm.MIN_PASSWORD) else null,
        )
        Spacer(Modifier.height(12.dp))
        OutlinedField(
            stringResource(R.string.mas_repite_la_nueva_contrasena), repite, { repite = it }, password = true, labelBackground = c.surfaceContainerHigh,
            error = mismatch || action.error != null,
            supporting = action.error ?: if (mismatch) stringResource(R.string.crear_cuenta_las_contrasenas_no_coinciden) else if (nueva.isNotEmpty() && nueva == actual) ChangePasswordForm.SAME_PASSWORD else null,
        )
    }
}

/** Borrar la cuenta (ORC-74): el aviso de lo que se borra, la contraseña actual y un botón que dice lo que hace. */
@Composable
internal fun BoxScope.HojaBorrarCuenta(onDismiss: () -> Unit) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    var clave by remember { mutableStateOf("") }
    BottomSheet(stringResource(R.string.mas_borrar_mi_cuenta), onDismiss = onDismiss) {
        // Con letra grande o pantalla pequeña el aviso no cabe: se desplaza y los botones siguen al alcance.
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Text(stringResource(R.string.mas_aviso_borrar_cuenta), style = StmType.bodyMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            OutlinedField(
                stringResource(R.string.mas_contrasena_actual), clave, { clave = it }, password = true, labelBackground = c.surfaceContainerLow,
                error = action.error != null, supporting = action.error,
            )
            Spacer(Modifier.height(16.dp))
            // Al terminar, la sesión pasa a «sin sesión» y esta hoja desaparece con la pantalla.
            Btn(
                stringResource(R.string.mas_borrar_mi_cuenta_para_siempre), { action.run { session.deleteAccount(clave) } }, Modifier.fillMaxWidth(),
                kind = BtnKind.Error, enabled = clave.isNotEmpty() && !action.busy,
            )
            Spacer(Modifier.height(8.dp))
            Btn(stringResource(R.string.comun_cancelar), onDismiss, Modifier.fillMaxWidth(), kind = BtnKind.Text)
        }
    }
}
