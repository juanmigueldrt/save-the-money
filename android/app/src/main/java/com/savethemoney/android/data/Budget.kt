package com.savethemoney.android.data

import java.text.Collator
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

// Budget.swift, BudgetTemplate.swift y CashFlow.swift de STMCore.

/** Días que cuenta como "este mes" un hogar cuyo mes empieza el día [startDay] (p. ej. el de cobro). */
fun YearMonth.period(startDay: Int = 1): ClosedRange<LocalDate> {
    val day = startDay.coerceIn(1, 28)
    if (day == 1) return atDay(1)..atEndOfMonth()
    return minusMonths(1).atDay(day)..atDay(day - 1)
}

/** Mes al que pertenece un día con ese día de inicio. */
fun monthContaining(day: LocalDate, startDay: Int = 1): YearMonth {
    val start = startDay.coerceIn(1, 28)
    val key = YearMonth.from(day)
    return if (start > 1 && day.dayOfMonth >= start) key.plusMonths(1) else key
}

data class BudgetTemplate(val needs: Int, val wants: Int, val savings: Int) {
    init {
        require(needs + wants + savings == 100) { "La plantilla debe sumar 100" }
    }

    fun percentage(group: BudgetGroup) = when (group) {
        BudgetGroup.Needs -> needs
        BudgetGroup.Wants -> wants
        BudgetGroup.Savings -> savings
    }

    /** Cuánto toca a cada grupo de unos ingresos dados, en céntimos. */
    fun allocate(income: Long): Map<BudgetGroup, Long> {
        val parts = Money.split(income, listOf(needs, wants, savings))
        return mapOf(BudgetGroup.Needs to parts[0], BudgetGroup.Wants to parts[1], BudgetGroup.Savings to parts[2])
    }

    companion object {
        val FiftyThirtyTwenty = BudgetTemplate(50, 30, 20)
    }
}

/** Presupuesto de un hogar para un mes; [limits] va por id de categoría de gasto, en positivo. */
data class Budget(
    val householdId: String,
    val month: YearMonth,
    val expectedIncome: Long = 0,
    val template: BudgetTemplate = BudgetTemplate.FiftyThirtyTwenty,
    val limits: Map<String, Long> = emptyMap(),
) {
    val issue: String? get() = when {
        expectedIncome < 0 -> "Los ingresos previstos no pueden ser negativos."
        limits.values.any { it < 0 } -> "Los límites no pueden ser negativos."
        else -> null
    }
}

data class GroupProgress(val group: BudgetGroup, val allocated: Long, val spent: Long)

data class CategoryLine(val category: BudgetCategory, val limit: Long?, val spent: Long) {
    val isOver: Boolean get() = limit != null && spent > limit

    /** Fracción gastada del límite, entre 0 y 1; nula si no tiene límite. */
    val fraction: Float? get() = limit?.takeIf { it > 0 }?.let { (spent.toDouble() / it).coerceIn(0.0, 1.0).toFloat() }
}

/** Lo gastado frente a lo previsto en [period]. Se calcula siempre a partir de los movimientos. */
class BudgetReport(
    budget: Budget?,
    val period: ClosedRange<LocalDate>,
    categories: List<BudgetCategory>,
    movements: List<Movement>,
) {
    /** Ingresos reales del periodo, sin transferencias entre cuentas. */
    val income: Long

    /** Lo que se reparte: los ingresos previstos si los hay; si no, los reales. */
    val base: Long
    val groups: List<GroupProgress>

    /** Categorías de gasto con límite o con gasto, por grupo y nombre. */
    val lines: List<CategoryLine>

    /** Gastos sin categoría o de categorías sin grupo. */
    val uncategorized: Long

    /** De dónde vienen los ingresos: categoría (o "Sin categoría") e importe, de mayor a menor. */
    val incomeSources: List<Pair<String, Long>>

    val totalSpent: Long get() = groups.sumOf { it.spent } + uncategorized

    init {
        val byId = categories.associateBy { it.id }
        var incomeTotal = 0L
        val incomeByTitle = mutableMapOf<String, Long>()
        val spentByCategory = mutableMapOf<String, Long>()
        var loose = 0L
        for (m in movements) {
            if (m.day !in period) continue
            val category = m.categoryId?.let(byId::get)
            when (category?.kind) {
                CategoryKind.Transfer -> Unit
                CategoryKind.Income -> {
                    incomeTotal += m.amountMinor
                    incomeByTitle.merge(category.name, m.amountMinor, Long::plus)
                }
                CategoryKind.Expense -> spentByCategory.merge(category.id, -m.amountMinor, Long::plus)
                null -> if (m.amountMinor > 0) {
                    incomeTotal += m.amountMinor
                    incomeByTitle.merge("Sin categoría", m.amountMinor, Long::plus)
                } else {
                    loose -= m.amountMinor
                }
            }
        }
        for (category in categories) {
            if (category.kind == CategoryKind.Expense && category.budgetGroup == null) loose += spentByCategory[category.id] ?: 0
        }
        income = incomeTotal
        uncategorized = loose
        incomeSources = incomeByTitle.filterValues { it > 0 }.toList().sortedWith(compareBy({ -it.second }, { it.first }))

        val expected = budget?.expectedIncome ?: 0
        base = if (expected > 0) expected else maxOf(incomeTotal, 0)
        val allocation = (budget?.template ?: BudgetTemplate.FiftyThirtyTwenty).allocate(base)
        groups = BudgetGroup.entries.map { group ->
            val spent = categories.filter { it.budgetGroup == group }.sumOf { spentByCategory[it.id] ?: 0 }
            GroupProgress(group, allocation[group] ?: 0, spent)
        }

        val collator = Collator.getInstance(Locale("es", "ES"))
        lines = categories.filter { it.kind == CategoryKind.Expense }
            .mapNotNull { category ->
                val limit = budget?.limits?.get(category.id)
                val spent = spentByCategory[category.id] ?: 0
                if (limit == null && spent == 0L) null else CategoryLine(category, limit, spent)
            }
            .sortedWith(compareBy<CategoryLine> { (it.category.budgetGroup ?: BudgetGroup.Wants).ordinal }.thenBy(collator) { it.category.name })
    }

    fun lines(group: BudgetGroup): List<CategoryLine> = lines.filter { it.category.budgetGroup == group }
}

