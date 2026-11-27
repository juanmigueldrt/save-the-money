package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MonthlyBills
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.compartir
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.escribirPdfPagos
import com.savethemoney.android.ui.ficheroExportar
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.YearMonth

/** Pagos del mes (no está en el diseño, sí en iOS): resumen y PDF para compartir o imprimir. */
@Composable
fun Pantalla36(nav: Nav) {
    val finance = LocalSession.current.finance ?: return
    val c = Stm.colors
    val context = LocalContext.current
    val resources = LocalResources.current
    val hoy = finance.today()
    var offset by remember { mutableIntStateOf(0) }
    val mes = YearMonth.from(hoy).plusMonths(offset.toLong())
    val bills = MonthlyBills(finance.planning.series, mes, finance.accounts)
    val action = rememberAction()
    StmScreen(
        topBar = { TopBar(stringResource(R.string.pagos_del_mes_pagos_del_mes), onNav = nav::back) },
        snackbar = action.error?.let { e -> { Snackbar(e) } },
    ) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Segmented(listOf(stringResource(R.string.pagos_del_mes_este_mes), stringResource(R.string.pagos_del_mes_el_mes_que_viene)), offset, { offset = it })
            StmCard {
                Text(stringResource(R.string.pagos_del_mes_pagos_de, Fechas.mes(mes.atDay(1))), style = StmType.labelMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(Money.format(bills.total), style = StmType.titleLarge, color = c.onSurface)
                if (offset == 0) {
                    Spacer(Modifier.height(4.dp))
                    Text(stringResource(R.string.pagos_del_mes_quedan_por_pagar, Money.format(bills.pending(hoy))), style = StmType.bodySmall, color = c.onSurfaceVariant)
                }
            }
            if (bills.lines.isEmpty()) {
                Text(stringResource(R.string.pagos_del_mes_no_hay_pagos_fijos_este_mes), style = StmType.bodyMedium, color = c.onSurfaceVariant)
            } else {
                ListCard {
                    bills.lines.forEachIndexed { i, l ->
                        if (i > 0) Divider()
                        ListItem(
                            l.name, listOfNotNull(stringResource(R.string.comun_dia_de_mes, l.due.dayOfMonth, Fechas.mes(l.due)), l.accountName).joinToString(" · "),
                            trailingText = Money.format(l.amount),
                        )
                    }
                }
            }
            Btn(
                stringResource(R.string.pagos_del_mes_crear_pdf),
                {
                    action.run {
                        val fichero = ficheroExportar(context, bills.fileName)
                        withContext(Dispatchers.IO) { escribirPdfPagos(bills, finance.household.name, hoy, fichero, resources) }
                        compartir(context, fichero, "application/pdf")
                    }
                },
                Modifier.fillMaxWidth(), large = true, enabled = bills.lines.isNotEmpty() && !action.busy,
            )
            Text(
                stringResource(R.string.pagos_del_mes_salen_los_cargos_de_suscripciones),
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
        }
    }
}
