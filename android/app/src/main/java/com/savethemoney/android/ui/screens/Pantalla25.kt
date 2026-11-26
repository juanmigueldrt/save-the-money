package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.ChartRange
import com.savethemoney.android.data.InvestmentText
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.Donut
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.LineChart
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.SelectorSheet
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 25 Cartera: total, rentabilidad, evolución, reparto y activos. */
@Composable
fun Pantalla25(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    var range by remember { mutableIntStateOf(1) }
    var eligiendo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        inv.load()
        inv.loadMembers(session.backend)
    }
    val rangos = listOf(ChartRange.Week, ChartRange.Month, ChartRange.Year, ChartRange.All)
    val cartera = inv.portfolio
    val nuevo = {
        nav.go(Route.FormActivo())
    }
    StmScreen(
        topBar = {
            MediumTopBar("Cartera", onBack = nav::back) {
                IconBtn(StmIcons.eventRepeat, { nav.go(Route.InversionesRecurrentes) }, contentDescription = "Inversiones recurrentes")
                IconBtn(StmIcons.add, { if (inv.activeHoldings.isEmpty()) nuevo() else eligiendo = true }, contentDescription = "Comprar")
            }
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
        snackbar = inv.error?.let { e -> { Snackbar(e) } },
        overlay = if (eligiendo) {
            {
                SelectorSheet(
                    "Comprar activo",
                    inv.activeHoldings.map { h ->
                        h.trimmedName to {
                            nav.go(Route.Activo(h.id))
                        }
                    } + ("Añadir otro activo" to nuevo),
                ) { eligiendo = false }
            }
        } else {
            null
        },
    ) {
        Spacer(Modifier.height(7.5.dp))
        Text(if (cartera.mixedCurrencies) Money.MIXED else euros(cartera.value), style = StmType.displaySmall, color = c.onSurface)
        if (cartera.cost > 0) {
            Spacer(Modifier.height(4.5.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val texto = euros(cartera.gain, signed = true) + (cartera.gainFraction?.let { " (${InvestmentText.percent(it)})" } ?: "")
                Pill(texto, positive = cartera.gain >= 0, icon = if (cartera.gain >= 0) StmIcons.arrowUpward else null)
                Spacer(Modifier.width(8.dp))
                Text("desde el inicio", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(20.dp))
        if (inv.activeHoldings.isEmpty()) {
            StmCard {
                Text("Sin inversiones todavía", style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Añade un fondo, un ETF o una acción y apunta tus compras. Los precios los apuntas tú cuando quieras; la app no se conecta a ningún bróker.",
                    style = StmType.bodyMedium, color = c.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                Btn("Añadir un activo", nuevo)
            }
        } else {
            HugSegmented(rangos.map { it.title }, range) { range = it }
            Spacer(Modifier.height(16.dp))
            StmCard { LineChart(normalizar(inv.evolution(rangos[range]).map { it.value })) }
            if (cartera.allocation.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                val colores = cartera.allocation.map { it.assetClass.color() }
                StmCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Donut(cartera.allocation.mapIndexed { i, s -> Slice(s.fraction.toFloat(), colores[i]) }, 112.dp, 16.dp)
                        Spacer(Modifier.width(16.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            cartera.allocation.forEachIndexed { i, s -> Legend(colores[i], "${s.assetClass.title} ${Math.round(s.fraction * 100)} %") }
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            ListCard {
                inv.activeHoldings.forEachIndexed { i, h ->
                    if (i > 0) Divider()
                    val p = inv.position(h)
                    val base = if (p.quantity.signum() > 0) "${InvestmentText.quantity(p.quantity)} participaciones" else h.kind.title
                    ListItem(
                        h.trimmedName, if (h.ownerId != null) "$base · ${inv.ownerName(h.ownerId)}" else base,
                        leading = { LeadIcon(iconoActivo(h.kind), c.tertiaryContainer, c.onTertiaryContainer) },
                        trailing = {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(euros(p.value), style = StmType.labelLarge, color = c.onSurface)
                                p.gainFraction?.let { Text(InvestmentText.percent(it), style = StmType.bodySmall, color = c.onSurfaceVariant) }
                            }
                        },
                        onClick = {
                            nav.go(Route.Activo(h.id))
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Aviso("Esto no es asesoramiento de inversión. Los valores salen de los precios que apuntas a mano.")
    }
}
