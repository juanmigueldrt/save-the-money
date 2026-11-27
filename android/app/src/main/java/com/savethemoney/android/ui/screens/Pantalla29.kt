package com.savethemoney.android.ui.screens

import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.savethemoney.android.R
import com.savethemoney.android.data.HouseholdInvite
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Brand
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 29 Invitar a tu pareja: QR, código de 6 caracteres y botones para copiar o compartir. */
@Composable
fun Pantalla29(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val context = LocalContext.current
    val resources = LocalResources.current
    val clipboard = LocalClipboardManager.current
    // Reutiliza la invitación pendiente si la hay; si no, pide una nueva al servidor.
    val invite by produceState<HouseholdInvite?>(null, session.household) {
        value = session.household?.let { h ->
            runCatching { session.backend.pendingInvites(h.id).firstOrNull() ?: session.backend.createInvite(h.id) }.getOrNull()
        }
    }
    val code = invite?.code?.let(InviteCode::parse)
    val horas by produceState<Long?>(null, invite) { value = invite?.let { horasHasta(it.expiresAt) } }
    StmScreen(topBar = { TopBar(stringResource(R.string.invitar_invitar), navIcon = StmIcons.close, onNav = nav::back) }) {
        Spacer(Modifier.height(12.dp))
        Text(
            stringResource(R.string.invitar_escanea_este_codigo_desde_su_movil), Modifier.fillMaxWidth(),
            style = StmType.headlineSmall, color = c.onSurface, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        // El QR va siempre en tinta sobre papel (igual en claro y oscuro) para que se pueda escanear.
        Box(
            Modifier.align(Alignment.CenterHorizontally).size(216.dp).clip(RoundedCornerShape(16.dp))
                .background(Brand.paper).padding(16.dp),
        ) {
            if (code != null) QrCode(code.link)
        }
        Spacer(Modifier.height(24.dp))
        Text(stringResource(R.string.invitar_o_escribe_el_codigo), Modifier.fillMaxWidth(), style = StmType.labelMedium, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (code?.value ?: "······").forEach { ch ->
                Box(
                    Modifier.size(44.dp, 56.dp).clip(RoundedCornerShape(8.dp)).background(c.surfaceContainerHighest),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(ch.toString(), style = StmType.headlineMediumWide, color = c.onSurface)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(horas?.let { pluralStringResource(R.plurals.invitar_caduca_en_horas, it.toInt(), it) } ?: "", Modifier.fillMaxWidth(), style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(24.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Btn(stringResource(R.string.invitar_copiar_codigo), code?.let { { clipboard.setText(AnnotatedString(it.value)) } }, kind = BtnKind.Tonal, icon = StmIcons.contentCopy)
            Btn(stringResource(R.string.invitar_compartir_enlace), code?.let {
                {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, resources.getString(R.string.invitar_unete_a_nuestro_hogar_en_save, it.link, it.value))
                    context.startActivity(Intent.createChooser(send, resources.getString(R.string.invitar_compartir_enlace)))
                }
            }, kind = BtnKind.Outlined, icon = StmIcons.share)
        }
    }
}

/**
 * QR real del enlace de invitación (zxing), en tinta sobre papel. Los tres buscadores se pintan
 * redondeados como en el diseño; su geometría no cambia, así que se sigue leyendo.
 */
@Composable
private fun QrCode(text: String) {
    val matrix = remember(text) {
        QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 0))
    }
    Canvas(Modifier.size(184.dp)) {
        val n = matrix.width
        val m = size.width / n
        for (y in 0 until n) for (x in 0 until n) {
            if (inFinder(x, y, n) || !matrix[x, y]) continue
            drawRect(Brand.ink, Offset(x * m, y * m), Size(m, m))
        }
        val far = (n - 7) * m
        listOf(Offset(0f, 0f), Offset(far, 0f), Offset(0f, far)).forEach { finder(it, m) }
    }
}

/** Buscador: anillo de 7 módulos y centro de 3, con esquinas redondeadas como en el diseño. */
private fun DrawScope.finder(at: Offset, m: Float) {
    drawRoundRect(Brand.ink, at, Size(7 * m, 7 * m), CornerRadius(2 * m))
    drawRoundRect(Brand.paper, at + Offset(m, m), Size(5 * m, 5 * m), CornerRadius(1.2f * m))
    drawRoundRect(Brand.ink, at + Offset(2 * m, 2 * m), Size(3 * m, 3 * m), CornerRadius(0.8f * m))
}

/** Zona de un buscador más su separador de un módulo. */
private fun inFinder(x: Int, y: Int, n: Int): Boolean {
    val far = n - 8
    return (x < 8 && y < 8) || (x >= far && y < 8) || (x < 8 && y >= far)
}
