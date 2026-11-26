import Foundation
import STMCore

/// Lo que comparten los modelos de la app al hablar con el servidor: el error en español para la pantalla,
/// qué pasa si la tarea se cancela y qué respuesta gana cuando dos lecturas se cruzan.
@MainActor
protocol ServerModel: AnyObject {
    /// El mensaje que enseña la pantalla, o nil.
    var error: String? { get set }
    /// Turnos de las lecturas: ver `store(_:in:turn:)`.
    var turns: ReadTurns { get set }
}

/// Cada lectura toma un turno al empezar. Lo que trae solo se guarda si nada que empezó después lo ha guardado ya.
struct ReadTurns {
    private var issued = 0
    private var stored: [AnyKeyPath: Int] = [:]

    mutating func next() -> Int {
        issued += 1
        return issued
    }

    /// true (y lo apunta) si `turn` no es más antiguo que lo último guardado en `slice`.
    mutating func claim(_ slice: AnyKeyPath, turn: Int) -> Bool {
        guard turn >= stored[slice, default: 0] else { return false }
        stored[slice] = turn
        return true
    }
}

extension ServerModel {
    /// Ejecuta la operación y deja el error en español en `error`. Devuelve si fue bien.
    /// Una tarea cancelada no escribe `error`: la que la sustituye pone el suyo. Con `turn` (una carga), un fallo
    /// no tapa lo que ha dejado una carga que empezó después.
    @discardableResult
    func perform(turn: Int? = nil, _ operation: () async throws -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        error = nil
        do {
            try await operation()
            if let turn { _ = mayStore(\.error, turn: turn) }
            return true
        } catch {
            if let message = Self.message(for: error), turn.map({ mayStore(\.error, turn: $0) }) ?? true {
                self.error = message
            }
            return false
        }
    }

    /// Recarga tras una escritura. Nunca falla: lo guardado sigue guardado y, si la recarga falla, `error` lo dice
    /// como problema de carga, que se reintenta cargando y no guardando otra vez (como `reloadAfterSave` en Android).
    /// Si la escritura ya había fallado, su error va primero: por él el formulario sigue abierto.
    func reloadAfterSave(_ reload: () async throws -> Void) async {
        do {
            try await reload()
        } catch {
            guard let message = Self.message(for: error) else { return }
            if let saveError = self.error, saveError != message {
                self.error = saveError + " Además, no se han podido volver a cargar los datos: " + message
            } else {
                self.error = message
            }
        }
    }

    /// El turno de una lectura que empieza.
    func nextTurn() -> Int { turns.next() }

    /// true si lo que ha traído la lectura del turno `turn` puede guardarse en `slice`: la tarea no se ha cancelado
    /// y ninguna lectura que empezó después ha guardado ahí lo suyo. Una respuesta antigua no pisa una más nueva.
    func mayStore<Value>(_ slice: KeyPath<Self, Value>, turn: Int) -> Bool {
        !Task.isCancelled && turns.claim(slice, turn: turn)
    }

    /// Guarda lo que ha traído una lectura si `mayStore` lo permite.
    func store<Value>(_ value: Value, in slice: ReferenceWritableKeyPath<Self, Value>, turn: Int) {
        guard mayStore(slice, turn: turn) else { return }
        self[keyPath: slice] = value
    }

    /// Un cambio que el servidor ya ha guardado se ve siempre; las lecturas que empezaron antes ya no lo pisan.
    func markChanged<Value>(_ slice: KeyPath<Self, Value>) {
        _ = turns.claim(slice, turn: turns.next())
    }

    /// El texto para la pantalla, o nil si la tarea se ha cancelado: eso no es un fallo que enseñar.
    static func message(for error: any Error) -> String? {
        if Task.isCancelled || error is CancellationError { return nil }
        return (error as? AppError)?.errorDescription ?? AppError.unknown("").errorDescription
    }
}
