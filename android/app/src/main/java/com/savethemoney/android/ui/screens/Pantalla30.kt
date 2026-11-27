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
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.ChangePasswordForm
import com.savethemoney.android.data.DELETE_ACCOUNT_WARNING
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
                    "Tema", AppTheme.entries.map { t -> t.title to { action.run { session.setTheme(t) } } }, { eligeTema = false },
                )
            }
        } else if (eligeHabito) {
            {
                SelectorSheet(
                    "Recordarme apuntar gastos",
                    HabitSettings.LogReminder.entries.map { r -> r.title to { cambiaHabitos(habitos.copy(logReminder = r)) } },
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
            MenuRow(StmIcons.creditCard, "Tarjetas") { nav.go(Route.Tarjetas) }
            MenuRow(StmIcons.eventRepeat, "Pagos fijos", count = LocalSession.current.finance?.planning?.activeSeries?.size?.toString()) { nav.go(Route.PagosFijos) }
            MenuRow(StmIcons.monitoring, "Patrimonio, informes y score") { nav.go(Route.Patrimonio) }
            MenuRow(StmIcons.candlestickChart, "Inversiones") { nav.go(Route.Cartera) }
            MenuRow(StmIcons.group, "Hogar") { nav.go(Route.Hogar) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Datos")
            MenuRow(StmIcons.uploadFile, "Importar CSV") { nav.go(Route.ImportarCsv()) }
            MenuRow(StmIcons.pictureAsPdf, "PDF de pagos del mes") { nav.go(Route.PagosDelMes) }
            MenuRow(StmIcons.tableView, "CSV para Excel") {
                action.run {
                    val modelo = finance ?: return@run
                    val datos = modelo.exportCsv()
                    val fichero = ficheroExportar(context, MovementsCsv.fileName(modelo.today()))
                    withContext(Dispatchers.IO) { fichero.writeBytes(datos) }
                    compartir(context, fichero, "text/csv")
                }
            }
            MenuRow(StmIcons.category, "Categorías", count = categorias.toString()) { nav.go(Route.Categorias) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Preferencias")
            ListItem(
                "Tema oscuro", if (tema == AppTheme.System) "Igual que el sistema" else tema.title,
                leading = { StmIcon(StmIcons.darkMode, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(oscuro) { activo -> action.run { session.setTheme(if (activo) AppTheme.Dark else AppTheme.Light) } }
                },
                onClick = { eligeTema = true },
            )
            // Dos interruptores, como en iOS y Mac.
            ListItem(
                "Avisos de pagos fijos", "Antes de cada cargo",
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
                "Avisos de límites del presupuesto", "Al llegar al 80 % o pasarse",
                leading = { StmIcon(StmIcons.donutLarge, Stm.colors.onSurfaceVariant) },
                trailing = {
                    StmSwitch(limites) {
                        limites = it
                        finance?.planning?.budgetAlertsEnabled = it
                    }
                },
            )
            MenuRow(StmIcons.restartAlt, "Borrar datos y empezar de cero", chevron = false) { nav.go(Route.BorrarDatos) }
        }
        // Sin permiso, Android descarta los avisos sin decir nada: que se vea aquí.
        if (!LocalNotifier(context).canShow) {
            Text(
                "Android no deja mostrar notificaciones de Save the Money: los avisos no se verán hasta que las actives en Ajustes.",
                Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.error,
            )
        }
        // Fase D, como en iOS: recordatorio para apuntar gastos y resumen semanal. Sólo en este dispositivo.
        if (finance != null) {
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListHeader("Recordatorios")
                ListItem(
                    "Recordarme apuntar gastos", habitos.logReminder.title,
                    leading = { StmIcon(StmIcons.notifications, Stm.colors.onSurfaceVariant) },
                    trailing = { StmIcon(StmIcons.arrowDropDown, Stm.colors.onSurfaceVariant) },
                    onClick = { eligeHabito = true },
                )
                if (habitos.logReminder != HabitSettings.LogReminder.Off) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Hora", Modifier.weight(1f), style = StmType.bodyLarge, color = Stm.colors.onSurface)
                        Stepper(
                            "A las ${habitos.logHour}:00",
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour - 1).coerceAtLeast(6))) },
                            { cambiaHabitos(habitos.copy(logHour = (habitos.logHour + 1).coerceAtMost(23))) },
                        )
                    }
                }
                ListItem(
                    "Resumen semanal los lunes", "A las 9:00, con la semana anterior",
                    leading = { StmIcon(StmIcons.calendarMonth, Stm.colors.onSurfaceVariant) },
                    trailing = { StmSwitch(habitos.weeklySummary) { cambiaHabitos(habitos.copy(weeklySummary = it)) } },
                )
            }
        }
        // No está en el diseño; va al final para no mover lo anterior. Sólo en este dispositivo.
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Vista")
            InterruptorVista(StmIcons.visibilityOff, "Modo incógnito", "Oculta los importes; también con el ojo del Resumen", Vista.incognito, Vista::setIncognito)
            InterruptorVista(StmIcons.savings, "Sin céntimos", "1.235 € en vez de 1.234,56 €", Vista.sinCentimos, Vista::setSinCentimos)
            InterruptorVista(StmIcons.add, "Mostrar + en los ingresos", "+1.200,00 €", Vista.signoMas, Vista::setSignoMas)
            InterruptorVista(StmIcons.trendingUp, "Ingresos en verde", "En las listas de movimientos", Vista.ingresosEnVerde, Vista::setIngresosEnVerde)
        }
        Text(
            "Sólo en este dispositivo. Los PDF y CSV llevan siempre los importes completos.",
            Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
        )
        // Bloqueo con huella, cara o código (ORC-111). Sólo en este dispositivo.
        Spacer(Modifier.height(16.dp))
        AjusteBloqueo()
        Spacer(Modifier.height(16.dp))
        // Cambiar la contraseña con la sesión abierta (ORC-57).
        ListCard {
            MenuRow(StmIcons.lock, "Cambiar la contraseña") { cambiaClave = true }
        }
        Text(
            if (claveCambiada) "Contraseña cambiada. Esta sesión sigue abierta; en tus otros dispositivos tendrás que volver a entrar."
            else "Pide la contraseña actual. Al cambiarla se cierra la sesión en tus otros dispositivos.",
            Modifier.padding(start = 16.dp, top = 8.dp), style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant,
        )
        HogaresAnteriores()
        Spacer(Modifier.height(16.dp))
        ListCard {
            MenuRow(StmIcons.logout, "Cerrar sesión", chevron = false) { action.run { session.signOut() } }
        }
        Spacer(Modifier.height(16.dp))
        // Borrar la cuenta (ORC-74): en rojo, como las demás acciones que no se pueden deshacer.
        ListCard {
            SheetItem(StmIcons.deleteForever, "Borrar mi cuenta", Stm.colors.error, Stm.colors.error) { borraCuenta = true }
        }
        Text(
            "Borra tu usuario y todo lo que has apuntado. Pide la contraseña y no se puede deshacer.",
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
        "Cambiar la contraseña",
        onDismiss = onDismiss,
        actions = {
            Btn("Cancelar", onDismiss, kind = BtnKind.Text)
            Btn("Cambiar", {
                action.run {
                    session.changePassword(form)
                    onChanged()
                    onDismiss()
                }
            }, kind = BtnKind.Text, enabled = form.firstIssue == null && !action.busy)
        },
    ) {
        Spacer(Modifier.height(16.dp))
        OutlinedField("Contraseña actual", actual, { actual = it }, password = true, labelBackground = c.surfaceContainerHigh, autoFocus = true)
        Spacer(Modifier.height(12.dp))
        OutlinedField(
            "Nueva contraseña", nueva, { nueva = it }, password = true, labelBackground = c.surfaceContainerHigh, error = tooShort,
            supporting = if (tooShort) "Usa al menos ${SignUpForm.MIN_PASSWORD} caracteres" else null,
        )
        Spacer(Modifier.height(12.dp))
        OutlinedField(
            "Repite la nueva contraseña", repite, { repite = it }, password = true, labelBackground = c.surfaceContainerHigh,
            error = mismatch || action.error != null,
            supporting = action.error ?: if (mismatch) "Las contraseñas no coinciden." else if (nueva.isNotEmpty() && nueva == actual) ChangePasswordForm.SAME_PASSWORD else null,
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
    BottomSheet("Borrar mi cuenta", onDismiss = onDismiss) {
        // Con letra grande o pantalla pequeña el aviso no cabe: se desplaza y los botones siguen al alcance.
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Text(DELETE_ACCOUNT_WARNING, style = StmType.bodyMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            OutlinedField(
                "Contraseña actual", clave, { clave = it }, password = true, labelBackground = c.surfaceContainerLow,
                error = action.error != null, supporting = action.error,
            )
            Spacer(Modifier.height(16.dp))
            // Al terminar, la sesión pasa a «sin sesión» y esta hoja desaparece con la pantalla.
            Btn(
                "Borrar mi cuenta para siempre", { action.run { session.deleteAccount(clave) } }, Modifier.fillMaxWidth(),
                kind = BtnKind.Error, enabled = clave.isNotEmpty() && !action.busy,
            )
            Spacer(Modifier.height(8.dp))
            Btn("Cancelar", onDismiss, Modifier.fillMaxWidth(), kind = BtnKind.Text)
        }
    }
}
