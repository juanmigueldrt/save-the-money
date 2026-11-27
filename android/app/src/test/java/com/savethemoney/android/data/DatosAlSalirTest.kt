package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class DatosAlSalirTest {
    private val password = "contrasena-de-prueba"

    private fun user(name: String) = Username.parse(name).getOrThrow()

    /**
     * ORC-56, lo mismo que `supabase/tests/database/25_orc56_datos_al_salir.test.sql` y HouseholdFlowTests.swift: quien sale
     * pierde lo suyo en el momento; a quien quitan le quedan 30 días para exportar. Datos inventados.
     */
    @Test
    fun datosDeQuienSaleODeQuienQuitan() = runBlocking {
        var now = Instant.parse("2027-01-15T08:00:00Z")
        val backend = InMemoryBackend { now }
        val finance = InMemoryFinance(backend)
        val day = LocalDate.of(2026, 11, 2)

        suspend fun note(name: String, home: String) {
            val account = finance.createAccount(AccountDraft("Cuenta de $name"), home)
            finance.addMovement(MovementDraft(account.id, null, day, -4500, "Compra de $name"), home)
        }

        suspend fun signIn(name: String) {
            backend.signOut()
            backend.signIn(user(name), password)
        }

        suspend fun enter(name: String, home: String) {
            signIn("ana")
            val code = InviteCode.parse(backend.createInvite(home).code)!!
            signIn(name)
            backend.acceptInvite(code)
        }

        for (name in listOf("bruno", "carla", "ana")) backend.signUp(user(name), password, null)
        val home = backend.createHousehold("Casa de prueba").id
        note("Ana", home)

        // Bruno entra, apunta y sale por su cuenta: se borra todo lo suyo.
        enter("bruno", home)
        note("Bruno", home)
        val seeded = finance.categories(home).size
        backend.leave(home)
        assertEquals("quien sale por su cuenta no queda como quitado", emptyList<RemovedHousehold>(), backend.removedHouseholds())
        enter("bruno", home)
        assertEquals("al salir se borraron sus cuentas", emptyList<Account>(), finance.accounts(home))
        assertEquals("y sus movimientos", emptyList<Movement>(), finance.movements(home, null, 100))
        assertEquals("al volver empieza con las categorías de partida", seeded, finance.categories(home).size)

        // Carla entra y apunta; Ana la quita: sus datos siguen 30 días y sólo ella puede exportarlos.
        enter("carla", home)
        note("Carla", home)
        assertEquals(seeded, finance.categories(home).size)
        val carla = backend.myProfile().id
        signIn("ana")
        backend.removeMember(home, carla)
        assertTrue("la dueña no exporta los datos de quien ha quitado", runCatching { backend.removedHouseholdExport(home) }.isFailure)
        assertEquals("lo de Ana no se toca", listOf("Cuenta de Ana"), finance.accounts(home).map { it.name })

        signIn("carla")
        assertEquals("Carla ya no está en el hogar", emptyList<Household>(), backend.households())
        assertEquals(emptyList<Account>(), finance.accounts(home))
        assertEquals(
            listOf(RemovedHousehold(home, "Casa de prueba", now.plus(Duration.ofDays(30)).toString())),
            backend.removedHouseholds(),
        )
        val export = backend.removedHouseholdExport(home)
        assertEquals(listOf("Cuenta de Carla"), export.accounts.map { it.name })
        assertEquals(listOf("Compra de Carla"), export.movements.map { it.description })
        assertEquals(seeded, export.categories.size)

        // Vuelve a entrar dentro del plazo: recupera lo suyo y no queda nada que purgar.
        enter("carla", home)
        assertEquals(listOf("Cuenta de Carla"), finance.accounts(home).map { it.name })
        assertEquals(emptyList<RemovedHousehold>(), backend.removedHouseholds())
        assertEquals("sin categorías repetidas", seeded, finance.categories(home).size)

        // Ana la quita otra vez y pasan los 30 días: ya no se puede exportar y los datos se borran.
        signIn("ana")
        backend.removeMember(home, carla)
        now = now.plus(Duration.ofDays(30))
        signIn("carla")
        assertEquals(emptyList<RemovedHousehold>(), backend.removedHouseholds())
        assertTrue("fuera de plazo no se exporta", runCatching { backend.removedHouseholdExport(home) }.isFailure)
        enter("carla", home)
        assertEquals("pasado el plazo se borró todo lo suyo", emptyList<Account>(), finance.accounts(home))
        assertEquals("y vuelve a empezar con las categorías de partida", seeded, finance.categories(home).size)
    }

    /** Quien vuelve con el plazo ya vencido, sin haber abierto antes la lista, tampoco recupera nada. */
    @Test
    fun volverFueraDePlazoNoRecuperaLosDatos() = runBlocking {
        var now = Instant.parse("2027-01-15T08:00:00Z")
        val backend = InMemoryBackend { now }
        val finance = InMemoryFinance(backend)
        backend.signUp(user("carla"), password, null)
        val carla = backend.myProfile().id
        backend.signUp(user("ana"), password, null)
        val home = backend.createHousehold("Casa de prueba").id
        val first = InviteCode.parse(backend.createInvite(home).code)!!
        backend.signIn(user("carla"), password)
        backend.acceptInvite(first)
        finance.createAccount(AccountDraft("Cuenta de Carla"), home)
        backend.signIn(user("ana"), password)
        backend.removeMember(home, carla)

        now = now.plus(Duration.ofDays(30))
        val second = InviteCode.parse(backend.createInvite(home).code)!!
        backend.signIn(user("carla"), password)
        backend.acceptInvite(second)

        assertEquals(emptyList<Account>(), finance.accounts(home))
    }

    /** Las dos funciones devuelven más columnas de las que lee la app (`removed_at`, `owner_id`, `created_at`…): se ignoran. */
    @Test
    fun laRespuestaDelServidorSeLeeAunqueTraigaColumnasDeMas() {
        // Como el cliente de Supabase: las claves que no conoce no son un error.
        val json = Json { ignoreUnknownKeys = true }

        val removed = json.decodeFromString<List<RemovedHousehold>>(
            """[{"household_id":"hogar","name":"Casa de prueba","removed_at":"2026-11-27T09:00:00.123456+00:00","export_until":"2026-12-27T09:00:00.123456+00:00"}]""",
        )
        assertEquals(listOf(RemovedHousehold("hogar", "Casa de prueba", "2026-12-27T09:00:00.123456+00:00")), removed)
        assertEquals(LocalDate.of(2026, 12, 27), removed.single().exportDay(ZoneOffset.UTC))
        // El día es el del dispositivo: a las 9:00 UTC, diez horas al oeste aún es el 26.
        assertEquals(LocalDate.of(2026, 12, 26), removed.single().exportDay(ZoneOffset.ofHours(-10)))
        assertNull("una fecha que no se entiende no rompe la pantalla", RemovedHousehold("hogar", "Casa", "pronto").exportDay())

        val export = json.decodeFromString<RemovedHouseholdExport>(
            """
            {
              "accounts": [{"id":"cuenta","household_id":"hogar","name":"Cuenta de Carla","kind":"checking","currency":"EUR",
                "opening_balance_minor":10000,"owner_id":null,"archived_at":null,"is_default":true,"include_in_net_worth":true,
                "created_at":"2026-11-01T10:00:00+00:00","updated_at":"2026-11-01T10:00:00+00:00","deleted_at":null}],
              "categories": [{"id":"categoria","household_id":"hogar","name":"Supermercado","kind":"expense","budget_group":"needs",
                "icon":"cart","owner_id":"carla","created_at":"2026-11-01T10:00:00+00:00","updated_at":"2026-11-01T10:00:00+00:00"}],
              "movements": [{"id":"movimiento","household_id":"hogar","account_id":"cuenta","category_id":"categoria",
                "booked_on":"2026-11-02","amount_minor":-4500,"description":"Compra de Carla","notes":null,"import_hash":null,
                "excluded":false,"reviewed_at":null,"payee":null,"tags":["casa"],"transfer_id":null,"trade_id":null,
                "owner_id":"carla","created_at":"2026-11-02T10:00:00+00:00","updated_at":"2026-11-02T10:00:00+00:00"}]
            }
            """.trimIndent(),
        )
        assertEquals(listOf("Cuenta de Carla"), export.accounts.map { it.name })
        assertEquals(listOf(BudgetGroup.Needs), export.categories.map { it.budgetGroup })
        assertEquals(listOf(-4500L), export.movements.map { it.amountMinor })
        assertEquals(listOf(listOf("casa")), export.movements.map { it.tags })
        // Lo exportado sirve tal cual para el CSV de siempre.
        assertEquals(
            "Fecha;Cuenta;Categoría;Descripción;Importe;Moneda;Notas\r\n02/11/2026;Cuenta de Carla;Supermercado;Compra de Carla;-45,00;EUR;\r\n",
            MovementsCsv.text(export.movements, export.accounts, export.categories),
        )
    }

    /** ORC-59, lo mismo que `testElPropietarioNoDejaElHogarSinPropietario` de HouseholdFlowTests.swift. */
    @Test
    fun elPropietarioNoDejaElHogarSinPropietario() = runBlocking {
        val backend = InMemoryBackend()
        suspend fun role(name: String, home: String) = backend.members(home).firstOrNull { it.profile.username == name }?.role

        backend.signUp(user("ana"), password, null)
        val home = backend.createHousehold("Casa de prueba").id
        val invite = InviteCode.parse(backend.createInvite(home).code)!!
        val spare = InviteCode.parse(backend.createInvite(home).code)!!
        backend.signOut()
        val bruno = backend.signUp(user("bruno"), password, null)
        backend.acceptInvite(invite)
        assertTrue("un miembro no puede hacerse propietario", runCatching { backend.transferHousehold(home, bruno) }.isFailure)
        backend.signOut()

        backend.signIn(user("ana"), password)
        assertEquals(
            "la propietaria no puede salir con otros miembros dentro",
            OWNER_MUST_TRANSFER,
            runCatching { backend.leave(home) }.exceptionOrNull()?.message,
        )
        assertTrue("no se traspasa a quien no es miembro", runCatching { backend.transferHousehold(home, "nadie") }.isFailure)
        backend.transferHousehold(home, bruno)
        assertEquals(MemberRole.Member, role("ana", home))
        assertEquals(MemberRole.Owner, role("bruno", home))
        backend.leave(home)
        backend.signOut()

        // Bruno, propietario y único miembro, sale: el hogar se borra y sus invitaciones dejan de valer.
        backend.signIn(user("bruno"), password)
        backend.leave(home)
        assertEquals(emptyList<Household>(), backend.households())
        assertEquals("la invitación de un hogar borrado no vale", AppError.InvalidOrExpiredInvite, runCatching { backend.acceptInvite(spare) }.exceptionOrNull())
    }

    /** ORC-59: un hogar sin miembros sigue mientras alguien a quien quitaron pueda exportar; vencido el plazo, se borra. */
    @Test
    fun elHogarVacioSeBorraCuandoVenceElPlazoDeQuienFueQuitado() = runBlocking {
        val start = Instant.parse("2027-01-15T08:00:00Z")
        var now = start
        val backend = InMemoryBackend { now }
        val bruno = backend.signUp(user("bruno"), password, null)
        backend.signUp(user("ana"), password, null)
        val home = backend.createHousehold("Casa de prueba").id
        val invite = InviteCode.parse(backend.createInvite(home).code)!!
        val spare = InviteCode.parse(backend.createInvite(home).code)!!
        backend.signIn(user("bruno"), password)
        backend.acceptInvite(invite)

        // Ana quita a Bruno y, ya sola, sale: el hogar se queda sin miembros.
        backend.signIn(user("ana"), password)
        backend.removeMember(home, bruno)
        backend.leave(home)
        assertEquals(emptyList<Household>(), backend.households())

        backend.signIn(user("bruno"), password)
        assertEquals("a Bruno le queda su plazo: el hogar sigue", listOf("Casa de prueba"), backend.removedHouseholds().map { it.name })
        backend.removedHouseholdExport(home)

        now = start.plus(Duration.ofDays(30))
        assertEquals(emptyList<RemovedHousehold>(), backend.removedHouseholds())
        assertTrue("fuera de plazo no se exporta", runCatching { backend.removedHouseholdExport(home) }.isFailure)
        // El reloj vuelve atrás para que la invitación no esté caducada por fecha: lo que la rechaza es que el hogar ya no existe.
        now = start
        assertEquals("con el plazo vencido el hogar se borró", AppError.InvalidOrExpiredInvite, runCatching { backend.acceptInvite(spare) }.exceptionOrNull())
    }

    /**
     * ORC-74, lo mismo que `supabase/tests/database/27_orc74_borrar_cuenta.test.sql` y
     * `testBorrarLaCuentaSeLlevaLoMioYNoLoDeLosDemas` de HouseholdFlowTests.swift. Datos inventados.
     */
    @Test
    fun borrarLaCuentaSeLlevaLoMioYNoLoDeLosDemas() = runBlocking {
        val backend = InMemoryBackend()
        val finance = InMemoryFinance(backend)
        val day = LocalDate.of(2026, 11, 2)

        suspend fun note(name: String, home: String) {
            val account = finance.createAccount(AccountDraft("Cuenta de $name"), home)
            finance.addMovement(MovementDraft(account.id, null, day, -4500, "Compra de $name"), home)
        }

        // Ana es propietaria de un hogar con Bruno dentro y de otro en el que está sola.
        backend.signUp(user("ana"), password, null)
        val shared = backend.createHousehold("Casa compartida").id
        val alone = backend.createHousehold("Casa de Ana").id
        note("Ana", shared)
        note("Ana", alone)
        val invite = InviteCode.parse(backend.createInvite(shared).code)!!
        val aloneInvite = InviteCode.parse(backend.createInvite(alone).code)!!
        backend.signOut()
        backend.signUp(user("bruno"), password, null)
        backend.acceptInvite(invite)
        note("Bruno", shared)
        backend.signOut()

        backend.signIn(user("ana"), password)
        assertEquals(
            "con la contraseña equivocada no se borra nada",
            AppError.WrongCurrentPassword,
            runCatching { backend.deleteAccount("otra-contrasena") }.exceptionOrNull(),
        )
        assertEquals(listOf("Cuenta de Ana"), finance.accounts(shared).map { it.name })
        backend.deleteAccount(password)
        assertNull("tras borrar la cuenta no queda sesión", backend.currentUserId())
        assertEquals(
            "la cuenta borrada ya no existe",
            AppError.InvalidCredentials,
            runCatching { backend.signIn(user("ana"), password) }.exceptionOrNull(),
        )

        // Bruno se queda con el hogar compartido y con lo suyo; el otro hogar ya no existe.
        backend.signIn(user("bruno"), password)
        val members = backend.members(shared)
        assertEquals(listOf("bruno"), members.map { it.profile.username })
        assertEquals(listOf(MemberRole.Owner), members.map { it.role })
        assertEquals(listOf("Cuenta de Bruno"), finance.accounts(shared).map { it.name })
        assertEquals(listOf("Compra de Bruno"), finance.movements(shared, null, 100).map { it.description })
        assertEquals(
            "el hogar en el que Ana estaba sola se borró",
            AppError.InvalidOrExpiredInvite,
            runCatching { backend.acceptInvite(aloneInvite) }.exceptionOrNull(),
        )
    }
}
