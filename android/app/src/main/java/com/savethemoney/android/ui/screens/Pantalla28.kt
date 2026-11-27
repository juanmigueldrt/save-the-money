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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.MONTH_START_DAYS
import com.savethemoney.android.data.MemberRole
import com.savethemoney.android.data.OWNER_MUST_TRANSFER
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
    val fallo = miembros?.exceptionOrNull()?.let { (it as? AppError)?.message ?: stringResource(R.string.hogar_no_se_han_podido_cargar_los) }
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
                IconBtn(StmIcons.arrowBack, nav::back, contentDescription = stringResource(R.string.comun_atras))
                Spacer(Modifier.weight(1f))
                // Sólo el dueño puede cambiar el nombre (RLS de households).
                if (soyDueno) {
                    IconBtn(StmIcons.edit, { nombre = session.household?.name.orEmpty() }, contentDescription = stringResource(R.string.hogar_cambiar_el_nombre_del_hogar))
                }
            }
            Text(stringResource(R.string.hogar_hogar), Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp), style = StmType.headlineMedium, color = c.onSurface)
            Text(session.household?.name.orEmpty(), Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.bodyLarge, color = c.onSurfaceVariant)
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        overlay = quitando?.let { m ->
            {
                StmDialog(
                    stringResource(R.string.hogar_quitar_a_del_hogar, m.profile.name),
                    stringResource(R.string.hogar_aviso_quitar_miembro, com.savethemoney.android.data.RemovedHousehold.EXPORT_DAYS),
                    icon = StmIcons.personRemove,
                    onDismiss = { quitando = null },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { quitando = null }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.hogar_quitar), {
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
                    stringResource(R.string.hogar_hacer_propietario_a, m.profile.name),
                    stringResource(R.string.hogar_aviso_traspasar),
                    onDismiss = { traspasando = null },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { traspasando = null }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.hogar_hacer_propietario), {
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
                    stringResource(R.string.hogar_nombre_del_hogar), stringResource(R.string.hogar_lo_veran_todos_los_miembros),
                    onDismiss = { nombre = null },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { nombre = null }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_guardar), {
                            val h = session.household ?: return@Btn
                            action.run {
                                session.renameHousehold(h, texto)
                                nombre = null
                            }
                        }, kind = BtnKind.Text, enabled = !action.busy)
                    },
                ) {
                    Spacer(Modifier.height(16.dp))
                    FilledField(stringResource(R.string.comun_nombre), texto, { nombre = it }, autoFocus = true)
                    action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) }
                }
            }
        } ?: if (saliendo) {
            {
                StmDialog(
                    stringResource(R.string.hogar_salir_del_hogar),
                    when {
                        duenoConOtros -> OWNER_MUST_TRANSFER
                        members.size == 1 -> stringResource(R.string.hogar_aviso_salir) + " " + stringResource(R.string.hogar_aviso_ultimo_miembro)
                        else -> stringResource(R.string.hogar_aviso_salir)
                    },
                    icon = StmIcons.logout,
                    onDismiss = { saliendo = false },
                    actions = {
                        Btn(if (duenoConOtros) stringResource(R.string.comun_entendido) else stringResource(R.string.comun_cancelar), { saliendo = false }, kind = BtnKind.Text)
                        if (!duenoConOtros) {
                            Btn(stringResource(R.string.hogar_salir), {
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
                    stringResource(R.string.hogar_dia_de_inicio_del_mes),
                    MONTH_START_DAYS.map { d -> stringResource(R.string.hogar_dia, d) to { action.run { session.setMonthStartDay(d) } } },
                    { eligeDia = false },
                )
            }
        } else nombreVisible?.let { texto ->
            {
                StmDialog(
                    stringResource(R.string.hogar_tu_nombre_visible), stringResource(R.string.hogar_es_como_te_ven_los_demas),
                    onDismiss = { nombreVisible = null },
                    actions = {
                        Btn(stringResource(R.string.comun_cancelar), { nombreVisible = null }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_guardar), {
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
                    FilledField(stringResource(R.string.hogar_nombre_visible), texto, { nombreVisible = it }, autoFocus = true)
                    action.error?.let { Spacer(Modifier.height(8.dp)); Text(it, style = StmType.bodySmall, color = c.error) }
                }
            }
        },
    ) {
        if (session.households.size > 1) {
            ListCard {
                ListHeader(stringResource(R.string.hogar_tus_hogares))
                session.households.forEachIndexed { i, h ->
                    if (i > 0) Divider()
                    val abierto = h.id == session.household?.id
                    ListItem(
                        h.name, if (abierto) stringResource(R.string.hogar_abierto) else stringResource(R.string.hogar_abrir_este_hogar),
                        onClick = if (abierto || action.busy) null else ({ action.run { session.open(h) } }),
                    )
                }
            }
            Text(
                stringResource(R.string.hogar_cada_hogar_tiene_sus_propias),
                Modifier.padding(16.dp), style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
        ListCard {
            ListHeader(stringResource(R.string.hogar_ajustes))
            val dia = session.household?.monthStartDay ?: 1
            // Sólo el dueño puede cambiarlo (RLS de households); los demás lo ven.
            ListItem(
                stringResource(R.string.hogar_inicio_del_mes), if (soyDueno) stringResource(R.string.hogar_dia, dia) else stringResource(R.string.hogar_dia_solo_quien_creo_el_hogar, dia),
                onClick = if (soyDueno) ({ eligeDia = true }) else null,
            )
            Divider()
            ListItem(stringResource(R.string.hogar_tu_nombre_visible), session.profile?.name, onClick = { nombreVisible = session.profile?.displayName.orEmpty() })
        }
        Text(
            stringResource(R.string.hogar_presupuestos_informes_y_este_mes),
            Modifier.padding(16.dp), style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
        // Lo que no se pudo guardar desde una hoja (día de inicio, cambiar de hogar): el aviso del servidor.
        if (!eligeDia && nombreVisible == null && nombre == null && quitando == null && traspasando == null && !saliendo) {
            action.error?.let { Text(it, Modifier.padding(horizontal = 16.dp), style = StmType.bodySmall, color = c.error) }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.hogar_miembros))
            members.forEachIndexed { i, m ->
                if (i > 0) Divider()
                val yo = m.profile.id == me
                ListItem(
                    m.profile.name, stringResource(if (m.role == MemberRole.Owner) { if (yo) R.string.hogar_tu_propietario else R.string.hogar_propietario } else { if (yo) R.string.hogar_tu_miembro else R.string.hogar_miembro }),
                    leading = { Avatar(m.profile.name.take(1).uppercase()) },
                    // Solo el dueño puede quitar a otros; el diseño deja 24 dp a la derecha del icono final.
                    trailing = if (m.profile.id == me || !soyDueno) null else ({
                        IconBtn(StmIcons.personRemove, { quitando = m }, contentDescription = stringResource(R.string.hogar_quitar_del_hogar))
                    }),
                )
                // Debajo de la fila y no junto al icono: con letra grande, un botón de texto ahí dejaría sin sitio al nombre.
                if (m.profile.id != me && soyDueno) {
                    Btn(stringResource(R.string.hogar_hacer_propietario), { traspasando = m }, Modifier.padding(start = 60.dp, bottom = 4.dp), kind = BtnKind.Text)
                }
            }
        }
        // Sin red la lista sale vacía: el aviso y «Reintentar» dicen que no es que el hogar no tenga miembros.
        fallo?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, Modifier.padding(horizontal = 16.dp), style = StmType.bodySmall, color = c.error)
            Btn(stringResource(R.string.comun_reintentar), { recarga++ }, kind = BtnKind.Text)
        }
        Spacer(Modifier.height(16.dp))
        val shape = RoundedCornerShape(12.dp)
        StmCard(Modifier.fillMaxWidth().border(1.dp, c.outlineVariant, shape), color = c.surface) {
            Text(stringResource(R.string.hogar_que_compartis), style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.hogar_metas_pagos_fijos_y_gastos),
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Btn(stringResource(R.string.hogar_invitar_a_alguien), { nav.go(Route.Invitar) }, Modifier.fillMaxWidth(), icon = StmIcons.personAdd, large = true)
        if (members.any { it.profile.id == me }) {
            Spacer(Modifier.height(8.dp))
            Btn(stringResource(R.string.hogar_salir_del_hogar_2), { saliendo = true }, Modifier.fillMaxWidth(), kind = BtnKind.Text, color = c.error)
        }
    }
}
