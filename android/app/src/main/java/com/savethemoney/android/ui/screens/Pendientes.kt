package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.WeeklySummary
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

// PendingViews.swift de iOS: pagos fijos pendientes de confirmar y resumen semanal.

/** Los cargos de pagos fijos que han llegado y esperan confirmación. Sale en Resumen sólo si hay alguno. */
@Composable
internal fun PendientesCard(finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    val planning = finance.planning
    val pendientes = planning.pending
    if (pendientes.isEmpty()) return
    val action = rememberAction()
    StmCard {
        Text(stringResource(R.string.pendientes_pendientes_de_confirmar), style = StmType.titleMedium, color = c.onSurface)
        Text(stringResource(R.string.pendientes_aun_no_cuentan_en_tus_saldos), style = StmType.bodySmall, color = c.onSurfaceVariant)
        pendientes.take(5).forEach { item ->
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(item.series.trimmedName, Modifier.weight(1f), style = StmType.titleSmall, color = c.onSurface)
                Text(Money.format(item.charge.amountMinor), style = StmType.titleSmall, color = c.onSurface)
            }
            Text(
                listOfNotNull(Fechas.corto(item.charge.due), finance.account(item.series.accountId)?.name).joinToString(" · "),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Btn(stringResource(R.string.comun_confirmar), {
                    nav.go(Route.ConfirmarCargo(item.id))
                })
                Btn(stringResource(R.string.pendientes_no_se_ha_cobrado), { action.run { planning.skip(item) } }, kind = BtnKind.Outlined, enabled = !action.busy)
            }
        }
        if (pendientes.size > 5) {
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.pendientes_y_mas, pendientes.size - 5), style = StmType.bodySmall, color = c.onSurfaceVariant)
        }
        action.error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = StmType.bodySmall, color = c.error)
        }
    }
}

/** La semana pasada en una línea; lleva al resumen completo (47). */
@Composable
internal fun SemanaCard(finance: FinanceModel, nav: Nav) {
    val c = Stm.colors
    val resumen = WeeklySummary(finance.recent, finance.categories, finance.today())
    StmCard(onClick = { nav.go(Route.ResumenSemanal) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.pendientes_la_semana_pasada, resumen.title), Modifier.weight(1f), style = StmType.labelMedium, color = c.onSurfaceVariant)
            StmIcon(StmIcons.chevronRight, c.onSurfaceVariant)
        }
        Text(Money.format(resumen.week.spent), style = StmType.displaySmall, color = c.onSurface)
        Text(resumen.changeText, style = StmType.bodyMedium, color = c.onSurfaceVariant)
    }
}
