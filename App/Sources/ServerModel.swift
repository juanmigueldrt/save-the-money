import Foundation
import STMCore
import STMData

/// Lo que comparten los modelos de la app al hablar con el servidor: el error en español para la pantalla,
/// qué pasa si la tarea se cancela y qué respuesta gana cuando dos lecturas se cruzan.
@MainActor
protocol ServerModel: AnyObject {
    /// El mensaje que enseña la pantalla, o nil.
    var error: String? { get set }
    /// Turnos de las lecturas: ver `store(_:in:turn:)`.
    var turns: ReadTurns { get set }
    /// true mientras hay una carga en curso: ver `beginLoad()`.
    var isLoading: Bool { get set }
}

/// Cada lectura toma un turno al empezar. Lo que trae solo se guarda si nada que empezó después lo ha guardado ya.
struct ReadTurns {
    private var issued = 0
    private var stored: [AnyKeyPath: Int] = [:]
    /// Cargas que todavía no han terminado.
    fileprivate(set) var running = 0

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
    func perform(
        turn: Int? = nil, _ operation: () async throws -> Void, function: String = #function
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        error = nil
        do {
            try await operation()
            if let turn { _ = mayStore(\.error, turn: turn) }
            return true
        } catch {
            Self.record(error, in: function)
            if let message = Self.message(for: error), turn.map({ mayStore(\.error, turn: $0) }) ?? true {
                self.error = message
            }
            return false
        }
    }

    /// Recarga tras una escritura. Nunca falla: lo guardado sigue guardado y, si la recarga falla, `error` lo dice
    /// como problema de carga, que se reintenta cargando y no guardando otra vez (como `reloadAfterSave` en Android).
    /// Si la escritura ya había fallado, su error va primero: por él el formulario sigue abierto.
    func reloadAfterSave(_ reload: () async throws -> Void, function: String = #function) async {
        do {
            try await reload()
        } catch {
            Self.record(error, in: function)
            guard let message = Self.message(for: error) else { return }
            if let saveError = self.error, saveError != message {
                self.error = saveError + " Además, no se han podido volver a cargar los datos: " + message
            } else {
                self.error = message
            }
        }
    }

    /// Una escritura y la recarga de lo que cambia. Si la escritura falla se recarga igual: puede que otro dispositivo
    /// cambiara la fila antes (STM05) o que ya estuviera guardada con otros datos (STM01); así se ve lo que hay
    /// detrás del aviso. Devuelve si se guardó.
    @discardableResult
    func write(
        _ operation: () async throws -> Void, thenReload reload: () async throws -> Void, function: String = #function
    ) async -> Bool {
        let saved = await perform(operation, function: function)
        await reloadAfterSave(reload, function: function)
        return saved
    }

    /// El turno de una lectura que empieza.
    func nextTurn() -> Int { turns.next() }

    /// Marca una carga en curso. `isLoading` sigue en true hasta que termina la última que se solapa con las demás.
    func beginLoad() {
        turns.running += 1
        isLoading = true
    }

    /// Cierra la carga que empezó con `beginLoad()`.
    func endLoad() {
        turns.running -= 1
        isLoading = turns.running > 0
    }

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

    /// Registra un fallo que no viene del servidor (ORC-72). Los del servidor ya los registra `mapped` en STMData,
    /// antes de convertirlos en `AppError`; las cancelaciones no son fallos.
    static func record(_ error: any Error, in function: String) {
        guard !(error is AppError), message(for: error) != nil else { return }
        ErrorLog.record(error, in: function)
    }

    /// El texto para la pantalla, o nil si la tarea se ha cancelado: eso no es un fallo que enseñar.
    static func message(for error: any Error) -> String? {
        if Task.isCancelled || error is CancellationError { return nil }
        return (error as? AppError)?.errorDescription ?? AppError.unknown("").errorDescription
    }
}
