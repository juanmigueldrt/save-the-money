package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class CoreTest {
    @Test
    fun usernameNormalizesAndValidates() {
        assertEquals("ana.g", Username.parse("  Ana.G ").getOrThrow().value)
        assertEquals("ana@savethemoney.invalid", Username.parse("ana").getOrThrow().authEmail)
        assertTrue(Username.parse("an").isFailure)
        assertTrue(Username.parse("año").isFailure)
        assertTrue(Username.parse("a".repeat(31)).isFailure)
    }

    @Test
    fun inviteCodeAcceptsSpacesDashesAndLinks() {
        assertEquals("4K9Q2X", InviteCode.parse("4k9 q2x")?.value)
        assertEquals("4K9Q2X", InviteCode.parse("4K9-Q2X")?.value)
        assertEquals("4K9Q2X", InviteCode.parse("savethemoney://unirse/4K9Q2X")?.value)
        assertNull(InviteCode.parse("4K9Q2O")) // la O no está en el alfabeto
        assertNull(InviteCode.parse("4K9Q2"))
    }

    @Test
    fun signUpFormReportsFirstIssue() {
        assertEquals("La contraseña necesita al menos 10 caracteres.", SignUpForm("ana", password = "corta", passwordConfirmation = "corta").firstIssue)
        assertEquals("Las contraseñas no coinciden.", SignUpForm("ana", password = "0123456789", passwordConfirmation = "x").firstIssue)
        assertNull(SignUpForm("ana", " ", "0123456789", "0123456789").firstIssue)
        assertNull(SignUpForm(displayName = "  ").trimmedDisplayName)
    }

    @Test
    fun inviteFlowInMemory() = runBlocking {
        var now = Instant.parse("2026-11-05T10:00:00Z")
        val backend = InMemoryBackend { now }
        backend.signUp(Username.parse("ana").getOrThrow(), "0123456789", "Ana")
        val home = backend.createHousehold("Casa de Ana")
        val code = InviteCode.parse(backend.createInvite(home.id).code)!!
        backend.signOut()
        backend.signUp(Username.parse("leo").getOrThrow(), "0123456789", null)
        assertEquals(home, backend.acceptInvite(code))
        assertEquals(home.id, backend.myProfile().defaultHouseholdId)
        assertEquals(2, backend.members(home.id).size)
        // Un solo uso
        runCatching { backend.acceptInvite(code) }.exceptionOrNull().let { assertEquals(AppError.InvalidOrExpiredInvite, it) }
        // Caducan a las 48 horas
        val second = backend.createInvite(home.id)
        now += Duration.ofHours(49)
        assertTrue(backend.pendingInvites(home.id).none { it.id == second.id })
    }

    @Test
    fun onlyOwnerRemovesMembers() = runBlocking {
        val backend = InMemoryBackend()
        val ana = backend.signUp(Username.parse("ana").getOrThrow(), "0123456789", "Ana")
        val home = backend.createHousehold("Casa de Ana")
        val code = InviteCode.parse(backend.createInvite(home.id).code)!!
        backend.signOut()
        val leo = backend.signUp(Username.parse("leo").getOrThrow(), "0123456789", null)
        backend.acceptInvite(code)
        // Un miembro no puede quitar al dueño
        assertTrue(runCatching { backend.removeMember(home.id, ana) }.exceptionOrNull() is AppError.InvalidInput)
        backend.signOut()
        backend.signIn(Username.parse("ana").getOrThrow(), "0123456789")
        backend.removeMember(home.id, leo)
        assertEquals(listOf(ana), backend.members(home.id).map { it.profile.id })
    }

    @Test
    fun wrongPasswordAndDuplicateUser() = runBlocking {
        val backend = InMemoryBackend()
        val ana = Username.parse("ana").getOrThrow()
        backend.signUp(ana, "0123456789", null)
        assertEquals(AppError.UsernameTaken, runCatching { backend.signUp(ana, "0123456789", null) }.exceptionOrNull())
        assertEquals(AppError.InvalidCredentials, runCatching { backend.signIn(ana, "otra-cosa-xx") }.exceptionOrNull())
    }

    @Test
    fun serverErrorsMapToSpanishMessages() {
        assertEquals(AppError.InvalidOrExpiredInvite, SupabaseBackend.postgresError("P0002", ""))
        assertEquals(AppError.AlreadyMember, SupabaseBackend.postgresError("23505", "already a member"))
        assertEquals(TransferDraft.STORED_WITH_OTHER_DATA, SupabaseBackend.postgresError("STM01", "").message)
        assertEquals(InvestmentTrade.NOT_ENOUGH_SHARES, SupabaseBackend.postgresError("STM02", "").message)
        assertEquals(InvestmentTrade.NEEDED_BY_LATER_SALE, SupabaseBackend.postgresError("STM03", "").message)
        assertEquals(AppError.TooManyInviteAttempts(7), SupabaseBackend.postgresError("STM04", "too many invite attempts; retry in 7 min"))
        assertEquals(
            "Has probado demasiados códigos. Vuelve a intentarlo dentro de 1 minuto.",
            SupabaseBackend.postgresError("STM04", "too many invite attempts; retry in 1 min").message,
        )
        assertEquals(AppError.TooManyInviteAttempts(15), SupabaseBackend.postgresError("STM04", "otro texto"))
        assertEquals(AppError.MovementChanged, SupabaseBackend.postgresError("STM05", ""))
        assertEquals(Money.BASE_CURRENCY_LOCKED, SupabaseBackend.postgresError("STM06", "").message)
        assertEquals(OWNER_MUST_TRANSFER, SupabaseBackend.postgresError("STM08", "").message)
        assertEquals(AppError.InvalidCredentials, SupabaseBackend.authError("Invalid login credentials"))
        assertEquals(AppError.UsernameTaken, SupabaseBackend.authError("user_already_exists"))
    }

    @Test
    fun soloElDuplicadoDelNombreDeUsuarioDiceNombreEnUso() {
        val generico = "Ya hay un registro igual guardado. Revisa el formulario."
        fun duplicado(restriccion: String) =
            SupabaseBackend.postgresError("23505", "duplicate key value violates unique constraint \"$restriccion\"")
        assertEquals(AppError.UsernameTaken, duplicado("profiles_username_key"))
        assertEquals("Ya hay una categoría con ese nombre.", duplicado("categories_household_name_idx").message)
        assertEquals(generico, duplicado("card_installments_transaction_id_key").message)
        assertEquals(generico, duplicado("holding_prices_holding_id_priced_on_key").message)
        assertEquals(generico, duplicado("budgets_household_creator_month_key").message)
        assertEquals(generico, SupabaseBackend.postgresError("23505", "duplicate key value violates unique constraint").message)
    }
}
