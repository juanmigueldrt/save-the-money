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
        assertEquals(AppError.InvalidCredentials, SupabaseBackend.authError("Invalid login credentials"))
        assertEquals(AppError.UsernameTaken, SupabaseBackend.authError("user_already_exists"))
    }
}
