package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.CalendarPayment
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.PaymentCalendar
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.LocalDate
import java.time.YearMonth

/** Calendario de pagos: el mes con un punto en los días con pagos; al tocar un día, sus pagos y los próximos. Fuera del diseño. */
@Composable
fun Pantalla43(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val c = Stm.colors
    val hoy = finance.today()
    var mes by remember { mutableStateOf(YearMonth.from(hoy)) }
    var dia by remember { mutableStateOf(hoy) }
    val inv = finance.investments
    val calendario = PaymentCalendar(
        finance.planning.series,
        finance.cards.cardAccounts.mapNotNull { a -> finance.cards.summary(a)?.let { a.name to it } },
        inv.plans,
    ) { id -> inv.holding(id)?.trimmedName ?: "Inversión" }
    val delMes = calendario.month(mes)
    val conPagos = delMes.map { it.day }.toSet()
    val pagos = delMes.filter { it.amount < 0 }.sumOf { -it.amount }
    val ingresos = delMes.filter { it.amount > 0 }.sumOf { it.amount }
    fun cambiarMes(n: Long) {
        mes = mes.plusMonths(n)
        dia = if (mes == YearMonth.from(hoy)) hoy else mes.atDay(1)
    }

    StmScreen(topBar = { TopBar("Calendario de pagos", onNav = nav::back) }) {
        StmCard {
            Text("Pagos de ${Fechas.mes(mes.atDay(1))}", style = StmType.labelMedium, color = c.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Text(Money.format(pagos), style = StmType.titleLarge, color = c.onSurface)
            if (ingresos > 0) {
                Spacer(Modifier.height(4.dp))
                Text("Ingresos previstos: ${Money.format(ingresos)}", style = StmType.bodySmall, color = c.success)
            }
        }
        Spacer(Modifier.height(16.dp))
        StmCard {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconBtn(StmIcons.chevronLeft, { cambiarMes(-1) }, contentDescription = "Mes anterior")
                val titulo = Fechas.mesTitulo(mes.atDay(1)) + if (mes.year != hoy.year) " ${mes.year}" else ""
                Text(titulo, Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface, textAlign = TextAlign.Center)
                IconBtn(StmIcons.chevronRight, { cambiarMes(1) }, contentDescription = "Mes siguiente")
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("L", "M", "X", "J", "V", "S", "D").forEach {
                    Box(Modifier.width(44.dp), contentAlignment = Alignment.Center) {
                        Text(it, style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            val hueco = mes.atDay(1).dayOfWeek.value - 1
            val dias = List<LocalDate?>(hueco) { null } + (1..mes.lengthOfMonth()).map(mes::atDay)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                dias.chunked(7).forEach { semana ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        (semana + List(7 - semana.size) { null }).forEach { d ->
                            val (bg, fg) = when (d) {
                                null -> Color.Transparent to c.onSurface
                                dia -> c.primary to c.onPrimary
                                hoy -> c.secondaryContainer to c.onSecondaryContainer
                                else -> Color.Transparent to c.onSurface
                            }
                            Column(
                                Modifier.size(44.dp).clip(CircleShape).background(bg)
                                    .let { m -> if (d != null) m.tap(CircleShape) { dia = d } else m },
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                            ) {
                                if (d != null) {
                                    Text("${d.dayOfMonth}", style = StmType.bodyMedium, color = fg)
                                    Spacer(Modifier.height(2.dp))
                                    // El punto marca los días con algún pago o ingreso.
                                    Box(Modifier.size(5.dp).clip(CircleShape).background(if (d in conPagos) (if (d == dia) c.onPrimary else c.primary) else Color.Transparent))
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(Fechas.dia(dia, hoy))
            val delDia = delMes.filter { it.day == dia }
            if (delDia.isEmpty()) ListItem("Sin pagos este día")
            delDia.forEachIndexed { i, p ->
                if (i > 0) Divider(inset = 16.dp)
                FilaPagoPrevisto(p, p.source)
            }
        }
        Spacer(Modifier.height(16.dp))
        val proximos = calendario.upcoming(dia)
        ListCard {
            ListHeader("Próximos")
            if (proximos.isEmpty()) ListItem("No hay pagos previstos")
            proximos.forEachIndexed { i, p ->
                if (i > 0) Divider(inset = 16.dp)
                FilaPagoPrevisto(p, "${Fechas.dia(p.day, hoy)} · ${p.source}")
            }
        }
    }
}

@Composable
private fun FilaPagoPrevisto(p: CalendarPayment, detalle: String) {
    val c = Stm.colors
    ListItem(p.name, detalle, trailing = {
        Text(Money.format(p.amount, signed = true), style = StmType.labelLarge, color = if (p.amount > 0) c.success else c.onSurface)
    })
}
