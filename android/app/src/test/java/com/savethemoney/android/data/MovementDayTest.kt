package com.savethemoney.android.data

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.time.LocalDate

/** La fecha del movimiento se analiza una vez al crearlo (ORC-128): mismo valor que antes, también al leerlo del servidor. */
class MovementDayTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test fun laFechaSaleIgualAlLeerElMovimientoDelServidor() {
        val fila = """{"id":"m1","household_id":"h","account_id":"a","booked_on":"2026-02-28","amount_minor":-1250,"description":"Café"}"""
        val m = json.decodeFromString<Movement>(fila)
        assertEquals(LocalDate.of(2026, 2, 28), m.day)
        // Con hora también vale: sólo cuentan los diez primeros caracteres.
        assertEquals(LocalDate.of(2026, 11, 26), m.copy(bookedOn = "2026-11-26T23:59:00+01:00").day)
    }

    @Test fun laFechaAnalizadaNoSeEnviaAlServidor() {
        val m = Movement("m1", "h", "a", null, "2026-02-28", -1250, "Café")
        assertFalse(json.encodeToString(Movement.serializer(), m).contains("\"day\""))
    }
}
