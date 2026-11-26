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
import androidx.compose.ui.semantics.contentDescription
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

internal fun fechaLarga(d: LocalDate) = "${d.dayOfMonth} de ${Fechas.mes(d)}"

/** "14" o "21,5", para los campos y los textos. */
internal fun tasa(valor: Double) = BigDecimal(valor).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString().replace('.', ',')

internal fun leerTasa(texto: String) = parseDecimal(texto, maxFractionDigits = 2)?.toDouble()

/** Los intereses ya van dentro de las cuotas: se dicen aparte para que no se sumen dos veces. */
internal fun desglose(p: CardPayment, modo: CardPaymentMode): String {
    val partes = buildList {
        if (p.purchases > 0) add((if (modo.isRevolving) "cuota " else "compras ") + Money.format(p.purchases))
        if (p.installments > 0) add("aplazados ${Money.format(p.installments)}")
    }
    if (partes.isEmpty()) return "Sin cargos"
    val texto = partes.joinToString(" · ")
    return if (p.interest > 0) "$texto (incluye ${Money.format(p.interest)} de intereses)" else texto
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
        IconBtn(StmIcons.edit, { nav.go(Route.CondicionesTarjeta(cuenta?.id)) }, contentDescription = "Editar condiciones")
        Box {
            IconBtn(StmIcons.moreVert, if (cuenta == null) null else ({ menu = true }), contentDescription = "Más opciones")
            // Bloqueada, el menú (otra ventana) no se pinta; vuelve al desbloquear.
            DropdownMenu(menu && !Bloqueo.app.bloqueada, { menu = false }, containerColor = c.surfaceContainer) {
                DropdownMenuItem({ Text("Editar condiciones", color = c.onSurface) }, {
                    menu = false
                    nav.go(Route.CondicionesTarjeta(cuenta?.id))
                }, leadingIcon = { StmIcon(StmIcons.edit, c.onSurfaceVariant) })
                DropdownMenuItem({ Text("Archivar tarjeta", color = c.onSurface) }, {
                    menu = false
                    val a = cuenta ?: return@DropdownMenuItem
                    action.run {
                        finance.updateAccount(a.copy(archivedAt = java.time.Instant.now().toString()))
                        nav.back()
                    }
                }, leadingIcon = { StmIcon(StmIcons.visibilityOff, c.onSurfaceVariant) })
                DropdownMenuItem({ Text("Borrar tarjeta y movimientos", color = c.error) }, {
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
            title = { Text("¿Borrar esta tarjeta?", style = StmType.headlineSmall, color = c.onSurface) },
            text = { Text("Se borran también todos sus movimientos, para todo el hogar. No se puede deshacer.", style = StmType.bodyMedium, color = c.onSurfaceVariant) },
            containerColor = c.surfaceContainerHigh,
            dismissButton = { Btn("Cancelar", { borrar = false }, kind = BtnKind.Text) },
            confirmButton = {
                Btn("Borrar", {
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
