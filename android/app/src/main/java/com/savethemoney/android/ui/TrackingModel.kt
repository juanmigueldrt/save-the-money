package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.NetWorth
import com.savethemoney.android.data.NetWorthPoint
import kotlinx.coroutines.CancellationException
import java.time.LocalDate
import java.time.YearMonth

/** Patrimonio con su historia, score e informes (TrackingModel de iOS). */
class TrackingModel(private val household: Household, private val service: FinanceService, val today: () -> LocalDate) {
    /** Todos los movimientos: rehacen el patrimonio mes a mes y alimentan los informes. */
    var allMovements by mutableStateOf(emptyList<Movement>())
        private set
    var scores by mutableStateOf(emptyList<CreditScore>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    val latestScore: CreditScore? get() = scores.firstOrNull()

    fun history(accounts: List<Account>, months: Int): List<NetWorthPoint> =
        NetWorth.history(accounts, allMovements, months, YearMonth.from(today()))

    /** Meses desde el primer movimiento hasta hoy, ambos incluidos. */
    val monthsWithData: Int get() {
        val first = allMovements.minOfOrNull { YearMonth.from(it.day) } ?: return 2
        return (java.time.temporal.ChronoUnit.MONTHS.between(first, YearMonth.from(today())).toInt() + 1).coerceAtLeast(2)
    }

    private suspend fun guarded(block: suspend () -> Unit) {
        try {
            block()
            error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
    }

    suspend fun loadMovements() = guarded {
        allMovements = service.movements(household.id, LocalDate.of(1900, 1, 1), LocalDate.of(2999, 12, 31))
    }

    suspend fun loadScores() = guarded { scores = service.creditScores() }

    suspend fun add(score: CreditScore) {
        score.issue?.let { throw AppError.InvalidInput(it) }
        service.addCreditScore(score)
        scores = service.creditScores()
    }

    suspend fun delete(score: CreditScore) {
        service.deleteCreditScore(score.id)
        scores = scores.filter { it.id != score.id }
    }
}
