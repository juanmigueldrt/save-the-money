package com.savethemoney.android.ui

import androidx.compose.runtime.derivedStateOf
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

    /** Qué lectura gana cuando dos se cruzan (ORC-144). */
    private val turns = ReadTurns()

    val latestScore: CreditScore? get() = scores.firstOrNull()

    fun history(accounts: List<Account>, months: Int): List<NetWorthPoint> =
        NetWorth.history(accounts, allMovements, months, YearMonth.from(today()))

    /** Meses desde el primer movimiento hasta hoy, ambos incluidos. */
    val monthsWithData: Int get() {
        val first = firstMonth ?: return 2
        return (java.time.temporal.ChronoUnit.MONTHS.between(first, YearMonth.from(today())).toInt() + 1).coerceAtLeast(2)
    }

    /** Se recalcula sólo cuando cambian los movimientos, no en cada recomposición. */
    private val firstMonth by derivedStateOf { allMovements.minOfOrNull { YearMonth.from(it.day) } }

    private suspend fun guarded(block: suspend (turn: Long) -> Unit) {
        val turn = turns.next()
        try {
            block(turn)
            turns.store(::error, null, turn)
        } catch (e: Exception) {
            turns.fallaCarga(::error, turn, e)
        }
    }

    suspend fun loadMovements() = guarded { turn ->
        turns.store(::allMovements, service.movements(household.id, LocalDate.of(1900, 1, 1), LocalDate.of(2999, 12, 31)), turn)
    }

    suspend fun loadScores() = guarded { turn -> turns.store(::scores, service.creditScores(), turn) }

    // Escrituras: cada una corre como [escritura], así que termina (y recarga) aunque se salga de la pantalla.

    /** Una escritura falló cuando su pantalla ya no estaba: el aviso sale en el error del modelo. */
    private fun sinPantalla(e: Exception) {
        turns.changed(::error, (e as? AppError)?.message ?: AppError.Unknown("app").message)
    }

    suspend fun add(score: CreditScore): Unit = escritura(::sinPantalla) {
        score.issue?.let { throw AppError.InvalidInput(it) }
        val saved = service.addCreditScore(score)
        // Se ve ya, aunque falle la recarga: así no se vuelve a apuntar.
        turns.changed(::scores, (scores + saved).sortedByDescending { it.recordedOn })
        reloadAfterSave { reloadScores() }?.let { turns.changed(::error, it) }
    }

    suspend fun delete(score: CreditScore): Unit = escritura(::sinPantalla) {
        service.deleteCreditScore(score.id)
        turns.changed(::scores, scores.filter { it.id != score.id })
    }

    private suspend fun reloadScores() {
        val turn = turns.next()
        turns.store(::scores, service.creditScores(), turn)
    }
}
