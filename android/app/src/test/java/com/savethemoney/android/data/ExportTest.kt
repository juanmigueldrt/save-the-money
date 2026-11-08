package com.savethemoney.android.data

import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.savethemoney.android.ui.leerQr
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class ExportTest {
    @Test
    fun csvParaExcelConFormulasDesactivadas() {
        val cuenta = Account("a", "h", "Principal", AccountKind.entries.first())
        val movs = listOf(
            Movement("2", "h", "a", null, "2026-11-02", -1_205, "=HYPERLINK(1)"),
            Movement("1", "h", "a", null, "2026-11-01", 123_456, "Sueldo; extra", "dijo \"hola\""),
        )
        assertEquals(
            "Fecha;Cuenta;Categoría;Descripción;Importe;Moneda;Notas\r\n" +
                "01/11/2026;Principal;;\"Sueldo; extra\";1234,56;EUR;\"dijo \"\"hola\"\"\"\r\n" +
                "02/11/2026;Principal;;'=HYPERLINK(1);-12,05;EUR;\r\n",
            MovementsCsv.text(movs, listOf(cuenta), emptyList()),
        )
        assertEquals(0xEF.toByte(), MovementsCsv.bytes(movs, listOf(cuenta), emptyList())[0])
    }

    @Test
    fun pagosDelMesSinIngresosNiArchivados() {
        val base = RecurringSeries("s", "h", "Luz", RecurringKind.Essential, 5_000, startsOn = "2026-01-10")
        val b = MonthlyBills(
            listOf(
                base,
                base.copy(id = "t", name = "Tele", kind = RecurringKind.Subscription, amountMinor = 1_299, startsOn = "2026-11-05", introMinor = 599, introCharges = 3),
                base.copy(id = "i", kind = RecurringKind.Income),
                base.copy(id = "x", archivedAt = "2026-01-01"),
            ),
            YearMonth.of(2026, 11),
        )
        assertEquals(listOf("Tele", "Luz"), b.lines.map { it.name })
        assertEquals(5_599L, b.total)
        assertEquals(599L, b.total(RecurringKind.Subscription))
        assertEquals(5_000L, b.pending(LocalDate.parse("2026-11-06")))
        assertEquals("pagos-2026-11.pdf", b.fileName)
    }

    @Test
    fun leeElQrDeLaInvitacion() {
        val enlace = InviteCode.parse("4K9Q2X")!!.link
        val matriz = QRCodeWriter().encode(enlace, BarcodeFormat.QR_CODE, 400, 400)
        val luma = ByteArray(400 * 400) { i -> if (matriz.get(i % 400, i / 400)) 0 else -1 }
        assertEquals(enlace, leerQr(luma, 400, 400))
        assertEquals("4K9Q2X", InviteCode.parse(leerQr(luma, 400, 400)!!)?.value)
        assertNull(leerQr(ByteArray(400 * 400) { -1 }, 400, 400))
    }
}
