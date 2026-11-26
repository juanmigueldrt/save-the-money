import Foundation
import os
import STMCore
import Supabase

/// Registro de fallos en el dispositivo (ORC-72): `docs/decisiones/informes-de-fallos.md`. Sólo fallos, nunca lo que va
/// bien, y nada sale del dispositivo.
public enum ErrorLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SaveTheMoney", category: "errores")

    /// Apunta un fallo. Es la única forma en que la app registra errores: la línea la decide `line(operation:error:)`.
    public static func record(_ error: any Error, in operation: String) {
        // Público a propósito: la línea no lleva datos del usuario ni ids, y así se lee en Consola.
        logger.error("\(line(operation: operation, error: error), privacy: .public)")
    }

    /// Lo que va en la línea: la operación (un texto fijo del código), el tipo del error, su código y el estado HTTP.
    /// Nunca el mensaje ni el cuerpo de la respuesta: los del servidor pueden citar importes, nombres o notas de la fila.
    public static func line(operation: String, error: any Error) -> String {
        var type = String(describing: Swift.type(of: error))
        var code: String?
        var status: Int?
        switch error {
        case let error as AppError:
            if case .unknown(let detail) = error { code = detail }
            // La etiqueta del caso, sin su valor: el de `invalidInput` es un mensaje.
            type = "AppError." + (Mirror(reflecting: error).children.first?.label ?? "\(error)")
        case let error as PostgrestError:
            code = error.code
        case let error as AuthError:
            code = error.errorCode.rawValue
            if case .api(_, _, _, let response) = error { status = response.statusCode }
        case let error as HTTPError:
            status = error.response.statusCode
        case let error as URLError:
            type = "URLError" // En Apple llega como NSError.
            code = String(error.code.rawValue)
        default:
            break
        }
        var fields = ["operacion=\(operation)", "tipo=\(type)"]
        if let code { fields.append("codigo=\(safe(code))") }
        if let status { fields.append("http=\(status)") }
        return fields.joined(separator: " ")
    }

    /// Un código es una palabra corta (`23505`, `PGRST301`, `invalid_credentials`, `-1009`). Si el servidor metiera ahí un
    /// texto, no sale nada de él.
    private static func safe(_ code: String) -> String {
        let isWord = code.count <= 40 && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return isWord ? code : "no_valido"
    }
}
