import XCTest
@testable import STMCore

final class HouseholdFlowTests: XCTestCase {
    func testSignUpFormValidation() {
        XCTAssertEqual(SignUpForm(username: "ab", password: "x").firstIssue, .username(.tooShort))
        XCTAssertEqual(SignUpForm(username: "ana", password: "corta").firstIssue, .passwordTooShort)
        XCTAssertEqual(SignUpForm(username: "ana", password: "contrasena-1", passwordConfirmation: "otra-cosa-1").firstIssue, .passwordsDoNotMatch)
        XCTAssertNil(SignUpForm(username: "ana", password: "contrasena-1", passwordConfirmation: "contrasena-1").firstIssue)
        XCTAssertNil(SignUpForm(displayName: "   ").trimmedDisplayName)
    }

    func testHouseholdName() {
        XCTAssertEqual(HouseholdName.validated("  Casa  "), "Casa")
        XCTAssertNil(HouseholdName.validated("   "))
        XCTAssertNil(HouseholdName.validated(String(repeating: "a", count: 81)))
    }

    func testInviteFlowBetweenTwoPeople() async throws {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"

        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: "Ana")
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let invite = try await backend.createInvite(for: home.id)
        XCTAssertNotNil(invite.inviteCode)
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        let empty = try await backend.households()
        XCTAssertTrue(empty.isEmpty)
        let joined = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        XCTAssertEqual(joined.id, home.id)

        let members = try await backend.members(of: home.id)
        XCTAssertEqual(Set(members.map(\.profile.username)), ["ana", "bruno"])
        XCTAssertEqual(members.first { $0.profile.username == "bruno" }?.role, .member)
        let profile = try await backend.myProfile()
        XCTAssertEqual(profile.defaultHouseholdId, home.id)

