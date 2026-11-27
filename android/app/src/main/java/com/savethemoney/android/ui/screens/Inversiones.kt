package com.savethemoney.android.ui.screens

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import com.savethemoney.android.R
import com.savethemoney.android.data.AssetClass
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.ui.InvestmentModel
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

@Composable
internal fun sinCuenta() = stringResource(R.string.inversiones_no_apuntar_en_ninguna_cuenta)

/** De quién es un activo: "Ana" o "Compartido". */
@Composable
internal fun nombreDueno(inv: InvestmentModel, id: String?): String =
    if (id == null) stringResource(R.string.inversiones_compartido) else inv.memberName(id) ?: stringResource(R.string.inversiones_otro_miembro)

@Composable
internal fun AssetClass.color(): Color {
    val c = Stm.colors
    return when (this) {
        AssetClass.Equity -> c.primary
        AssetClass.FixedIncome -> c.tertiary
        AssetClass.Crypto -> c.success
        AssetClass.Cash -> c.secondaryContainer
        AssetClass.Other -> c.outline
    }
}

internal fun iconoActivo(kind: InvestmentKind) = if (kind == InvestmentKind.Bond) StmIcons.accountBalance else StmIcons.public

@Composable
internal fun Aviso(text: String) = Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
