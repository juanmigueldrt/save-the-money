package com.savethemoney.android.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.TopBar

const val SCREEN_COUNT = 34

/** Pinta la pantalla de [route] con sus argumentos. */
@Composable
fun ScreenFor(route: Route, nav: Nav) {
    when (route) {
        Route.IniciarSesion -> Pantalla01(nav)
        Route.CrearCuenta -> Pantalla02(nav)
        Route.TuHogar -> Pantalla03(nav)
        Route.Inicio -> Pantalla04(nav)
        Route.Movimientos -> Pantalla05(nav)
        is Route.Cuenta -> Pantalla06(nav, route.accountId)
        is Route.FormMovimiento -> Pantalla07(nav, route)
        is Route.AccionesMovimiento -> Pantalla08(nav, route.movementId)
        is Route.FormCuenta -> Pantalla09(nav, route.accountId, route.kind)
        Route.Tarjetas -> Pantalla10(nav)
        is Route.Tarjeta -> Pantalla11(nav, route.cardId)
        is Route.CondicionesTarjeta -> Pantalla12(nav, route.cardId)
        is Route.AplazarCompra -> Pantalla13(nav, route.cardId, route.movementId)
        Route.Presupuesto -> Pantalla14(nav)
        Route.EditarPresupuesto -> Pantalla15(nav)
        Route.Flujo -> Pantalla16(nav)
        Route.Patrimonio -> Pantalla17(nav)
        Route.Informes -> Pantalla18(nav)
        Route.Score -> Pantalla19(nav)
        Route.PagosFijos -> Pantalla20(nav)
        is Route.FormPagoFijo -> Pantalla21(nav, route.seriesId)
        Route.Metas -> Pantalla22(nav)
        is Route.Meta -> Pantalla23(nav, route.goalId)
        is Route.FormMeta -> Pantalla24(nav, route.goalId)
        Route.Cartera -> Pantalla25(nav)
        is Route.Activo -> Pantalla26(nav, route.holdingId)
        Route.InversionesRecurrentes -> Pantalla27(nav)
        Route.Hogar -> Pantalla28(nav)
        Route.Invitar -> Pantalla29(nav)
        Route.Mas -> Pantalla30(nav)
        Route.Categorias -> Pantalla31(nav)
        is Route.ImportarCsv -> Pantalla32(nav, route.accountId)
        Route.BorrarDatos -> Pantalla33(nav)
        is Route.DetalleMovimiento -> Pantalla34(nav, route.movementId)
        // Fuera del diseño: el formulario de aportar a una meta.
        is Route.Aportar -> Pantalla35(nav, route.goalId)
        // Fuera del diseño: pagos del mes y lector de QR, como en iOS.
        Route.PagosDelMes -> Pantalla36(nav)
        Route.EscanerQr -> Pantalla37(nav)
        // Fuera del diseño: apuntar un score, como en iOS.
        Route.ApuntarScore -> Pantalla38(nav)
        // Fuera del diseño: formularios de inversiones, como en iOS.
        is Route.FormActivo -> Pantalla39(nav, route.holdingId)
        is Route.ApuntarPrecio -> Pantalla40(nav, route.holdingId)
        is Route.Vender -> Pantalla41(nav, route.holdingId)
        is Route.FormPlan -> Pantalla42(nav, route.planId)
        // Fuera del diseño: calendario de pagos.
        Route.Calendario -> Pantalla43(nav)
        // Fuera del diseño: día de cobro y presupuestos extra (fase C), como en iOS.
        Route.DiaDeCobro -> Pantalla44(nav)
        is Route.FormExtra -> Pantalla45(nav, route.extraId)
        // Fuera del diseño: confirmar un pago fijo pendiente y resumen semanal (fase D), como en iOS.
        is Route.ConfirmarCargo -> Pantalla46(nav, route.chargeId)
        Route.ResumenSemanal -> Pantalla47(nav)
    }
}

/**
 * La fila que abre un formulario, tal como estaba al encontrarla: guardar sobre ella detecta si otro la cambió mientras
 * tanto. Nula sin [id] (formulario nuevo) o mientras no esté cargada; si se borra, vuelve a ser nula.
 */
@Composable
internal fun <T : Any> rememberRow(id: String?, find: (String) -> T?): T? {
    val actual = id?.let(find)
    return remember(id, actual != null) { actual }
}

/** Lo que abría la pantalla ya no está (se borró) o aún no ha cargado: se dice y se deja volver, nunca se enseña otra fila. */
@Composable
internal fun NoEncontrado(nav: Nav) {
    StmScreen(topBar = { TopBar(null, onNav = nav::back) }) {
        Vacio("No se encuentra. Puede que se haya borrado o que aún se esté cargando.")
    }
}