        do {
            _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
            XCTFail("un código usado no debe valer otra vez")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidOrExpiredInvite)
        }
    }

    func testDemasiadosCodigosDiceCuantoEsperar() {
        XCTAssertEqual(
            AppError.tooManyInviteAttempts(minutes: 15).errorDescription,
            "Has probado demasiados códigos. Vuelve a intentarlo dentro de 15 minutos."
        )
        XCTAssertEqual(
            AppError.tooManyInviteAttempts(minutes: 1).errorDescription,
            "Has probado demasiados códigos. Vuelve a intentarlo dentro de 1 minuto."
        )
    }

    func testOwnerRemovesMember() async throws {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"
        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: "Ana")
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let invite = try await backend.createInvite(for: home.id)
        try await backend.signOut()
        _ = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        let members = try await backend.members(of: home.id)
        let ana = try XCTUnwrap(members.first { $0.profile.username == "ana" }).profile.id
        let bruno = try XCTUnwrap(members.first { $0.profile.username == "bruno" }).profile.id

        do {
            try await backend.removeMember(ana, from: home.id)
            XCTFail("un miembro no puede quitar al dueño")
        } catch {}
        try await backend.signOut()

        _ = try await backend.signIn(username: Username("ana"), password: password)
        try await backend.removeMember(bruno, from: home.id)
        let left = try await backend.members(of: home.id)
        XCTAssertEqual(left.map(\.profile.username), ["ana"])
    }

    /// ORC-59, lo mismo que `supabase/tests/database/26_orc59_hogar_sin_dueno.test.sql`: el propietario no deja el
    /// hogar sin propietario y un hogar sin miembros se borra. Datos inventados.
    func testElPropietarioNoDejaElHogarSinPropietario() async throws {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"
        func rejected(_ message: String, _ call: () async throws -> Void) async {
            do {
                try await call()
                XCTFail(message)
            } catch {}
        }
        func role(_ username: String, in home: UUID) async throws -> MemberRole? {
            try await backend.members(of: home).first { $0.profile.username == username }?.role
        }

        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba").id
        let invite = try await backend.createInvite(for: home)
        let spare = try await backend.createInvite(for: home)
        try await backend.signOut()
        let bruno = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        await rejected("un miembro no puede hacerse propietario") { try await backend.transferHousehold(home, to: bruno) }
        try await backend.signOut()

        _ = try await backend.signIn(username: Username("ana"), password: password)
        do {
            try await backend.leave(householdId: home)
            XCTFail("la propietaria no puede salir con otros miembros dentro")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidInput(LeavingHousehold.ownerMustTransfer))
        }
        await rejected("no se traspasa a quien no es miembro") { try await backend.transferHousehold(home, to: UUID()) }
        try await backend.transferHousehold(home, to: bruno)
        let anaRole = try await role("ana", in: home)
        let brunoRole = try await role("bruno", in: home)
        XCTAssertEqual(anaRole, .member)
        XCTAssertEqual(brunoRole, .owner)
        try await backend.leave(householdId: home)
        try await backend.signOut()

        // Bruno, propietario y único miembro, sale: el hogar se borra y sus invitaciones dejan de valer.
        _ = try await backend.signIn(username: Username("bruno"), password: password)
        try await backend.leave(householdId: home)
        let left = try await backend.households()
        XCTAssertEqual(left, [])
        await rejected("la invitación de un hogar borrado no vale") { _ = try await backend.acceptInvite(XCTUnwrap(spare.inviteCode)) }
    }

    /// ORC-56, lo mismo que `supabase/tests/database/25_orc56_datos_al_salir.test.sql`: quien sale pierde lo suyo
    /// en el momento; a quien quitan le quedan 30 días para exportar. Datos inventados.
    func testDatosDeQuienSaleODeQuienQuitan() async throws {
        final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_800_000_000) }
        let clock = Clock()
        let backend = InMemoryBackend(now: { clock.date })
        let password = "contrasena-de-prueba"
        let day = CalendarDay(year: 2026, month: 11, day: 2)!
        func note(_ name: String, in home: UUID) async throws {
            let account = try await backend.createAccount(AccountDraft(name: "Cuenta de \(name)"), in: home)
            _ = try await backend.addMovement(MovementDraft(accountId: account.id, bookedOn: day, amount: Money(minor: -4500),
                                                            description: "Compra de \(name)"), in: home)
        }
        func enter(_ username: String, home: UUID, as owner: String = "ana") async throws {
            try await backend.signOut()
            _ = try await backend.signIn(username: Username(owner), password: password)
            let invite = try await backend.createInvite(for: home)
            try await backend.signOut()
            _ = try await backend.signIn(username: Username(username), password: password)
            _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        }
        func rejected(_ message: String, _ call: () async throws -> Void) async {
            do {
                try await call()
                XCTFail(message)
            } catch {}
        }

        for name in ["bruno", "carla", "ana"] {
            _ = try await backend.signUp(username: Username(name), password: password, displayName: nil)
            try await backend.signOut()
        }
        _ = try await backend.signIn(username: Username("ana"), password: password)
        let home = try await backend.createHousehold(name: "Casa de prueba").id
        try await note("Ana", in: home)

        // Bruno entra, apunta y sale por su cuenta: se borra todo lo suyo.
        try await enter("bruno", home: home)
        try await note("Bruno", in: home)
        let seeded = try await backend.categories(in: home).count
        try await backend.leave(householdId: home)
        let brunoRemoved = try await backend.removedHouseholds()
        XCTAssertEqual(brunoRemoved, [], "quien sale por su cuenta no queda como quitado")
        try await enter("bruno", home: home)
        let brunoAccounts = try await backend.accounts(in: home)
        let brunoMovements = try await backend.allMovements(in: home)
        let brunoCategories = try await backend.categories(in: home).count
        XCTAssertEqual(brunoAccounts, [], "al salir se borraron sus cuentas")
        XCTAssertEqual(brunoMovements, [], "y sus movimientos")
        XCTAssertEqual(brunoCategories, seeded, "al volver empieza con las categorías de partida")

        // Carla entra y apunta; Ana la quita: sus datos siguen 30 días y sólo ella puede exportarlos.
        try await enter("carla", home: home)
        try await note("Carla", in: home)
        let carla = try await backend.myProfile().id
        try await backend.signOut()
        _ = try await backend.signIn(username: Username("ana"), password: password)
        try await backend.removeMember(carla, from: home)
        await rejected("la dueña no exporta los datos de quien ha quitado") { _ = try await backend.removedHouseholdExport(home) }
        let anaAccounts = try await backend.accounts(in: home)
        XCTAssertEqual(anaAccounts.map(\.name), ["Cuenta de Ana"], "lo de Ana no se toca")
        try await backend.signOut()

        _ = try await backend.signIn(username: Username("carla"), password: password)
        let households = try await backend.households()
        XCTAssertEqual(households, [], "Carla ya no está en el hogar")
        let removed = try await backend.removedHouseholds()
        XCTAssertEqual(removed, [RemovedHousehold(householdId: home, name: "Casa de prueba",
                                                  exportUntil: clock.date.addingTimeInterval(30 * 86_400))])
        let export = try await backend.removedHouseholdExport(home)
        XCTAssertEqual(export.accounts.map(\.name), ["Cuenta de Carla"])
        XCTAssertEqual(export.movements.map(\.description), ["Compra de Carla"])
        XCTAssertEqual(export.categories.count, seeded)

        // Vuelve a entrar dentro del plazo: recupera lo suyo y no queda nada que purgar.
        try await enter("carla", home: home)
        let back = try await backend.accounts(in: home)
        let backRemoved = try await backend.removedHouseholds()
        let backCategories = try await backend.categories(in: home).count
        XCTAssertEqual(back.map(\.name), ["Cuenta de Carla"])
        XCTAssertEqual(backRemoved, [])
        XCTAssertEqual(backCategories, seeded, "sin categorías repetidas")

        // Ana la quita otra vez y pasan los 30 días: ya no se puede exportar y los datos se borran.
        try await backend.signOut()
        _ = try await backend.signIn(username: Username("ana"), password: password)
        try await backend.removeMember(carla, from: home)
        clock.date.addTimeInterval(30 * 86_400)
        try await backend.signOut()
        _ = try await backend.signIn(username: Username("carla"), password: password)
        let late = try await backend.removedHouseholds()
        XCTAssertEqual(late, [])
        await rejected("fuera de plazo no se exporta") { _ = try await backend.removedHouseholdExport(home) }
        try await enter("carla", home: home)
        let afterPurge = try await backend.accounts(in: home)
        XCTAssertEqual(afterPurge, [], "pasado el plazo se borró todo lo suyo")
    }

    /// Lo mismo que `supabase/tests/database/11_privacidad.test.sql`: cada miembro ve y toca solo lo suyo.
    /// Datos inventados.
    func testBrunoNoVeLasCuentasDeAna() async throws {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"
        let november = CalendarDay(year: 2026, month: 11, day: 2)!
        func rejected(_ message: String, _ call: () async throws -> Void) async {
            do {
                try await call()
                XCTFail(message)
            } catch {}
        }

        // Ana crea el hogar, apunta sus cosas e invita a Bruno.
        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: "Ana")
        let home = try await backend.createHousehold(name: "Casa de prueba").id
        let anaAccount = try await backend.createAccount(AccountDraft(name: "Cuenta de Ana"), in: home)
        let anaSavings = try await backend.createAccount(AccountDraft(name: "Ahorro de Ana"), in: home)
        let anaMovement = try await backend.addMovement(MovementDraft(accountId: anaAccount.id, bookedOn: november,
                                                                      amount: Money(minor: -4500), description: "Compra de Ana"), in: home)
        let anaTransfer = TransferDraft(fromAccountId: anaAccount.id, toAccountId: anaSavings.id, bookedOn: november,
                                        amount: Money(minor: 1000), fromDescription: "A ahorro", toDescription: "Desde la cuenta")
        _ = try await backend.addTransfer(anaTransfer, in: home)
        let anaCategories = try await backend.categories(in: home)
        let anaCategory = try XCTUnwrap(anaCategories.first { $0.name == "Supermercado" })
        _ = try await backend.saveBudget(Budget(householdId: home, month: MonthKey(year: 2026, month: 11),
                                                expectedIncome: Money(minor: 200_000)))
        let anaHolding = try await backend.createHolding(Holding(householdId: home, name: "Fondo de Ana", price: 10))
        let anaTrade = try await backend.addTrade(InvestmentTrade(householdId: home, holdingId: anaHolding.id, tradedOn: november,
                                                                  quantity: 1, price: 10), cash: nil)
        let anaGoal = try await backend.createGoal(Goal(householdId: home, name: "Viaje", target: Money(minor: 100_000)))
        _ = try await backend.createRecurring(RecurringSeries(householdId: home, name: "Música", amount: Money(minor: 999),
                                                              startsOn: november))
        _ = try await backend.saveExtraBudget(ExtraBudget(householdId: home, name: "Vacaciones", limit: Money(minor: 80_000),
                                                          startsOn: november, endsOn: november))
        let invite = try await backend.createInvite(for: home)
        try await backend.signOut()

        // Bruno ---------------------------------------------------------------------------
        _ = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        let accounts = try await backend.accounts(in: home)
        XCTAssertEqual(accounts.count, 0, "Bruno no ve las cuentas de Ana")
        let movements = try await backend.allMovements(in: home)
        XCTAssertEqual(movements.count, 0, "ni sus movimientos")
        let budget = try await backend.budget(startingOn: CalendarDay(year: 2026, month: 11, day: 1)!, in: home)
        XCTAssertNil(budget, "ni su presupuesto")
        let categories = try await backend.categories(in: home)
        XCTAssertEqual(categories.count, 20, "Bruno tiene sus propias categorías de partida")
        XCTAssertFalse(categories.contains { $0.id == anaCategory.id }, "y no ve las de Ana")
        let holdings = try await backend.holdings(in: home)
        let trades = try await backend.trades(in: home)
        let goals = try await backend.goals(in: home)
        let series = try await backend.recurringSeries(in: home)
        let extras = try await backend.extraBudgets(in: home)
        XCTAssertTrue(holdings.isEmpty && trades.isEmpty && goals.isEmpty && series.isEmpty && extras.isEmpty,
                      "ni sus inversiones, metas, pagos fijos o presupuestos extra")

        await rejected("Bruno no apunta en la cuenta de Ana") {
            _ = try await backend.addMovement(MovementDraft(accountId: anaAccount.id, bookedOn: november,
                                                            amount: Money(minor: -100), description: "Truco"), in: home)
        }
        let brunoAccount = try await backend.createAccount(AccountDraft(name: "Cuenta de Bruno"), in: home)
        let brunoSavings = try await backend.createAccount(AccountDraft(name: "Ahorro de Bruno"), in: home)
        await rejected("ni usa una categoría de Ana") {
            _ = try await backend.addMovement(MovementDraft(accountId: brunoAccount.id, categoryId: anaCategory.id, bookedOn: november,
                                                            amount: Money(minor: -100), description: "Con categoría ajena"), in: home)
        }
        await rejected("ni aporta a una meta de Ana") {
            _ = try await backend.addContribution(GoalContribution(householdId: home, goalId: anaGoal.id,
                                                                   amount: Money(minor: 100), madeOn: november))
        }
        _ = try await backend.addMovement(MovementDraft(accountId: brunoAccount.id, bookedOn: november,
                                                        amount: Money(minor: -2000), description: "Compra de Bruno"), in: home)

        // Un id de Ana no sirve para guardar lo de Bruno (como el 23505 del servidor) ni para cambiarlo.
        do {
            _ = try await backend.addMovement(MovementDraft(id: anaMovement.id, accountId: brunoAccount.id, bookedOn: november,
                                                            amount: Money(minor: -4500), description: "Mismo id"), in: home)
            XCTFail("un movimiento con el id de Ana no se guarda")
        } catch {
            XCTAssertEqual(error as? AppError, .idUsedBySomeoneElse)
        }
        do {
            var reused = anaTransfer
            reused.fromAccountId = brunoAccount.id
            reused.toAccountId = brunoSavings.id
            _ = try await backend.addTransfer(reused, in: home)
            XCTFail("una transferencia con el id de Ana no se guarda")
        } catch {
            XCTAssertEqual(error as? AppError, .idUsedBySomeoneElse)
        }
        let brunoHolding = try await backend.createHolding(Holding(householdId: home, name: "Fondo de Bruno", price: 10))
        do {
            _ = try await backend.addTrade(InvestmentTrade(id: anaTrade.id, householdId: home, holdingId: brunoHolding.id,
                                                           tradedOn: november, quantity: 1, price: 10), cash: nil)
            XCTFail("una operación con el id de Ana no se guarda")
        } catch {
            XCTAssertEqual(error as? AppError, .idUsedBySomeoneElse)
        }
        do {
            var changed = anaMovement
            changed.description = "Cambiado por Bruno"
            _ = try await backend.updateMovement(changed)
            XCTFail("Bruno no cambia un movimiento de Ana")
        } catch {
            XCTAssertEqual(error as? AppError, .movementChanged)
        }

        _ = try await backend.saveBudget(Budget(householdId: home, month: MonthKey(year: 2026, month: 11),
                                                expectedIncome: Money(minor: 150_000)))
        let own = try await backend.budget(startingOn: CalendarDay(year: 2026, month: 11, day: 1)!, in: home)
        XCTAssertEqual(own?.expectedIncome, Money(minor: 150_000), "Bruno guarda su presupuesto del mismo mes y solo ve el suyo")
        try await backend.deleteAccount(anaAccount.id)
        try await backend.deleteGoal(anaGoal.id)
        try await backend.deleteHolding(anaHolding.id)
        try await backend.deleteAccount(brunoAccount.id)
        let left = try await backend.accounts(in: home)
        XCTAssertEqual(left.map(\.id), [brunoSavings.id], "Bruno solo puede borrar su cuenta")
        try await backend.resetHousehold(home)
        try await backend.signOut()

        // Carla, de otro hogar, no ve nada del de Ana.
        _ = try await backend.signUp(username: Username("carla"), password: password, displayName: nil)
        await rejected("quien no es del hogar no ve sus cuentas") { _ = try await backend.accounts(in: home) }
        try await backend.signOut()

        // Ana -------------------------------------------------------------------------------
        _ = try await backend.signIn(username: Username("ana"), password: password)
        let anaAccounts = try await backend.accounts(in: home)
        XCTAssertEqual(Set(anaAccounts.map(\.id)), [anaAccount.id, anaSavings.id], "Ana sigue con sus cuentas")
        let anaMovements = try await backend.movements(in: home, accountId: anaAccount.id, limit: 50)
        XCTAssertEqual(anaMovements.map(\.description).sorted(), ["A ahorro", "Compra de Ana"], "y ve solo sus movimientos")
        let anaBudget = try await backend.budget(startingOn: CalendarDay(year: 2026, month: 11, day: 1)!, in: home)
        XCTAssertEqual(anaBudget?.expectedIncome, Money(minor: 200_000), "y su presupuesto no ha cambiado")
        let anaCategoriesAfter = try await backend.categories(in: home)
        XCTAssertTrue(anaCategoriesAfter.contains { $0.id == anaCategory.id }, "el borrado de Bruno no toca las categorías de Ana")
        let anaGoals = try await backend.goals(in: home)
        let anaHoldings = try await backend.holdings(in: home)
        let anaTrades = try await backend.trades(in: home)
        XCTAssertEqual(anaGoals.map(\.id), [anaGoal.id], "ni sus metas")
        XCTAssertEqual(anaHoldings.map(\.id), [anaHolding.id], "ni sus inversiones")
        XCTAssertEqual(anaTrades.map(\.id), [anaTrade.id])
        let anaSeries = try await backend.recurringSeries(in: home)
        let anaExtras = try await backend.extraBudgets(in: home)
        XCTAssertEqual(anaSeries.count, 1)
        XCTAssertEqual(anaExtras.count, 1)
    }

    func testExpiredInviteAndWrongPassword() async throws {
        let clock = Clock()
        let backend = InMemoryBackend(now: { clock.now })
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-1", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa")
        let invite = try await backend.createInvite(for: home.id)
        clock.now = clock.now.addingTimeInterval(49 * 3600)
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("bruno"), password: "contrasena-2", displayName: nil)
        do {
            _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
            XCTFail("un código caducado no debe valer")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidOrExpiredInvite)
        }

        try await backend.signOut()
        do {
            _ = try await backend.signIn(username: Username("ana"), password: "mal")
            XCTFail("contraseña incorrecta")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidCredentials)
        }
    }

    func testDecodesServerRows() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000000a","username":"ana","display_name":null,
         "theme":"dark","default_household_id":null,"created_at":"2026-10-27T10:00:00+00:00"}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.theme, .dark)
        XCTAssertEqual(profile.name, "ana")
    }
}

/// Reloj que la prueba puede adelantar.
private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
