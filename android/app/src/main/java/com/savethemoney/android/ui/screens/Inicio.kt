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
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.iconoCuenta
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Fab
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
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
    val anadir = { nav.go(if (cuentas.isEmpty()) 9 else 7) }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = StmIcons.menu, onNav = { nav.tab(Tab.Mas) }) {
                IconBtn(StmIcons.search, { nav.go(5) }, contentDescription = "Buscar")
                Box(Modifier.size(40.dp).tap(CircleShape) { nav.go(28) }, contentAlignment = Alignment.Center) {
                    Avatar(name.take(1).uppercase(), c.primaryContainer, c.onPrimaryContainer, size = 32.dp)
                }
            }
            LargeTitle("Hola, $name", "${Fechas.mesTitulo(hoy)} · ${cuentas.size} ${if (cuentas.size == 1) "cuenta" else "cuentas"}")
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab, badgeOnMore = true) },
        fab = { Fab("Añadir movimiento", onClick = anadir) },
    ) {
        StmCard(onClick = { nav.go(17) }) {
            Text("Patrimonio neto", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.dp))
            Text(Money.format(total, decimals = false), style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            if (variacion != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pill(porcentaje(variacion) + " este mes", positive = variacion >= 0, icon = if (variacion >= 0) StmIcons.arrowUpward else null)
                    Spacer(Modifier.width(8.dp))
                    Text("vs. ${Fechas.mes(hoy.minusMonths(1))}", style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // Presupuesto (paso 4) y tarjetas (paso 6) aún no calculan: en la app real no se inventan cifras.
            Stat(
                "Gastado", Money.format(finance.spentThisMonth, decimals = false),
                if (session.capture) "de 2.400 € previstos" else "este mes", Modifier.weight(1f),
            ) { nav.tab(Tab.Presupuesto) }
            Stat(
                "Próximo cargo", when {
                    session.capture -> "312 €"
                    proximo != null -> Money.format(proximo.amount, decimals = false)
                    else -> "—"
                },
                when {
                    session.capture -> "Visa · 1 dic"
                    proximo != null -> "${proximo.series.trimmedName} · ${Fechas.corto(proximo.due)}"
                    else -> "Sin cargos a la vista"
                },
                Modifier.weight(1f),
            ) { nav.go(if (session.capture) 11 else 20) }
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader("Últimos movimientos", "Ver todo") { nav.go(5) }
        if (finance.recent.isEmpty()) {
            Vacio("Todavía no hay movimientos.")
        } else {
            ListaMovimientos(finance.recent.take(3), finance) { m ->
                finance.selectedMovementId = m.id
                nav.go(34)
            }
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader("Cuentas", "Añadir") { nav.go(9) }
        if (cuentas.isEmpty()) {
            Vacio("Añade tu primera cuenta para empezar a apuntar movimientos o importar un CSV del banco.")
        } else {
            ListCard {
                cuentas.forEachIndexed { i, cuenta ->
                    if (i > 0) Divider()
                    ListItem(
                        cuenta.name,
                        if (cuenta.isShared) "${cuenta.kind.title} · compartida" else cuenta.kind.title,
                        trailingText = Money.format(finance.balance(cuenta)),
                        leading = { LeadIcon(iconoCuenta(cuenta.kind)) },
                        onClick = {
                            finance.selectedAccountId = cuenta.id
                            nav.go(6)
                        },
                    )
                }
            }
        }
        finance.error?.let {
            Spacer(Modifier.height(16.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
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
