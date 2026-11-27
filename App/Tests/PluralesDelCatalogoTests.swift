import XCTest
@testable import SaveTheMoney

/// ORC-110: los singulares que antes elegía el código (`count == 1 ? … : …`) ahora son variantes de plural del
/// catálogo. Los literales se copiaron del código de antes: si alguno cambia, el usuario vería otra cosa.
final class PluralesDelCatalogoTests: XCTestCase {
    func testElCatalogoEligeSingularYPlural() {
        func pin(_ text: (Int) -> String, _ one: String, _ two: String, line: UInt = #line) {
            XCTAssertEqual(text(1), one, line: line)
            XCTAssertEqual(text(2), two, line: line)
        }
        pin({ String(localized: " \($0) pagos recurrentes creados.") }, " 1 pago recurrente creado.", " 2 pagos recurrentes creados.")
        pin({ String(localized: "\($0) días") }, "1 día", "2 días")
        pin({ String(localized: "\($0) días antes") }, "1 día antes", "2 días antes")
        pin({ String(localized: "\($0) planes activos") }, "1 plan activo", "2 planes activos")
        pin({ String(localized: "\($0) seleccionados") }, "1 seleccionado", "2 seleccionados")
        pin({ String(localized: "Durante \($0) cargos") }, "Durante 1 cargo", "Durante 2 cargos")
        pin({ String(localized: "Editar \($0) movimientos") }, "Editar 1 movimiento", "Editar 2 movimientos")
        pin({ String(localized: "Hay \($0) movimientos con el mismo concepto") },
            "Hay 1 movimiento con el mismo concepto", "Hay 2 movimientos con el mismo concepto")
        pin({ String(localized: "¿Borrar \($0) movimientos?") }, "¿Borrar 1 movimiento?", "¿Borrar 2 movimientos?")
        pin({ String(localized: "Sin compras nuevas, terminarías de pagar en \($0) meses y pagarías \("3,00 €") de intereses. Pagando todo a fin de mes no pagarías ninguno.") },
            "Sin compras nuevas, terminarías de pagar en 1 mes y pagarías 3,00 € de intereses. Pagando todo a fin de mes no pagarías ninguno.",
            "Sin compras nuevas, terminarías de pagar en 2 meses y pagarías 3,00 € de intereses. Pagando todo a fin de mes no pagarías ninguno.")
        pin(CardText.uncategorizedCredits,
            "Hay 1 abono sin categoría. Sin categoría no bajan los cargos: si es una devolución, ponle la suya; si es un pago de la tarjeta, una de transferencia.",
            "Hay 2 abonos sin categoría. Sin categoría no bajan los cargos: si es una devolución, ponle la suya; si es un pago de la tarjeta, una de transferencia.")
        pin(CardText.unresolvedInstallments,
            "No se ha podido cargar la compra de 1 aplazado. Hasta que se carguen, los cargos y la deuda de la tarjeta no son de fiar: vuelve a abrirla en un rato.",
            "No se han podido cargar las compras de 2 aplazados. Hasta que se carguen, los cargos y la deuda de la tarjeta no son de fiar: vuelve a abrirla en un rato.")
    }
}
