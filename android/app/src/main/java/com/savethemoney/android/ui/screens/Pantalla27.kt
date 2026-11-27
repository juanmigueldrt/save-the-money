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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.RecurrenceUnit
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.time.YearMonth

/** 27 Inversiones recurrentes: calendario del mes con los días de aportación y planes. */
@Composable
fun Pantalla27(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val inv = finance.investments
    val c = Stm.colors
    val hoy = finance.today()
    val mes = YearMonth.from(hoy)
    val cargos = inv.charges(mes)
    val diasConCargo = cargos.map { it.due.dayOfMonth }.toSet()
    val action = rememberAction()
    val nuevo = {
        nav.go(Route.FormPlan())
    }
    StmScreen(
        topBar = {
            TopBar(stringResource(R.string.inversiones_recurrentes_inversiones_recurrentes), onNav = nav::back) {
                if (inv.activeHoldings.isNotEmpty()) IconBtn(StmIcons.add, nuevo, contentDescription = stringResource(R.string.comun_anadir))
            }
        },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        StmCard {
            Text(Fechas.mesTitulo(hoy), style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf(stringResource(R.string.comun_inicial_lunes), stringResource(R.string.comun_inicial_martes), stringResource(R.string.comun_inicial_miercoles), stringResource(R.string.comun_inicial_jueves), stringResource(R.string.comun_inicial_viernes), stringResource(R.string.comun_inicial_sabado), stringResource(R.string.comun_inicial_domingo)).forEach {
                    Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) {
                        Text(it, style = StmType.labelMedium, color = c.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            val hueco = mes.atDay(1).dayOfWeek.value - 1
            val dias = List<Int?>(hueco) { null } + (1..mes.lengthOfMonth()).toList()
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                dias.chunked(7).forEach { semana ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        (semana + List(7 - semana.size) { null }).forEach { dia ->
                            val (bg, fg) = when (dia) {
                                hoy.dayOfMonth -> c.primary to c.onPrimary
                                in diasConCargo -> c.secondaryContainer to c.onSecondaryContainer
                                else -> Color.Transparent to c.onSurface
                            }
                            Box(Modifier.size(40.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
                                if (dia != null) Text("$dia", style = StmType.bodyMedium, color = fg)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        val (activos, pausados) = inv.planCounts
        Aviso(
            if (pausados > 0) pluralStringResource(R.plurals.inversiones_recurrentes_al_mes_en_planes_y_pausa, activos, Money.format(inv.monthlyPlanned), activos, pausados)
            else pluralStringResource(R.plurals.inversiones_recurrentes_al_mes_en_planes, activos, Money.format(inv.monthlyPlanned), activos),
        )
        Spacer(Modifier.height(16.dp))
        if (inv.livePlans.isNotEmpty()) {
            ListCard {
                inv.livePlans.forEachIndexed { i, plan ->
                    if (i > 0) Divider()
                    val h = inv.holding(plan.holdingId)
                    val cuando = if (plan.unit == RecurrenceUnit.Month && plan.every == 1) stringResource(R.string.inversiones_recurrentes_el_dia_de_cada_mes, plan.startDay.dayOfMonth) else plan.recurrence.title.lowercase()
                    ListItem(
                        h?.trimmedName ?: stringResource(R.string.inversiones_recurrentes_activo), "${euros(plan.amountMinor)} $cuando".let { if (plan.isPaused) stringResource(R.string.inversiones_recurrentes_en_pausa, it) else it },
                        leading = {
                            if (plan.isPaused) LeadIcon(iconoActivo(h?.kind ?: InvestmentKind.Fund), c.surfaceContainerHighest, c.onSurfaceVariant)
                            else LeadIcon(iconoActivo(h?.kind ?: InvestmentKind.Fund), c.tertiaryContainer, c.onTertiaryContainer)
                        },
                        trailing = { StmSwitch(!plan.isPaused) { on -> action.run { inv.setPaused(!on, plan) } } },
                        onClick = {
                            nav.go(Route.FormPlan(plan.id))
                        },
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
        } else if (inv.activeHoldings.isEmpty()) {
            Aviso(stringResource(R.string.inversiones_recurrentes_anade_antes_un_activo_en_la))
            Spacer(Modifier.height(16.dp))
        } else {
            Btn(stringResource(R.string.form_plan_nuevo_plan), nuevo, Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
        }
        if (cargos.isNotEmpty()) {
            ListCard {
                ListHeader(stringResource(R.string.inversiones_recurrentes_este_mes))
                cargos.forEachIndexed { i, cargo ->
                    if (i > 0) Divider()
                    ListItem(Fechas.dia(cargo.due, hoy), inv.holding(cargo.plan.holdingId)?.trimmedName, trailingText = euros(cargo.plan.amountMinor))
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        Aviso(stringResource(R.string.inversiones_recurrentes_un_plan_no_compra_nada_solo))
    }
}
