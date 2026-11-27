package com.savethemoney.android.ui

import androidx.annotation.StringRes
import com.savethemoney.android.R
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppTheme
import com.savethemoney.android.data.AssetClass
import com.savethemoney.android.data.CardPaymentMode
import com.savethemoney.android.data.ChartRange
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.DateOrder
import com.savethemoney.android.data.GroupedSpending
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.ImportMark
import com.savethemoney.android.data.InvestmentKind
import com.savethemoney.android.data.MovementDateFilter
import com.savethemoney.android.data.MovementKindFilter
import com.savethemoney.android.data.MovementStatusFilter
import com.savethemoney.android.data.PayFrequency
import com.savethemoney.android.data.ReportKind
import com.savethemoney.android.data.ReportPeriod
import com.savethemoney.android.data.TradeSide

// ORC-110: el dominio da el valor tipado y la app pone aquí, en un solo sitio, el texto que ve la persona (como
// KindTitles.swift en iOS). Se lee con stringResource(x.titulo) o, fuera de una función @Composable, resources.getString(x.titulo).

@get:StringRes
val AppTheme.titulo: Int get() = when (this) {
    AppTheme.System -> R.string.tema_automatico
    AppTheme.Light -> R.string.tema_claro
    AppTheme.Dark -> R.string.tema_oscuro
}

@get:StringRes
val AccountKind.titulo: Int get() = when (this) {
    AccountKind.Checking -> R.string.tipo_cuenta_cuenta_corriente
    AccountKind.Savings -> R.string.tipo_cuenta_ahorro
    AccountKind.CreditCard -> R.string.tipo_cuenta_tarjeta_de_credito
    AccountKind.Cash -> R.string.tipo_cuenta_efectivo
    AccountKind.Investment -> R.string.tipo_cuenta_inversion
    AccountKind.Loan -> R.string.tipo_cuenta_prestamo
    AccountKind.Other -> R.string.tipo_cuenta_otra
}

@get:StringRes
val CardPaymentMode.titulo: Int get() = when (this) {
    CardPaymentMode.Full -> R.string.forma_pago_todo
    CardPaymentMode.Fixed -> R.string.forma_pago_cuota_fija
    CardPaymentMode.Minimum -> R.string.forma_pago_minimo
}

@get:StringRes
val CardPaymentMode.detalle: Int get() = when (this) {
    CardPaymentMode.Full -> R.string.forma_pago_todo_detalle
    CardPaymentMode.Fixed -> R.string.forma_pago_cuota_fija_detalle
    CardPaymentMode.Minimum -> R.string.forma_pago_minimo_detalle
}

@get:StringRes
val PayFrequency.titulo: Int get() = when (this) {
    PayFrequency.Weekly -> R.string.cobro_cada_semana
    PayFrequency.Biweekly -> R.string.cobro_cada_dos_semanas
    PayFrequency.TwiceMonthly -> R.string.cobro_dos_dias_al_mes
    PayFrequency.Monthly -> R.string.cobro_cada_mes
    PayFrequency.Yearly -> R.string.cobro_cada_ano
}

@get:StringRes
val MovementKindFilter.titulo: Int get() = when (this) {
    MovementKindFilter.All -> R.string.filtro_tipo_todos
    MovementKindFilter.Expense -> R.string.filtro_tipo_gastos
    MovementKindFilter.Income -> R.string.filtro_tipo_ingresos
    MovementKindFilter.Transfer -> R.string.filtro_tipo_transferencias
}

@get:StringRes
val MovementStatusFilter.titulo: Int get() = when (this) {
    MovementStatusFilter.All -> R.string.filtro_estado_todos
    MovementStatusFilter.Unreviewed -> R.string.filtro_estado_sin_revisar
    MovementStatusFilter.Reviewed -> R.string.filtro_estado_revisados
    MovementStatusFilter.Excluded -> R.string.filtro_estado_excluidos
}

@get:StringRes
val MovementDateFilter.titulo: Int get() = when (this) {
    MovementDateFilter.All -> R.string.filtro_fechas_cualquier_fecha
    MovementDateFilter.ThisMonth -> R.string.filtro_fechas_este_mes
    MovementDateFilter.LastMonth -> R.string.filtro_fechas_el_mes_pasado
    MovementDateFilter.Last30Days -> R.string.filtro_fechas_ultimos_30_dias
    MovementDateFilter.Last90Days -> R.string.filtro_fechas_ultimos_90_dias
    MovementDateFilter.ThisYear -> R.string.filtro_fechas_este_ano
    MovementDateFilter.Custom -> R.string.filtro_fechas_fechas_a_medida
}

@get:StringRes
val ReportKind.titulo: Int get() = when (this) {
    ReportKind.Expense -> R.string.informe_tipo_gastos
    ReportKind.Income -> R.string.informe_tipo_ingresos
}

