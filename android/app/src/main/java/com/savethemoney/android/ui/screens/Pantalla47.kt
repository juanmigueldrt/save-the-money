package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.WeeklySummary
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Progress
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 47 Resumen semanal: total frente a la anterior, gastos más grandes, categorías y mapa de calor. */
@Composable
fun Pantalla47(nav: Nav) {
    val c = Stm.colors
    val finance = LocalSession.current.finance ?: return
    var semana by remember { mutableIntStateOf(0) }
    val resumen = WeeklySummary(finance.recent, finance.categories, finance.today(), includeCurrent = semana == 1)
    StmScreen(topBar = { TopBar("Resumen semanal", navIcon = StmIcons.arrowBack, onNav = nav::back) }) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf("La pasada", "Esta semana"), semana, { semana = it })
            StmCard {
                Text(resumen.title, style = StmType.labelMedium, color = c.onSurfaceVariant)
                Text(Money.format(resumen.week.spent), style = StmType.displaySmall, color = c.onSurface)
                Text(resumen.changeText, style = StmType.bodyMedium, color = c.onSurfaceVariant)
            }
            ListCard {
                ListItem("Ingresos", trailingText = Money.format(resumen.week.income))
                Divider()
                ListItem("Semana anterior", trailingText = Money.format(resumen.previous.spent))
            }
            ListCard {
                ListItem("Gastos más grandes")
                if (resumen.biggest.isEmpty()) {
                    Box(Modifier.padding(horizontal = 16.dp)) { Vacio("No hay gastos esta semana.") }
                }
                resumen.biggest.forEach { m ->
                    Divider()
                    ListItem(
                        m.description, "${DIAS[m.day.dayOfWeek.value - 1]}, ${Fechas.corto(m.day)}",
                        trailingText = Money.format(-m.amountMinor),
                    )
                }
            }
            if (resumen.topCategories.isNotEmpty()) {
                StmCard {
                    Text("En qué se fue", style = StmType.titleMedium, color = c.onSurface)
                    resumen.topCategories.forEach { row ->
                        Spacer(Modifier.height(12.dp))
                        Row {
                            Text(row.title, Modifier.weight(1f), style = StmType.bodyMedium, color = c.onSurface)
                            Text(Money.format(row.amount), style = StmType.titleSmall, color = c.onSurface)
                        }
                        Spacer(Modifier.height(4.dp))
                        Progress(row.share.toFloat())
                    }
                }
            }
            StmCard {
                Text("Día a día", style = StmType.titleMedium, color = c.onSurface)
                Spacer(Modifier.height(12.dp))
                MapaCalor(resumen.heatmap)
                Spacer(Modifier.height(8.dp))
                Text("Cuanto más oscuro, más gastaste ese día. Las últimas 6 semanas.", style = StmType.bodySmall, color = c.onSurfaceVariant)
            }
        }
    }
}

private val DIAS = listOf("Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo")

/** Cuadrícula de lunes a domingo, una fila por semana. */
@Composable
private fun MapaCalor(semanas: List<List<WeeklySummary.Day>>) {
    val c = Stm.colors
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                Text(it, Modifier.weight(1f), style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }
        semanas.forEach { semana ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                semana.forEach { d ->
                    val color = if (d.spent == 0L) c.surfaceContainer else c.primary.copy(alpha = (0.2 + 0.8 * d.intensity).toFloat())
                    Box(
                        Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(4.dp)).background(color)
                            .semantics { contentDescription = "${DIAS[d.day.dayOfWeek.value - 1]} ${Fechas.corto(d.day)}: ${Money.format(d.spent)}" },
                    )
                }
            }
        }
    }
}
