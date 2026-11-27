package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.Vista
import com.savethemoney.android.ui.rememberAction
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.savethemoney.android.ui.iconoCuenta
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.SectionHeader
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import com.savethemoney.android.ui.titulo
import kotlin.math.abs

/** 04 Inicio: patrimonio, gastado, próximo cargo y últimos movimientos. */
@Composable
fun Pantalla04(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val name = session.profile?.name ?: ""
    val hoy = finance.today()
    val cuentas = finance.activeAccounts
    val total = finance.totalBalance
    val inicioMes = total - finance.netThisMonth
    val variacion = if (inicioMes > 0) finance.netThisMonth * 1000 / inicioMes else null
    val proximo = finance.planning.nextExpense
    val anadir = { nav.go(if (cuentas.isEmpty()) Route.FormCuenta() else Route.FormMovimiento()) }
    val recarga = rememberAction()
    StmScreen(
        topBar = {
            TopBar(null, navIcon = StmIcons.menu, onNav = { nav.tab(Tab.Mas) }) {
                IconBtn(
                    if (Vista.incognito) StmIcons.visibilityOff else StmIcons.visibility, { Vista.setIncognito(!Vista.incognito) },
                    contentDescription = if (Vista.incognito) stringResource(R.string.comun_mostrar_importes) else stringResource(R.string.comun_ocultar_importes),
                )
                IconBtn(StmIcons.search, { nav.go(Route.Movimientos) }, contentDescription = stringResource(R.string.comun_buscar))
                Box(Modifier.size(40.dp).tap(CircleShape) { nav.go(Route.Hogar) }, contentAlignment = Alignment.Center) {
                    Avatar(name.take(1).uppercase(), c.primaryContainer, c.onPrimaryContainer, size = 32.dp)
                }
            }
            LargeTitle(stringResource(R.string.inicio_hola, name), pluralStringResource(R.plurals.inicio_mes_y_cuentas, cuentas.size, Fechas.mesTitulo(hoy), cuentas.size))
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab, badgeOnMore = true) },
        fab = { Fab(stringResource(R.string.inicio_anadir_movimiento), onClick = anadir) },
    ) {
        StmCard(onClick = { nav.go(Route.Patrimonio) }) {
            Text(stringResource(R.string.patrimonio_patrimonio_neto), style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.dp))
            Text(Money.format(total, decimals = false), style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            if (variacion != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pill(stringResource(R.string.inicio_este_mes, porcentaje(variacion)), positive = variacion >= 0, icon = if (variacion >= 0) StmIcons.arrowUpward else null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.inicio_vs, Fechas.mes(hoy.minusMonths(1))), style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // Presupuesto (paso 4) y tarjetas (paso 6) aún no calculan: en la app real no se inventan cifras.
            Stat(stringResource(R.string.inicio_gastado), Money.format(finance.spentThisMonth, decimals = false), stringResource(R.string.inicio_este_mes_2), Modifier.weight(1f)) { nav.tab(Tab.Presupuesto) }
            Stat(
                stringResource(R.string.comun_proximo_cargo), proximo?.let { Money.format(it.amount, decimals = false) } ?: "—",
                proximo?.let { "${it.series.trimmedName} · ${Fechas.corto(it.due)}" } ?: stringResource(R.string.inicio_sin_cargos_a_la_vista),
                Modifier.weight(1f),
            ) { nav.go(Route.PagosFijos) }
        }
        if (finance.planning.pending.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            PendientesCard(finance, nav)
        }
        Spacer(Modifier.height(16.dp))
        GastarHoyCard(finance.budgets, finance) { nav.tab(Tab.Presupuesto) }
        if (finance.budgets.extraBudgets.any { it.isFavorite }) {
            Spacer(Modifier.height(16.dp))
            FavoritoExtraCard(finance.budgets, finance, nav)
        }
        Spacer(Modifier.height(16.dp))
        SemanaCard(finance, nav)
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem(
                stringResource(R.string.calendario_calendario_de_pagos), stringResource(R.string.inicio_lo_que_se_cobra_cada_dia),
                leading = { LeadIcon(StmIcons.calendarMonth, c.secondaryContainer, c.onSecondaryContainer) },
                trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) },
                onClick = { nav.go(Route.Calendario) },
            )
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader(stringResource(R.string.inicio_ultimos_movimientos), stringResource(R.string.inicio_ver_todo)) { nav.go(Route.Movimientos) }
        if (finance.recent.isEmpty()) {
            Vacio(stringResource(R.string.inicio_todavia_no_hay_movimientos))
        } else {
            ListaMovimientos(finance.recent.take(3), finance) { m ->
                finance.tappedMovement = m
                nav.go(Route.DetalleMovimiento(m.id))
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader(stringResource(R.string.inicio_cuentas), stringResource(R.string.comun_anadir)) { nav.go(Route.FormCuenta()) }
        if (cuentas.isEmpty()) {
            Vacio(stringResource(R.string.inicio_anade_tu_primera_cuenta_para))
        } else {
            ListCard {
                cuentas.forEachIndexed { i, cuenta ->
                    if (i > 0) Divider()
                    ListItem(
                        cuenta.name,
                        if (cuenta.isShared) stringResource(R.string.comun_tipo_cuenta_compartida, stringResource(cuenta.kind.titulo)) else stringResource(cuenta.kind.titulo),
                        trailingText = Money.format(finance.balance(cuenta)),
                        leading = { LeadIcon(iconoCuenta(cuenta.kind)) },
                        onClick = {
                            nav.go(Route.Cuenta(cuenta.id))
                        },
                    )
                }
            }
        }
        val archivadas = finance.archivedAccounts
        if (archivadas.isNotEmpty()) {
            var abiertas by remember { mutableStateOf(false) }
            Spacer(Modifier.height(16.dp))
            ListCard {
                ListItem(
                    stringResource(R.string.inicio_archivadas, archivadas.size), if (abiertas) null else stringResource(R.string.inicio_abrelas_para_verlas_o),
                    trailing = { StmIcon(if (abiertas) StmIcons.arrowDropDown else StmIcons.chevronRight, c.onSurfaceVariant) },
                    onClick = { abiertas = !abiertas },
                )
                if (abiertas) {
                    archivadas.forEach { cuenta ->
                        Divider()
                        ListItem(
                            cuenta.name, stringResource(R.string.inicio_archivada, stringResource(cuenta.kind.titulo)),
                            trailingText = Money.format(finance.balance(cuenta)),
                            trailingColor = c.onSurfaceVariant,
                            leading = { LeadIcon(iconoCuenta(cuenta.kind)) },
                            onClick = {
                                nav.go(Route.Cuenta(cuenta.id))
                            },
                        )
                    }
                }
            }
        }
        finance.error?.let {
            Spacer(Modifier.height(16.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
            // Es un problema de carga (también tras guardar algo): se reintenta cargando, nunca guardando otra vez.
            Btn(stringResource(R.string.comun_reintentar), { recarga.run { finance.load() } }, kind = BtnKind.Text, enabled = !recarga.busy)
        }
    }
}

/** "+2,4%" a partir de milésimas. */
private fun porcentaje(milesimas: Long): String {
    val valor = abs(milesimas)
    return "${if (milesimas < 0) Money.MINUS else "+"}${valor / 10},${valor % 10}%"
}

/** Tarjeta pequeña con etiqueta, cifra serif y nota. */
@Composable
fun Stat(label: String, value: String, note: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val c = Stm.colors
    StmCard(modifier, onClick = onClick) {
        Text(label, style = StmType.labelMedium, color = c.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(value, style = StmType.titleLarge, color = c.onSurface)
        Text(note, style = StmType.bodySmall, color = c.onSurfaceVariant)
    }
}