/** Sankey: ingresos → Necesidades / Deseos / Ahorro (y lo que queda sin gastar) → categorías. */
class CashFlow(report: BudgetReport) {
    sealed interface Role {
        data object Income : Role
        data object FromBalance : Role
        data object Uncategorized : Role
        data object Unspent : Role
        data class Group(val group: BudgetGroup) : Role
    }

    /** [value] en céntimos, siempre positivo. Las categorías llevan el [Role.Group] de su grupo. */
    data class Node(val id: String, val title: String, val column: Int, val value: Double, val role: Role)
    data class Link(val from: String, val to: String, val value: Double)

    val nodes: List<Node>
    val links: List<Link>
    val isEmpty: Boolean get() = nodes.isEmpty()

    init {
        val leaves = mutableListOf<Node>()
        val edges = mutableListOf<Link>()
        val middle = mutableListOf<Node>()
        for (progress in report.groups) {
            if (progress.spent <= 0) continue
            val groupId = "grupo:${progress.group.name}"
            middle += Node(groupId, progress.group.title, 1, progress.spent.toDouble(), Role.Group(progress.group))
            for (line in report.lines(progress.group)) {
                if (line.spent <= 0) continue
                val id = "categoria:${line.category.id}"
                leaves += Node(id, line.category.name, 2, line.spent.toDouble(), Role.Group(progress.group))
                edges += Link(groupId, id, line.spent.toDouble())
            }
        }
        if (report.uncategorized > 0) {
            middle += Node("sin-categoria", "Sin categoría", 1, report.uncategorized.toDouble(), Role.Uncategorized)
        }
        val spent = middle.sumOf { it.value }
        val income = report.incomeSources.sumOf { it.second.toDouble() }
        if (income > spent) middle += Node("sin-gastar", "Sin gastar", 1, income - spent, Role.Unspent)

        val sources = report.incomeSources.mapIndexed { i, (title, amount) ->
            Node("ingreso:$i", title, 0, amount.toDouble(), Role.Income)
        }.toMutableList()
        if (spent > income) sources += Node("del-saldo", "Del saldo", 0, spent - income, Role.FromBalance)

        // Cada fuente reparte su importe entre los grupos en proporción a lo que se llevan.
        val total = sources.sumOf { it.value }
        if (total > 0) {
            for (source in sources) for (target in middle) edges += Link(source.id, target.id, source.value * target.value / total)
        }
        nodes = sources + middle + leaves
        links = edges
    }
}

/** Posiciones del diagrama para un tamaño dado, sin Compose para poder probarlo. */
class SankeyLayout(flow: CashFlow, width: Double, height: Double, nodeWidth: Double = 10.0, gap: Double = 12.0) {
    data class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
        val midY: Double get() = y + height / 2
    }

    data class Band(val from: String, val to: String, val sourceX: Double, val sourceTop: Double, val targetX: Double, val targetTop: Double, val thickness: Double)

    val nodes: Map<String, Rect>
    val bands: List<Band>

    init {
        val columns = flow.nodes.groupBy { it.column }
        val columnCount = (columns.keys.maxOrNull() ?: 0) + 1
        // Misma escala en todas las columnas para que los grosores sean comparables.
        val scale = columns.values.minOfOrNull { column ->
            val total = column.sumOf { it.value }
            val free = height - gap * maxOf(column.size - 1, 0)
            if (total > 0) maxOf(free, 1.0) / total else Double.POSITIVE_INFINITY
        } ?: 0.0
        val step = if (columnCount > 1) (width - nodeWidth) / (columnCount - 1) else 0.0

        val rects = mutableMapOf<String, Rect>()
        for ((index, column) in columns) {
            val used = column.sumOf { it.value * scale } + gap * maxOf(column.size - 1, 0)
            var y = maxOf(0.0, (height - used) / 2)
            for (node in column) {
                val h = node.value * scale
                rects[node.id] = Rect(index * step, y, nodeWidth, h)
                y += h + gap
            }
        }

        val outOffset = mutableMapOf<String, Double>()
        val inOffset = mutableMapOf<String, Double>()
        val result = mutableListOf<Band>()
        for (link in flow.links) {
            if (link.value <= 0) continue
            val source = rects[link.from] ?: continue
            val target = rects[link.to] ?: continue
            val thickness = link.value * scale
            val sourceTop = source.y + (outOffset[link.from] ?: 0.0)
            val targetTop = target.y + (inOffset[link.to] ?: 0.0)
            outOffset[link.from] = (outOffset[link.from] ?: 0.0) + thickness
            inOffset[link.to] = (inOffset[link.to] ?: 0.0) + thickness
            result += Band(link.from, link.to, source.x + source.width, sourceTop, target.x, targetTop, thickness)
        }
        nodes = rects
        bands = result
    }
}
