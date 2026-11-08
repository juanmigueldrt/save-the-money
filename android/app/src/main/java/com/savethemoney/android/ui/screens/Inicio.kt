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
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
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

/** 04 Inicio: patrimonio, gastado, próximo cargo y últimos movimientos. */
@Composable
fun Pantalla04(nav: Nav) {
    val c = Stm.colors
    val name = LocalSession.current.profile?.name ?: ""
    StmScreen(
        topBar = {
            TopBar(null, navIcon = StmIcons.menu, onNav = { nav.tab(Tab.Mas) }) {
                IconBtn(StmIcons.search, { nav.go(5) }, contentDescription = "Buscar")
                Box(Modifier.size(40.dp).tap(CircleShape) { nav.go(28) }, contentAlignment = Alignment.Center) {
                    Avatar(name.take(1).uppercase(), c.primaryContainer, c.onPrimaryContainer, size = 32.dp)
                }
            }
            LargeTitle("Hola, $name", "Noviembre · 4 cuentas")
        },
        bottomBar = { NavBar(Tab.Inicio, nav::tab, badgeOnMore = true) },
        fab = { Fab("Añadir movimiento") { nav.go(7) } },
    ) {
        StmCard(onClick = { nav.go(17) }) {
            Text("Patrimonio neto", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(3.dp))
            Text("48.230 €", style = StmType.displaySmall, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Pill("+2,4% este mes")
                Spacer(Modifier.width(8.dp))
                Text("vs. octubre", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Stat("Gastado", "1.284 €", "de 2.400 € previstos", Modifier.weight(1f)) { nav.tab(Tab.Presupuesto) }
            Stat("Próximo cargo", "312 €", "Visa · 1 dic", Modifier.weight(1f)) { nav.go(11) }
        }
        Spacer(Modifier.height(16.dp))
        SectionHeader("Últimos movimientos", "Ver todo") { nav.go(5) }
        ListCard {
            ListHeader("Hoy")
            ListItem(
                "Supermercado Día", "Comida · Tarjeta compartida", trailingText = "−64,20 €",
                leading = { LeadIcon(StmIcons.shoppingCart) }, onClick = { nav.go(34) },
            )
            Divider()
            ListItem(
                "Nómina", "Ingresos · Cuenta principal", trailingText = "+2.150,00 €",
                leading = { LeadIcon(StmIcons.work, c.successContainer, c.onSuccessContainer) }, onClick = { nav.go(6) },
            )
            Divider()
            ListItem(
                "Repsol", "Transporte · Visa", trailingText = "−48,00 €",
                leading = { LeadIcon(StmIcons.localGasStation) }, onClick = { nav.go(34) },
            )
        }
    }
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