@get:StringRes
val ReportPeriod.titulo: Int get() = when (this) {
    ReportPeriod.ThisMonth -> R.string.informe_periodo_este_mes
    ReportPeriod.LastMonth -> R.string.informe_periodo_el_mes_pasado
    ReportPeriod.Last3Months -> R.string.informe_periodo_ultimos_3_meses
    ReportPeriod.Last6Months -> R.string.informe_periodo_ultimos_6_meses
    ReportPeriod.ThisYear -> R.string.informe_periodo_este_ano
    ReportPeriod.Last12Months -> R.string.informe_periodo_ultimos_12_meses
}

/** "el mes pasado", "los 3 meses anteriores"… para la frase de la comparación. */
@get:StringRes
val ReportPeriod.tituloAnterior: Int get() = when (this) {
    ReportPeriod.ThisMonth -> R.string.informe_periodo_anterior_el_mes_pasado_a_estas_alturas
    ReportPeriod.LastMonth -> R.string.informe_periodo_anterior_el_mes_anterior
    ReportPeriod.Last3Months -> R.string.informe_periodo_anterior_los_3_meses_anteriores
    ReportPeriod.Last6Months -> R.string.informe_periodo_anterior_los_6_meses_anteriores
    ReportPeriod.ThisYear -> R.string.informe_periodo_anterior_el_ano_pasado_a_estas_alturas
    ReportPeriod.Last12Months -> R.string.informe_periodo_anterior_los_12_meses_anteriores
}

@get:StringRes
val GroupedSpending.Grouping.titulo: Int get() = when (this) {
    GroupedSpending.Grouping.Tag -> R.string.agrupar_por_etiqueta
    GroupedSpending.Grouping.Payee -> R.string.agrupar_por_beneficiario
}

@get:StringRes
val CreditScore.Rating.titulo: Int get() = when (this) {
    CreditScore.Rating.Excellent -> R.string.score_tramo_excelente
    CreditScore.Rating.Good -> R.string.score_tramo_bueno
    CreditScore.Rating.Fair -> R.string.score_tramo_regular
    CreditScore.Rating.Poor -> R.string.score_tramo_mejorable
}

@get:StringRes
val HabitSettings.LogReminder.titulo: Int get() = when (this) {
    HabitSettings.LogReminder.Off -> R.string.recordatorio_apuntar_no
    HabitSettings.LogReminder.Daily -> R.string.recordatorio_apuntar_cada_dia
    HabitSettings.LogReminder.Weekly -> R.string.recordatorio_apuntar_los_domingos
}

@get:StringRes
val InvestmentKind.titulo: Int get() = when (this) {
    InvestmentKind.Fund -> R.string.tipo_activo_fondo
    InvestmentKind.Etf -> R.string.tipo_activo_etf
    InvestmentKind.Stock -> R.string.tipo_activo_accion
    InvestmentKind.Bond -> R.string.tipo_activo_bono
    InvestmentKind.Crypto -> R.string.tipo_activo_cripto
    InvestmentKind.Pension -> R.string.tipo_activo_plan_de_pensiones
    InvestmentKind.Cash -> R.string.tipo_activo_liquidez
    InvestmentKind.Other -> R.string.tipo_activo_otro
}

@get:StringRes
val AssetClass.titulo: Int get() = when (this) {
    AssetClass.Equity -> R.string.clase_activo_renta_variable
    AssetClass.FixedIncome -> R.string.clase_activo_renta_fija
    AssetClass.Crypto -> R.string.clase_activo_cripto
    AssetClass.Cash -> R.string.clase_activo_liquidez
    AssetClass.Other -> R.string.clase_activo_otros
}

@get:StringRes
val TradeSide.titulo: Int get() = when (this) {
    TradeSide.Buy -> R.string.operacion_compra
    TradeSide.Sell -> R.string.operacion_venta
}

@get:StringRes
val ChartRange.titulo: Int get() = when (this) {
    ChartRange.Day -> R.string.rango_grafico_1d
    ChartRange.Week -> R.string.rango_grafico_1s
    ChartRange.Month -> R.string.rango_grafico_1m
    ChartRange.HalfYear -> R.string.rango_grafico_6m
    ChartRange.Year -> R.string.rango_grafico_1a
    ChartRange.FiveYears -> R.string.rango_grafico_5a
    ChartRange.All -> R.string.rango_grafico_todo
}

@get:StringRes
val DateOrder.titulo: Int get() = when (this) {
    DateOrder.DayMonthYear -> R.string.formato_fecha_dia_mes_ano
    DateOrder.YearMonthDay -> R.string.formato_fecha_ano_mes_dia
    DateOrder.MonthDayYear -> R.string.formato_fecha_mes_dia_ano
}

@get:StringRes
val ImportMark.titulo: Int get() = when (this) {
    ImportMark.None -> R.string.marca_importar_sin_marcar
    ImportMark.Recurring -> R.string.marca_importar_recurrente
    ImportMark.Subscription -> R.string.marca_importar_suscripcion
    ImportMark.Card -> R.string.marca_importar_compra_con_tarjeta
}
