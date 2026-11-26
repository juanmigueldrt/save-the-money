package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountKind

/**
 * Las pantallas de la app con lo que necesitan para abrirse. [screen] es el número del diseño (01–47).
 *
 * Los argumentos son ids y enums, nunca filas, importes ni nombres: la pantalla busca la fila al pintarse, así ve siempre
 * lo último. Si el id ya no está (se borró o aún no ha cargado, p. ej. tras cerrar Android la app), la pantalla lo dice y
 * deja volver; nunca enseña otra fila.
 */
sealed class Route(val screen: Int) {
    /** Los argumentos en orden, como texto, para guardar la pila (nulo = sin valor). */
    protected open val args: List<String?> get() = emptyList()

    data object IniciarSesion : Route(1)
    data object CrearCuenta : Route(2)
    data object TuHogar : Route(3)
    data object Inicio : Route(4)
    data object Movimientos : Route(5)
    data class Cuenta(val accountId: String) : Route(6) {
        override val args get() = listOf(accountId)
    }

    /**
     * Nuevo o editar movimiento. [movementId] edita ese; si no, [accountId] es la cuenta preelegida y, en una transferencia,
     * [toAccountId] la de destino. [cardPayment]: el pago de la tarjeta [toAccountId], con su próximo cargo ya escrito.
     */
    data class FormMovimiento(
        val movementId: String? = null,
        val accountId: String? = null,
        val transfer: Boolean = false,
        val toAccountId: String? = null,
        val cardPayment: Boolean = false,
    ) : Route(7) {
        override val args get() = listOf(movementId, accountId, "$transfer", toAccountId, "$cardPayment")
    }
    data class AccionesMovimiento(val movementId: String) : Route(8) {
        override val args get() = listOf(movementId)
    }

    /** Nueva cuenta (del tipo [kind], si viene) o editar [accountId]. */
    data class FormCuenta(val accountId: String? = null, val kind: AccountKind? = null) : Route(9) {
        override val args get() = listOf(accountId, kind?.name)
    }
    data object Tarjetas : Route(10)

    /** Sin [cardId], la primera tarjeta. */
    data class Tarjeta(val cardId: String?) : Route(11) {
        override val args get() = listOf(cardId)
    }
    data class CondicionesTarjeta(val cardId: String?) : Route(12) {
        override val args get() = listOf(cardId)
    }

    /** Sin [movementId], la persona elige la compra a aplazar. */
    data class AplazarCompra(val cardId: String?, val movementId: String? = null) : Route(13) {
        override val args get() = listOf(cardId, movementId)
    }
    data object Presupuesto : Route(14)
    data object EditarPresupuesto : Route(15)
    data object Flujo : Route(16)
    data object Patrimonio : Route(17)
    data object Informes : Route(18)
    data object Score : Route(19)
    data object PagosFijos : Route(20)
    data class FormPagoFijo(val seriesId: String? = null) : Route(21) {
        override val args get() = listOf(seriesId)
    }
    data object Metas : Route(22)
    data class Meta(val goalId: String) : Route(23) {
        override val args get() = listOf(goalId)
    }
    data class FormMeta(val goalId: String? = null) : Route(24) {
        override val args get() = listOf(goalId)
    }
    data object Cartera : Route(25)
    data class Activo(val holdingId: String) : Route(26) {
        override val args get() = listOf(holdingId)
    }
    data object InversionesRecurrentes : Route(27)
    data object Hogar : Route(28)
    data object Invitar : Route(29)
    data object Mas : Route(30)
    data object Categorias : Route(31)
    data class ImportarCsv(val accountId: String? = null) : Route(32) {
        override val args get() = listOf(accountId)
    }
    data object BorrarDatos : Route(33)
    data class DetalleMovimiento(val movementId: String) : Route(34) {
        override val args get() = listOf(movementId)
    }
    data class Aportar(val goalId: String) : Route(35) {
        override val args get() = listOf(goalId)
    }
    data object PagosDelMes : Route(36)
    data object EscanerQr : Route(37)
    data object ApuntarScore : Route(38)
    data class FormActivo(val holdingId: String? = null) : Route(39) {
        override val args get() = listOf(holdingId)
    }
    data class ApuntarPrecio(val holdingId: String) : Route(40) {
        override val args get() = listOf(holdingId)
    }
    data class Vender(val holdingId: String) : Route(41) {
        override val args get() = listOf(holdingId)
    }
    data class FormPlan(val planId: String? = null) : Route(42) {
        override val args get() = listOf(planId)
    }
    data object Calendario : Route(43)
    data object DiaDeCobro : Route(44)
    data class FormExtra(val extraId: String? = null) : Route(45) {
        override val args get() = listOf(extraId)
    }
    data class ConfirmarCargo(val chargeId: String) : Route(46) {
        override val args get() = listOf(chargeId)
    }
    data object ResumenSemanal : Route(47)

    /** La ruta como texto: el número y sus argumentos. Los ids no llevan [SEP]. */
    fun encode(): String = (listOf("$screen") + args.map { it ?: "" }).joinToString(SEP)

    companion object {
        private const val SEP = "|"

        /** La última pantalla del diseño. */
        const val LAST = 47

        /** Lee lo que dio [encode]. Nulo si no es una ruta conocida o le faltan o sobran argumentos: nunca lanza. */
        fun decode(text: String): Route? = runCatching {
            val parts = text.split(SEP)
            val a = parts.drop(1).map { it.ifEmpty { null } }
            val route = when (parts[0].toInt()) {
                1 -> IniciarSesion
                2 -> CrearCuenta
                3 -> TuHogar
                4 -> Inicio
                5 -> Movimientos
                6 -> Cuenta(a[0]!!)
                7 -> FormMovimiento(a[0], a[1], a[2]!!.toBooleanStrict(), a[3], a[4]!!.toBooleanStrict())
                8 -> AccionesMovimiento(a[0]!!)
                9 -> FormCuenta(a[0], a[1]?.let(AccountKind::valueOf))
                10 -> Tarjetas
                11 -> Tarjeta(a[0])
                12 -> CondicionesTarjeta(a[0])
                13 -> AplazarCompra(a[0], a[1])
                14 -> Presupuesto
                15 -> EditarPresupuesto
                16 -> Flujo
                17 -> Patrimonio
                18 -> Informes
                19 -> Score
                20 -> PagosFijos
                21 -> FormPagoFijo(a[0])
                22 -> Metas
                23 -> Meta(a[0]!!)
                24 -> FormMeta(a[0])
                25 -> Cartera
                26 -> Activo(a[0]!!)
                27 -> InversionesRecurrentes
                28 -> Hogar
                29 -> Invitar
                30 -> Mas
                31 -> Categorias
                32 -> ImportarCsv(a[0])
                33 -> BorrarDatos
                34 -> DetalleMovimiento(a[0]!!)
                35 -> Aportar(a[0]!!)
                36 -> PagosDelMes
                37 -> EscanerQr
                38 -> ApuntarScore
                39 -> FormActivo(a[0])
                40 -> ApuntarPrecio(a[0]!!)
                41 -> Vender(a[0]!!)
                42 -> FormPlan(a[0])
                43 -> Calendario
                44 -> DiaDeCobro
                45 -> FormExtra(a[0])
                46 -> ConfirmarCargo(a[0]!!)
                47 -> ResumenSemanal
                else -> null
            }
            route?.takeIf { it.args.size == a.size }
        }.getOrNull()
    }
}
