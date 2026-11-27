package com.savethemoney.android.ui.screens

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.LAST_MEMBER_WARNING
import com.savethemoney.android.data.LEAVE_HOUSEHOLD_WARNING
import com.savethemoney.android.data.MONTH_START_DAYS
import com.savethemoney.android.data.MemberRole
import com.savethemoney.android.data.OWNER_MUST_TRANSFER
import com.savethemoney.android.data.REMOVE_MEMBER_WARNING
import com.savethemoney.android.data.TRANSFER_HOUSEHOLD_WARNING
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmDialog
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 28 Hogar: elegir hogar, ajustes del hogar y del perfil, miembros, qué se comparte e invitar a alguien. */
@Composable
fun Pantalla28(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val me = session.profile?.id
    var recarga by remember { mutableIntStateOf(0) }
    // Con el id del hogar: al cambiar de hogar, la lista del anterior no se enseña mientras carga la del nuevo.
    val carga by produceState<Pair<String, Result<List<HouseholdMember>>>?>(null, session.household, recarga) {
        value = session.household?.let { h -> h.id to runCatching { session.backend.members(h.id) } }
    }
    val miembros = carga?.takeIf { it.first == session.household?.id }?.second
    val members = miembros?.getOrNull().orEmpty().sortedBy { it.profile.id != me }
    val fallo = miembros?.exceptionOrNull()?.let { (it as? AppError)?.message ?: "No se han podido cargar los miembros del hogar." }
    val soyDueno = members.any { it.profile.id == me && it.role == MemberRole.Owner }
    // El dueño no puede salir con otros miembros dentro (ORC-59): el servidor también lo impide.
    val duenoConOtros = soyDueno && members.size > 1
    var quitando by remember { mutableStateOf<HouseholdMember?>(null) }
    var traspasando by remember { mutableStateOf<HouseholdMember?>(null) }
    var saliendo by remember { mutableStateOf(false) }
    var nombre by remember { mutableStateOf<String?>(null) }
    var eligeDia by remember { mutableStateOf(false) }
    var nombreVisible by remember { mutableStateOf<String?>(null) }
    val action = rememberAction()
    StmScreen(
        topBar = {
            // Barra de 60 dp con título mediano debajo (no coincide con TopBar + LargeTitle).
            Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconBtn(StmIcons.arrowBack, nav::back, contentDescription = "Atrás")
                Spacer(Modifier.weight(1f))
                // Sólo el dueño puede cambiar el nombre (RLS de households).
                if (soyDueno) {
                    IconBtn(StmIcons.edit, { nombre = session.household?.name.orEmpty() }, contentDescription = "Cambiar el nombre del hogar")
                }
            }
            Text("Hogar", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp), style = StmType.headlineMedium, color = c.onSurface)
            Text(session.household?.name.orEmpty(), Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.bodyLarge, color = c.onSurfaceVariant)
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        overlay = quitando?.let { m ->
            {
                StmDialog(
                    "¿Quitar a ${m.profile.name} del hogar?",
                    REMOVE_MEMBER_WARNING,
                    icon = StmIcons.personRemove,
                    onDismiss = { quitando = null },
                    actions = {
                        Btn("Cancelar", { quitando = null }, kind = BtnKind.Text)
                        Btn("Quitar", {
                            val h = session.household ?: return@Btn
                            action.run {
                                session.backend.removeMember(h.id, m.profile.id)
                                quitando = null
                                recarga++
                            }
                        }, kind = BtnKind.Error, enabled = !action.busy)
                    },
                ) { action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) } }
            }
        } ?: traspasando?.let { m ->
            {
                StmDialog(
                    "¿Hacer propietario a ${m.profile.name}?",
                    TRANSFER_HOUSEHOLD_WARNING,
                    onDismiss = { traspasando = null },
                    actions = {
                        Btn("Cancelar", { traspasando = null }, kind = BtnKind.Text)
                        Btn("Hacer propietario", {
                            val h = session.household ?: return@Btn
                            action.run {
                                session.backend.transferHousehold(h.id, m.profile.id)
                                traspasando = null
                                recarga++
                            }
                        }, kind = BtnKind.Text, enabled = !action.busy)
                    },
                ) { action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) } }
            }
        } ?: nombre?.let { texto ->
            {
                StmDialog(
                    "Nombre del hogar", "Lo verán todos los miembros.",
                    onDismiss = { nombre = null },
                    actions = {
                        Btn("Cancelar", { nombre = null }, kind = BtnKind.Text)
                        Btn("Guardar", {
                            val h = session.household ?: return@Btn
                            action.run {
                                session.renameHousehold(h, texto)
                                nombre = null
                            }
                        }, kind = BtnKind.Text, enabled = !action.busy)
                    },
                ) {
                    Spacer(Modifier.height(16.dp))
                    FilledField("Nombre", texto, { nombre = it }, autoFocus = true)
                    action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) }
                }
            }
        } ?: if (saliendo) {
            {
                StmDialog(
                    "¿Salir del hogar?",
                    when {
                        duenoConOtros -> OWNER_MUST_TRANSFER
                        members.size == 1 -> "$LEAVE_HOUSEHOLD_WARNING $LAST_MEMBER_WARNING"
                        else -> LEAVE_HOUSEHOLD_WARNING
                    },
                    icon = StmIcons.logout,
                    onDismiss = { saliendo = false },
                    actions = {
                        Btn(if (duenoConOtros) "Entendido" else "Cancelar", { saliendo = false }, kind = BtnKind.Text)
                        if (!duenoConOtros) {
                            Btn("Salir", {
                                val h = session.household ?: return@Btn
                                action.run { session.leaveHousehold(h) }
                            }, kind = BtnKind.Error, enabled = !action.busy)
                        }
                    },
                ) { action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) } }
            }
        } else if (eligeDia) {
            {
                SelectorSheet(
                    "Día de inicio del mes",
                    MONTH_START_DAYS.map { d -> "Día $d" to { action.run { session.setMonthStartDay(d) } } },
                    { eligeDia = false },
                )
            }
        } else nombreVisible?.let { texto ->
            {
                StmDialog(
                    "Tu nombre visible", "Es como te ven los demás miembros. Vacío, se usa tu usuario; como mucho 60 caracteres.",
                    onDismiss = { nombreVisible = null },
                    actions = {
                        Btn("Cancelar", { nombreVisible = null }, kind = BtnKind.Text)
                        Btn("Guardar", {
                            action.run {
                                session.setDisplayName(texto)
                                nombreVisible = null
                                // La lista de miembros lleva el nombre: se vuelve a pedir.
                                recarga++
                            }
                        }, kind = BtnKind.Text, enabled = !action.busy)
                    },
                ) {
                    Spacer(Modifier.height(16.dp))
                    FilledField("Nombre visible", texto, { nombreVisible = it }, autoFocus = true)
                    action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) }
                }
            }
        },
    ) {
        if (session.households.size > 1) {
            ListCard {
                ListHeader("Tus hogares")
                session.households.forEachIndexed { i, h ->
                    if (i > 0) Divider()
                    val abierto = h.id == session.household?.id
                    ListItem(
                        h.name, if (abierto) "Abierto" else "Abrir este hogar",
                        onClick = if (abierto || action.busy) null else ({ action.run { session.open(h) } }),
                    )
                }
            }
            Text(
                "Cada hogar tiene sus propias cuentas y presupuestos. Este dispositivo recuerda cuál abriste.",
                Modifier.padding(16.dp), style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
        ListCard {
            ListHeader("Ajustes")
            val dia = session.household?.monthStartDay ?: 1
            // Sólo el dueño puede cambiarlo (RLS de households); los demás lo ven.
            ListItem(
                "Inicio del mes", if (soyDueno) "Día $dia" else "Día $dia · solo quien creó el hogar puede cambiarlo",
                onClick = if (soyDueno) ({ eligeDia = true }) else null,
            )
            Divider()
            ListItem("Tu nombre visible", session.profile?.name, onClick = { nombreVisible = session.profile?.displayName.orEmpty() })
        }
        Text(
            "Presupuestos, informes y «este mes» cuentan desde el día de inicio. No se cambia ni se borra ningún movimiento.",
            Modifier.padding(16.dp), style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
        // Lo que no se pudo guardar desde una hoja (día de inicio, cambiar de hogar): el aviso del servidor.
        if (!eligeDia && nombreVisible == null && nombre == null && quitando == null && traspasando == null && !saliendo) {
            action.error?.let { Text(it, Modifier.padding(horizontal = 16.dp), style = StmType.bodySmall, color = c.error) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Miembros")
            members.forEachIndexed { i, m ->
                if (i > 0) Divider()
                val role = if (m.role == MemberRole.Owner) "propietario" else "miembro"
                ListItem(
                    m.profile.name, if (m.profile.id == me) "Tú · $role" else role.replaceFirstChar { it.uppercase() },
                    leading = { Avatar(m.profile.name.take(1).uppercase()) },
                    // Solo el dueño puede quitar a otros; el diseño deja 24 dp a la derecha del icono final.
                    trailing = if (m.profile.id == me || !soyDueno) null else ({
                        IconBtn(StmIcons.personRemove, { quitando = m }, contentDescription = "Quitar del hogar")
                    }),
                )
                // Debajo de la fila y no junto al icono: con letra grande, un botón de texto ahí dejaría sin sitio al nombre.
                if (m.profile.id != me && soyDueno) {
                    Btn("Hacer propietario", { traspasando = m }, Modifier.padding(start = 60.dp, bottom = 4.dp), kind = BtnKind.Text)
                }
            }
        }
        // Sin red la lista sale vacía: el aviso y «Reintentar» dicen que no es que el hogar no tenga miembros.
        fallo?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, Modifier.padding(horizontal = 16.dp), style = StmType.bodySmall, color = c.error)
            Btn("Reintentar", { recarga++ }, kind = BtnKind.Text)
        }
        Spacer(Modifier.height(16.dp))
        val shape = RoundedCornerShape(12.dp)
        StmCard(Modifier.fillMaxWidth().border(1.dp, c.outlineVariant, shape), color = c.surface) {
            Text("Qué compartís", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Text(
                "Metas, pagos fijos y gastos esenciales. Las cuentas, los presupuestos y el score son de cada uno salvo que los compartas.",
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Btn("Invitar a alguien", { nav.go(Route.Invitar) }, Modifier.fillMaxWidth(), icon = StmIcons.personAdd, large = true)
        if (members.any { it.profile.id == me }) {
            Spacer(Modifier.height(8.dp))
            Btn("Salir del hogar", { saliendo = true }, Modifier.fillMaxWidth(), kind = BtnKind.Text, color = c.error)
        }
    }
}
