package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.NetWorth
import com.savethemoney.android.data.NetWorthProjection
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 17 Patrimonio neto: cifra, variación, evolución por periodo y lista de activos y deudas. */
@Composable
fun Pantalla17(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val tracking = finance.tracking
    val c = Stm.colors
    var range by remember { mutableIntStateOf(1) }
    LaunchedEffect(finance.recent) { tracking.loadMovements() }
    val saldos = finance.activeAccounts.map { it to finance.balance(it) }
    val hoy = NetWorth.current(finance.accounts, finance.balances, finance.today())
    val meses = listOf(2, 7, 13, tracking.monthsWithData)[range]
    // Rehacer el patrimonio recorre todos los movimientos: sólo cuando cambian sus datos, no en cada recomposición.
    val dia = tracking.today()
    val historia = remember(tracking.allMovements, finance.accounts, meses, dia) { tracking.history(finance.accounts, meses) }
    val cambio = (historia.lastOrNull()?.net ?: 0) - (historia.firstOrNull()?.net ?: 0)
    val tramo = listOf("en 1 mes", "en 6 meses", "en 1 año", "desde el principio")[range]
    val inversiones = saldos.filter { (a, b) -> a.kind == AccountKind.Investment && b > 0 }.sumOf { it.second }
    val tarjetas = saldos.filter { (a, b) -> a.kind == AccountKind.CreditCard && b < 0 }.sumOf { it.second }
    val otrasDeudas = saldos.filter { (a, b) -> a.kind != AccountKind.CreditCard && b < 0 }.sumOf { it.second }
    StmScreen(
        topBar = {
            TopBar("Patrimonio neto", onNav = nav::back) {
                IconBtn(StmIcons.add, {
                    nav.go(Route.FormCuenta())
                }, contentDescription = "Añadir cuenta")
            }
        },
        snackbar = tracking.error?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        Text(euros(hoy.net), style = StmType.displayMedium, color = if (hoy.net < 0) c.error else c.onSurface)
        Spacer(Modifier.height(4.dp))
        Pill("${euros(cambio, signed = true)} $tramo", positive = cambio >= 0, icon = if (cambio >= 0) StmIcons.arrowUpward else null)
        Spacer(Modifier.height(20.dp))
        SegmentedWrap(listOf("1M", "6M", "1A", "Todo"), range) { range = it }
        Spacer(Modifier.height(16.dp))
        StmCard {
            LineChart(normalizar(historia.map { it.net }), plotHeight = 160.dp)
        }
        val prevision = remember(tracking.allMovements, finance.accounts, dia) {
            if (finance.accounts.isEmpty()) null else NetWorthProjection.of(tracking.history(finance.accounts, 7))
        }
        if (prevision != null) {
            Spacer(Modifier.height(16.dp))
            StmCard {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("A final de año", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                    Text(euros(prevision.endOfYear), style = StmType.labelLarge, color = if (prevision.endOfYear < 0) c.error else c.onSurface)
                }
                Spacer(Modifier.height(8.dp))
                LineChart(normalizar(prevision.points.map { it.second }), plotHeight = 80.dp, dashed = true)
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    prevision.points.forEach { (mes, _) -> Text(Fechas.mes(mes.atDay(1)).take(3), style = StmType.labelSmall, color = c.onSurfaceVariant) }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "Si sigue como los últimos meses (${euros(prevision.monthlyChange, signed = true)} al mes de media). Es una estimación, no una promesa.",
                    style = StmType.bodySmall, color = c.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Activos")
            ListItem(
                "Cuentas", leading = { LeadIcon(StmIcons.accountBalance) },
                trailingText = euros(hoy.assets - inversiones), onClick = { nav.go(Route.Movimientos) },
            )
            Divider()
            ListItem(
                "Inversiones", leading = { LeadIcon(StmIcons.candlestickChart, c.tertiaryContainer, c.onTertiaryContainer) },
                trailingText = euros(inversiones), onClick = { nav.go(Route.Cartera) },
            )
            ListHeader("Deudas")
            ListItem(
                "Tarjetas", leading = { LeadIcon(StmIcons.creditCard, c.errorContainer, c.onErrorContainer) },
                trailingText = euros(tarjetas), onClick = { nav.go(Route.Tarjetas) },
            )
            if (otrasDeudas != 0L) {
                Divider()
                ListItem("Otras deudas", leading = { LeadIcon(StmIcons.description, c.errorContainer, c.onErrorContainer) }, trailingText = euros(otrasDeudas))
            }
        }
        // El diseño no dibuja cómo se llega a estas dos; en iOS están en el mismo apartado.
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListItem("Informes", leading = { LeadIcon(StmIcons.monitoring) }, trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(Route.Informes) })
            Divider()
            ListItem("Score crediticio", leading = { LeadIcon(StmIcons.creditScore) }, trailing = { StmIcon(StmIcons.chevronRight, c.onSurfaceVariant) }, onClick = { nav.go(Route.Score) })
        }
        Spacer(Modifier.height(16.dp))
        Text(
            "Se calcula con el saldo inicial de cada cuenta y sus movimientos. Las cuentas archivadas no cuentan.",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
    }
}
