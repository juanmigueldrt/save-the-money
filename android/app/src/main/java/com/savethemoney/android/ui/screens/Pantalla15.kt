package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetGroup
import com.savethemoney.android.data.BudgetTemplate
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.FlexBudget
import com.savethemoney.android.data.Money
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.FilledField
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.Segmented
import com.savethemoney.android.ui.components.Snackbar
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.StmSwitch
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.iconoCategoria
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.rememberAction
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

/** 15 Editar presupuesto: modo, ingresos previstos, plantilla 50/30/20 e importes por categoría. */
@Composable
fun Pantalla15(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val finance = session.finance ?: return
    val budgets = finance.budgets
    val action = rememberAction()
    val inicial = budgets.draft
    var mode by rememberSaveable { mutableIntStateOf(0) }
    var income by rememberSaveable(inicial) { mutableStateOf(if (inicial.expectedIncome == 0L) "" else Money.input(inicial.expectedIncome)) }
    var template by remember(inicial) { mutableStateOf(inicial.template) }
    val limites = remember(inicial) { mutableStateMapOf<String, String>().apply { inicial.limits.forEach { (k, v) -> put(k, Money.input(v)) } } }
    var arrastre by rememberSaveable(inicial) { mutableStateOf(inicial.carryOver) }
    var aviso by rememberSaveable(inicial) { mutableIntStateOf(inicial.warnPercent) }
    var propuesta by remember { mutableStateOf<String?>(null) }
    val base = Money.entered(income)?.coerceAtLeast(0) ?: 0
    val reparto = template.allocate(base)
    val gastos = finance.categories(CategoryKind.Expense)
    val guardar = {
        action.run {
            val expected = if (income.isBlank()) 0L else Money.entered(income)?.takeIf { it >= 0 }
                ?: throw AppError.InvalidInput("Los ingresos previstos no son un importe válido.")
            val parsed = limites.filterValues { it.isNotBlank() }.mapValues { (id, text) ->
                Money.entered(text)?.takeIf { it >= 0 }
                    ?: throw AppError.InvalidInput("El límite de ${finance.category(id)?.name ?: "una categoría"} no es un importe válido.")
            }.filterValues { it > 0 }
            budgets.save(inicial.copy(expectedIncome = expected, template = template, limits = parsed, carryOver = arrastre, warnPercent = aviso))
            nav.back()
        }
    }
    LaunchedEffect(Unit) { if (budgets.budget == null && budgets.proposal == null) budgets.load() }
    StmScreen(
        topBar = {
            TopBar("Presupuesto · ${inicial.period.title}", navIcon = StmIcons.close, onNav = nav::back) {
                Btn("Guardar", guardar, kind = BtnKind.Text, enabled = !action.busy)
            }
        },
        snackbar = (action.error ?: propuesta)?.let { e -> { Snackbar(e) } },
    ) {
        Spacer(Modifier.height(8.dp))
        Segmented(listOf("Por categorías", "Flexible"), mode, { mode = it })
        Spacer(Modifier.height(16.dp))
        FilledField("Ingresos previstos", income, { income = it }, suffix = "€", keyboard = KeyboardType.Decimal, calculator = true)
        Spacer(Modifier.height(16.dp))
        StmCard(color = c.surfaceContainerHighest) {
            Row(Modifier.fillMaxWidth().height(32.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Reparto ${template.needs}/${template.wants}/${template.savings}", Modifier.weight(1f), style = StmType.titleMedium, color = c.onSurface)
                SmallTonalBtn("Aplicar") { template = BudgetTemplate.FiftyThirtyTwenty }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                BudgetGroup.entries.joinToString(" · ") { "${Money.format(reparto[it] ?: 0, decimals = false)} ${it.title.lowercase()}" },
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        ListCard {
            ListHeader("Arrastre y avisos")
            ListItem("Pasar lo que sobre al siguiente periodo", trailing = { StmSwitch(arrastre) { arrastre = it } })
            Divider(inset = 16.dp)
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Avisarme al", Modifier.weight(1f), style = StmType.bodyLarge, color = c.onSurface)
                Stepper("$aviso % del límite", { aviso = (aviso - 5).coerceAtLeast(50) }, { aviso = (aviso + 5).coerceAtMost(100) })
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "Con el arrastre, lo que sobre en una categoría se suma a su límite del siguiente periodo, y lo que te pases se resta.",
            style = StmType.bodySmall, color = c.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        if (mode == 0) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallTonalBtn("Proponer límites (media de 3 periodos)") {
                    val sugeridos = budgets.suggestedLimits(finance.categories)
                    if (sugeridos.isEmpty()) {
                        propuesta = "Aún no hay gastos en los periodos anteriores para proponer límites."
                    } else {
                        propuesta = null
                        limites.clear()
                        sugeridos.forEach { (k, v) -> limites[k] = Money.input(v) }
                    }
                }
                if (limites.values.any { it.isNotBlank() }) SmallTonalBtn("Vaciar límites") { limites.clear() }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "La propuesta usa lo que gastaste de media en cada categoría en los 3 periodos anteriores. Puedes cambiarla antes de guardar.",
                style = StmType.bodySmall, color = c.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            ListCard {
                BudgetGroup.entries.forEach { group ->
                    val filas = gastos.filter { it.budgetGroup == group }
                    if (filas.isNotEmpty()) {
                        ListHeader(group.title)
                        filas.forEachIndexed { i, category ->
                            if (i > 0) Divider()
                            ListItem(
                                category.name,
                                leading = { LeadIconGrupo(iconoCategoria(category), group) },
                                trailing = { CampoLimite(category.name, limites[category.id].orEmpty()) { limites[category.id] = it } },
                            )
                        }
                    }
                }
            }
        } else {
            val flex = FlexBudget(budgets.report(finance.categories), finance.planning.series, finance.today())
            ListCard {
                ListHeader("Flexible")
                ListItem("Entra", trailingText = Money.format(flex.income))
                Divider()
                ListItem("Pagos fijos", trailingText = Money.format(-flex.fixed))
                Divider()
                ListItem("Ahorro", trailingText = Money.format(-flex.savings))
                Divider()
                ListItem("Para todo lo demás", trailingText = Money.format(flex.flexible))
                Divider()
                ListItem("Gastado", trailingText = Money.format(flex.flexibleSpent))
                Divider()
                ListItem(
                    if (flex.remaining < 0) "Gastado de más" else "Queda",
                    flex.perDay?.let { "${Money.format(it)} al día" },
                    trailingText = Money.format(flex.remaining),
                )
            }
        }
    }
}

@Composable
private fun LeadIconGrupo(icon: ImageVector, group: BudgetGroup) {
    val c = Stm.colors
    when (group) {
        BudgetGroup.Wants -> LeadIcon(icon, c.tertiaryContainer, c.onTertiaryContainer)
        else -> LeadIcon(icon)
    }
}

/** Importe editable de una fila: gris y alineado a la derecha, como el importe del diseño. */
@Composable
private fun CampoLimite(categoria: String, value: String, onChange: (String) -> Unit) {
    val c = Stm.colors
    val style = StmType.bodyMediumTight.copy(color = c.onSurfaceVariant, textAlign = TextAlign.End)
    Row(verticalAlignment = Alignment.CenterVertically) {
        BasicTextField(
            value, onChange, Modifier.width(88.dp).semantics { contentDescription = "Límite de $categoria" },
            textStyle = style, singleLine = true, cursorBrush = SolidColor(c.primary),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterEnd) {
                    if (value.isEmpty()) Text("Sin límite", style = style)
                    inner()
                }
            },
        )
        if (value.isNotEmpty()) Text(" €", style = style)
    }
}

/** «Botón» tonal pequeño de 32 dp. */
@Composable
private fun SmallTonalBtn(label: String, onClick: () -> Unit) {
    val c = Stm.colors
    Box(
        Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(c.secondaryContainer).tap(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = StmType.labelLarge, color = c.onSecondaryContainer)
    }
}
