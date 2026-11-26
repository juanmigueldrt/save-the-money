package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.MovementDraft
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/** Cambio del patrimonio del mes: mes del hogar y cuentas archivadas. Datos inventados. */
class PatrimonioMesTest {
    private val today = LocalDate.of(2026, 11, 10)

    @Test
    fun cambioDelMesSigueElInicioDelHogarYLasArchivadasHastaSuDia() = runBlocking {
        val service = InMemoryFinance()
        val corriente = service.createAccount(AccountDraft("Corriente", AccountKind.Checking), "h")
        val antigua = service.createAccount(AccountDraft("Antigua", AccountKind.Savings), "h")
        val vieja = service.createAccount(AccountDraft("Vieja", AccountKind.Savings), "h")
        service.updateAccount(antigua.copy(archivedAt = "2026-11-05T00:00:00Z"))
        service.updateAccount(vieja.copy(archivedAt = "2026-10-01T00:00:00Z"))
        service.addMovement(MovementDraft(corriente.id, null, LocalDate.of(2026, 10, 26), -7_000, "Octubre"), "h")
        service.addMovement(MovementDraft(corriente.id, null, LocalDate.of(2026, 11, 3), -5_000, "Noviembre"), "h")
        service.addMovement(MovementDraft(antigua.id, null, LocalDate.of(2026, 11, 4), -99_000, "Antes de archivar"), "h")
        service.addMovement(MovementDraft(vieja.id, null, LocalDate.of(2026, 11, 2), -1_000, "Archivada antes"), "h")

        val model = FinanceModel(Household("h", "Casa", monthStartDay = 25), service, { today })
        model.load()
        assertEquals("inicio 25: desde el 25 de octubre; la cuenta archivada el 5 cuenta lo del 4", -111_000L, model.netThisMonth)

        model.household = Household("h", "Casa")
        assertEquals("inicio 1: octubre no cuenta; la archivada el 5 cuenta lo del 4", -104_000L, model.netThisMonth)
    }
}
