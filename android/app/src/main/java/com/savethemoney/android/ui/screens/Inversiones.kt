package com.savethemoney.android.ui.screens

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.savethemoney.android.data.AssetClass
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

internal const val SIN_CUENTA = "No apuntar en ninguna cuenta"

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
