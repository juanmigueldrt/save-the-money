import XCTest
import STMCore
@testable import STMData

/// ORC-104: las inserciones que no van por una función del servidor mandan exactamente estas columnas, aunque los
/// modelos ya se codifiquen enteros. Sin id (lo pone el servidor), sin estado y con los textos limpios. Datos inventados.
final class FilasDeInsercionTests: XCTestCase {
    private func sent(_ value: some Encodable) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
    }

    func testElCargoNuevoLlevaSoloHogarSerieDiaEImporte() throws {
        let home = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000f1"))
        let series = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000a1"))
        let charge = RecurringCharge(householdId: home, seriesId: series, dueOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5)),
                                     amount: Money(minor: -1_199), status: .confirmed, transactionId: UUID(),
                                     updatedAt: "2026-11-01T10:00:00.123456+00:00")
        let expected: NSDictionary = ["household_id": "00000000-0000-0000-0000-0000000000F1",
                                      "series_id": "00000000-0000-0000-0000-0000000000A1",
                                      "due_on": "2026-11-05", "amount_minor": -1_199]
        XCTAssertEqual(try sent(NewChargeRow(charge: charge)), expected)
    }

    func testElScoreNuevoLlevaLasColumnasEditablesConTextosLimpios() throws {
        let day = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 1))
        let full = CreditScore(score: 720, maxScore: 850, provider: "  Buró  ", recordedOn: day, note: " revisado ")
        let fullExpected: NSDictionary = ["score": 720, "max_score": 850, "provider": "Buró",
                                          "recorded_on": "2026-11-01", "note": "revisado"]
        XCTAssertEqual(try sent(NewCreditScoreRow(score: full)), fullExpected)

        // Los vacíos van como null explícito, no se omiten.
        let empty = CreditScore(score: 500, maxScore: 1000, provider: "   ", recordedOn: day, note: "  ")
        let emptyExpected: NSDictionary = ["score": 500, "max_score": 1000, "provider": NSNull(),
                                           "recorded_on": "2026-11-01", "note": NSNull()]
        XCTAssertEqual(try sent(NewCreditScoreRow(score: empty)), emptyExpected)
        XCTAssertEqual(try sent(NewCreditScoreRow(score: CreditScore(score: 500, recordedOn: day))),
                       ["score": 500, "max_score": 850, "provider": NSNull(), "recorded_on": "2026-11-01", "note": NSNull()])
    }
}
