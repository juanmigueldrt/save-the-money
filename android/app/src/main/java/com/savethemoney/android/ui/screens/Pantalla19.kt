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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
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
import com.savethemoney.android.ui.titulo

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
            TopBar(stringResource(R.string.score_score_crediticio), onNav = nav::back) {
                IconBtn(StmIcons.add, { nav.go(Route.ApuntarScore) }, contentDescription = stringResource(R.string.score_anadir_puntuacion))
            }
        },
        snackbar = (action.error ?: tracking.error)?.let { e -> { Snackbar(e) } },
        overlay = borrando?.let { item ->
            {
                BottomSheet(stringResource(R.string.score_borrar_este_score), stringResource(R.string.score_de, item.score, item.maxScore), onDismiss = { borrando = null }) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Btn(stringResource(R.string.comun_cancelar), { borrando = null }, kind = BtnKind.Text)
                        Btn(stringResource(R.string.comun_borrar), {
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
                Text(stringResource(R.string.score_apunta_el_score_que_te_da), style = StmType.bodyMedium, color = c.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Btn(stringResource(R.string.score_apuntar_mi_score), { nav.go(Route.ApuntarScore) })
            }
            return@StmScreen
        }
        StmCard {
            val valor = "${ultimo.score}"
            val titulo = stringResource(ultimo.rating.titulo)
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
                stringResource(R.string.score_lo_apuntas_tu_a_mano_en), Modifier.fillMaxWidth(),
                style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader(stringResource(R.string.score_historial))
            tracking.scores.forEachIndexed { i, item ->
                if (i > 0) Divider()
                val delta = tracking.scores.getOrNull(i + 1)?.takeIf { it.maxScore == item.maxScore }?.let { item.score - it.score }
                ListItem(
                    stringResource(R.string.score_de_2, item.score, item.maxScore, stringResource(item.rating.titulo)),
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
        Text(stringResource(R.string.score_solo_lo_ves_tu_no_se), style = StmType.bodySmall, color = c.onSurfaceVariant)
    }
}
