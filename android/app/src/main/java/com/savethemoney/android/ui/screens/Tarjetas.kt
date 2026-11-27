package com.savethemoney.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import com.savethemoney.android.R
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.CardPayment
import com.savethemoney.android.data.CardPaymentMode
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.parseDecimal
import com.savethemoney.android.ui.Bloqueo
import com.savethemoney.android.ui.Fechas
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate

internal fun fechaLarga(d: LocalDate, resources: android.content.res.Resources) = resources.getString(R.string.comun_dia_de_mes, d.dayOfMonth, Fechas.mes(d))

/** "14" o "21,5", para los campos y los textos. */
internal fun tasa(valor: Double) = BigDecimal(valor).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString().replace('.', ',')

internal fun leerTasa(texto: String) = parseDecimal(texto, maxFractionDigits = 2)?.toDouble()

/** Los intereses ya van dentro de las cuotas: se dicen aparte para que no se sumen dos veces. */
internal fun desglose(p: CardPayment, modo: CardPaymentMode, resources: android.content.res.Resources): String {
    val partes = buildList {
        if (p.purchases > 0) add(resources.getString(if (modo.isRevolving) R.string.tarjetas_desglose_cuota else R.string.tarjetas_desglose_compras, Money.format(p.purchases)))
        if (p.installments > 0) add(resources.getString(R.string.tarjetas_aplazados, Money.format(p.installments)))
    }
    if (partes.isEmpty()) return resources.getString(R.string.tarjetas_sin_cargos)
    val texto = partes.joinToString(" · ")
    return if (p.interest > 0) resources.getString(R.string.tarjetas_incluye_de_intereses, texto, Money.format(p.interest)) else texto
}

internal fun Double.barra() = toFloat().coerceIn(0f, 1f)

/** Barra con el nombre de la tarjeta que comparten el detalle (11) y el aplazamiento (13); el «más» abre Editar, Archivar y Borrar. */
@Composable
internal fun DetalleBar(nav: Nav, cuenta: Account?, nombre: String) {
    val session = LocalSession.current
    val finance = session.finance ?: return
    var menu by remember { mutableStateOf(false) }
    var borrar by remember { mutableStateOf(false) }
    val action = rememberAction()
    val c = Stm.colors
    TopBar(nombre, onNav = nav::back) {
        IconBtn(StmIcons.edit, { nav.go(Route.CondicionesTarjeta(cuenta?.id)) }, contentDescription = stringResource(R.string.tarjetas_editar_condiciones))
        Box {
            IconBtn(StmIcons.moreVert, if (cuenta == null) null else ({ menu = true }), contentDescription = stringResource(R.string.comun_mas_opciones))
            // Bloqueada, el menú (otra ventana) no se pinta; vuelve al desbloquear.
            DropdownMenu(menu && !Bloqueo.app.bloqueada, { menu = false }, containerColor = c.surfaceContainer) {
                DropdownMenuItem({ Text(stringResource(R.string.tarjetas_editar_condiciones), color = c.onSurface) }, {
                    menu = false
                    nav.go(Route.CondicionesTarjeta(cuenta?.id))
                }, leadingIcon = { StmIcon(StmIcons.edit, c.onSurfaceVariant) })
                DropdownMenuItem({ Text(stringResource(R.string.tarjetas_archivar_tarjeta), color = c.onSurface) }, {
                    menu = false
                    val a = cuenta ?: return@DropdownMenuItem
                    action.run {
                        finance.updateAccount(a.copy(archivedAt = java.time.Instant.now().toString()))
                        nav.back()
                    }
                }, leadingIcon = { StmIcon(StmIcons.visibilityOff, c.onSurfaceVariant) })
                DropdownMenuItem({ Text(stringResource(R.string.tarjetas_borrar_tarjeta_y_movimientos), color = c.error) }, {
                    menu = false
                    borrar = true
                }, leadingIcon = { StmIcon(StmIcons.delete, c.error) })
            }
        }
    }
    // Bloqueada, el diálogo (otra ventana) no se pinta; vuelve al desbloquear.
    if (borrar && cuenta != null && !Bloqueo.app.bloqueada) {
        AlertDialog(
            onDismissRequest = { borrar = false },
            icon = { StmIcon(StmIcons.deleteForever, c.error) },
            title = { Text(stringResource(R.string.tarjetas_borrar_esta_tarjeta), style = StmType.headlineSmall, color = c.onSurface) },
            text = { Text(stringResource(R.string.cuenta_se_borran_tambien_todos_sus), style = StmType.bodyMedium, color = c.onSurfaceVariant) },
            containerColor = c.surfaceContainerHigh,
            dismissButton = { Btn(stringResource(R.string.comun_cancelar), { borrar = false }, kind = BtnKind.Text) },
            confirmButton = {
                Btn(stringResource(R.string.comun_borrar), {
                    action.run {
                        finance.deleteAccount(cuenta)
                        borrar = false
                        nav.back()
                    }
                }, kind = BtnKind.Error, enabled = !action.busy)
            },
        )
    }
}
