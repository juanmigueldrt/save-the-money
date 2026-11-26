import Foundation
import XCTest
@testable import STMCore

/// ORC-106: los atajos de rendimiento no cambian ningún número ni ningún texto.
final class RendimientoTests: XCTestCase {
    /// Lo que hacía `formatted` antes de guardar los formateadores: uno nuevo por importe.
    private func freshText(_ money: Money, locale: Locale, options: MoneyDisplayOptions) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        if money.isMixed { return Money.mixedText }
        formatter.currencyCode = money.currency
        if options.hidesAmounts { return "•••• " + (formatter.currencySymbol ?? money.currency) }
        if options.roundsToUnits {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        }
        let text = formatter.string(from: money.decimal as NSDecimalNumber) ?? "\(money.decimal) \(money.currency)"
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    func testFormateadorGuardadoDaElMismoTextoQueUnoNuevo() {
        let locales = ["es_ES", "en_US", "de_DE", "fr_FR", "ja_JP"].map { Locale(identifier: $0) }
        let currencies = ["EUR", "USD", "GBP", "JPY", "CHF"]
        let options = [
            MoneyDisplayOptions.standard,
            MoneyDisplayOptions(hidesAmounts: true),
            MoneyDisplayOptions(roundsToUnits: true),
            MoneyDisplayOptions(hidesAmounts: true, roundsToUnits: true)
        ]
        let amounts = [0, 1, -1, 50, -50, 99, 150, -150, 123_456, -123_456, 100_000_000_049, -987_654_321]
        // Dos vueltas: la primera crea los formateadores y la segunda los reutiliza.
        for _ in 0..<2 {
            for locale in locales {
                for currency in currencies {
                    for option in options {
                        for minor in amounts {
                            let money = Money(minor: minor, currency: currency)
                            XCTAssertEqual(money.formatted(locale: locale, options: option),
                                           freshText(money, locale: locale, options: option),
                                           "\(minor) \(currency) \(locale.identifier) \(option)")
                            XCTAssertEqual(money.signedText(options: option),
                                           signedReference(money, options: option))
                        }
                    }
                }
            }
        }
        XCTAssertEqual(Money.mixed.formatted(options: .standard), "Varias monedas")
    }

    /// `signedText` (opción «Mostrar +») con el formateador nuevo de antes.
    private func signedReference(_ money: Money, options: MoneyDisplayOptions) -> String {
        let magnitude = freshText(Money(minor: abs(money.minor), currency: money.currency),
                                  locale: Locale(identifier: "es_ES"), options: options)
        if options.hidesAmounts || money.minor == 0 { return magnitude }
        return (money.minor < 0 ? "\u{2212}" : "+") + magnitude
    }

    func testFormateadorGuardadoEsSeguroDesdeVariosHilos() {
        let expected = Money(minor: -123_456, currency: "USD").formatted(options: .standard)
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            let text = Money(minor: -123_456, currency: index.isMultiple(of: 2) ? "USD" : "EUR").formatted(options: .standard)
            if index.isMultiple(of: 2) { XCTAssertEqual(text, expected) }
        }
    }

    /// Lo que hacía `amount(on:)` antes: contar todos los cargos desde el primero.
    private func referenceAmount(_ series: RecurringSeries, on due: CalendarDay) -> Money {
        guard series.hasIntro else { return series.amount }
        return series.amount(forCharge: max(0, series.occurrences(from: series.startsOn, through: due).count - 1))
    }

    func testImporteDeUnCargoEsElMismoSinRecorrerTodaLaSerie() throws {
        let home = UUID()
        let start = try XCTUnwrap(CalendarDay(year: 2024, month: 1, day: 31))
        let recurrences = [Recurrence(every: 1, unit: .week), Recurrence(every: 2, unit: .week),
                           Recurrence(every: 1, unit: .month), Recurrence(every: 3, unit: .month),
                           Recurrence(every: 1, unit: .year)]
        let ends: [CalendarDay?] = [nil, start.adding(days: 20), start.adding(months: 2), start.adding(months: 40)]
        for recurrence in recurrences {
            for endsOn in ends {
                for intro in [1, 3, 12] {
                    let series = RecurringSeries(householdId: home, name: "Serie", amount: Money(minor: 1_299),
                                                 recurrence: recurrence, startsOn: start, endsOn: endsOn,
                                                 introAmount: Money(minor: 699), introCharges: intro)
                    // Todos los días, sean de cargo o no, de antes de empezar a cinco años después.
                    for offset in stride(from: -10, through: 365 * 5, by: 1) {
                        let day = start.adding(days: offset)
                        XCTAssertEqual(series.amount(on: day), referenceAmount(series, on: day),
                                       "\(recurrence) fin \(String(describing: endsOn)) oferta \(intro) día \(day.iso)")
                    }
                }
            }
        }
    }
}
