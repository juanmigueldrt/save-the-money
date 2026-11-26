package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.BottomSheet
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Pill
import com.savethemoney.android.ui.components.SemicircleGauge
import com.savethemoney.android.ui.components.Slice
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 19 Score crediticio: indicador con la última puntuación e historial de las apuntadas a mano. */
@Composable
fun Pantalla19(nav: Nav) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    val tracking = finance.tracking
    val c = Stm.colors
    var borrando by remember { mutableStateOf<CreditScore?>(null) }
    val action = rememberAction()
    LaunchedEffect(Unit) { tracking.loadScores() }
    val ultimo = tracking.latestScore
    StmScreen(
        topBar = {
            TopBar("Score crediticio", onNav = nav::back) {
                IconBtn(StmIcons.add, { nav.go(Route.ApuntarScore) }, contentDescription = "Añadir puntuación")
            }
        },
        snackbar = (action.error ?: tracking.error)?.let { e -> { Snackbar(e) } },
        overlay = borrando?.let { item ->
            {
                BottomSheet("¿Borrar este score?", "${item.score} de ${item.maxScore}", onDismiss = { borrando = null }) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn("Cancelar", { borrando = null }, kind = BtnKind.Text)
                        Btn("Borrar", {
                            action.run {
                                tracking.delete(item)
                                borrando = null
                            }
                        }, kind = BtnKind.Error)
                    }
                }
            }
        },
    ) {
        if (ultimo == null) {
            StmCard {
                Text("Apunta el score que te da tu banco o tu proveedor para ver cómo evoluciona.", style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn("Apuntar mi score", { nav.go(Route.ApuntarScore) })
            }
            return@StmScreen
        }
        StmCard {
            val valor = "${ultimo.score}"
            val titulo = ultimo.rating.title
            val tono = when (ultimo.rating) {
                CreditScore.Rating.Excellent, CreditScore.Rating.Good -> c.success
                CreditScore.Rating.Fair -> c.onSurfaceVariant
                CreditScore.Rating.Poor -> c.error
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                // El tramo del diseño barre 129,6° de 180°.
                SemicircleGauge(listOf(Slice(ultimo.fraction.toFloat(), tono)), width = 280.dp, thickness = 20.dp, gapDegrees = 0f)
                Column(Modifier.padding(top = 92.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(valor, style = StmType.displaySmall, color = c.onSurface)
                    Text(titulo, style = StmType.labelMedium, color = tono)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Lo apuntas tú a mano: en España no hay una fuente abierta para consultarlo.", Modifier.fillMaxWidth(),
                style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Historial")
            tracking.scores.forEachIndexed { i, item ->
                if (i > 0) Divider()
                val delta = tracking.scores.getOrNull(i + 1)?.takeIf { it.maxScore == item.maxScore }?.let { item.score - it.score }
                ListItem(
                    "${item.score} de ${item.maxScore} · ${item.rating.title}",
                    listOfNotNull("${Fechas.mesTitulo(item.day)} ${item.day.year}", item.trimmedProvider, item.note).joinToString(" · "),
                    leading = {
                        if (i == 0) LeadIcon(StmIcons.creditScore, c.successContainer, c.onSuccessContainer)
                        else LeadIcon(StmIcons.creditScore, c.surfaceContainerHighest, c.onSurfaceVariant)
                    },
                    trailing = { if (delta != null && delta != 0) Pill(if (delta > 0) "+$delta" else "${Money.MINUS}${-delta}", positive = delta > 0, icon = null) },
                    onClick = { borrando = item },
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        Text("Sólo lo ves tú: no se comparte con el resto del hogar. Los tramos son orientativos. Toca uno para borrarlo.", style = StmType.bodySmall, color = c.onSurfaceVariant)
    }
}
