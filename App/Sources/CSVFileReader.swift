import SwiftUI
import UniformTypeIdentifiers
import STMCore
import STMUI

/// Lo que se saca de un archivo CSV, listo para la pantalla.
struct CSVLoadedFile: Sendable {
    let fileName: String
    let text: String
    let table: CSVTable
    let mapping: CSVMapping?
    /// true si las columnas salen de un formato de banco ya usado.
    let usedSavedFormat: Bool
    /// Cuenta que guardaba el formato, si lo hay.
    let savedAccount: UUID?
}

/// Por qué no se puede abrir el archivo. El mensaje es el que ve el usuario.
enum CSVOpenFailure: Error, Sendable {
    case tooLarge
    case unreadableText
    case cannotOpen

    var message: String {
        switch self {
        case .tooLarge: String(localized: "El archivo es demasiado grande (máximo 10 MB).")
        case .unreadableText: String(localized: "No he podido leer el texto del archivo.")
        case .cannotOpen: String(localized: "No he podido abrir el archivo.")
        }
    }
}

/// Lectura y primer análisis del archivo elegido. No toca la pantalla: puede correr fuera del hilo principal.
enum CSVFileReader {
    /// Tamaño máximo del archivo: un extracto de varios años cabe de sobra.
    static let maxBytes = 10 * 1024 * 1024

    static func read(_ url: URL, savedFormats: [CSVSavedFormat]) throws -> CSVLoadedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw CSVOpenFailure.cannotOpen
        }
        if let size, size > maxBytes { throw CSVOpenFailure.tooLarge }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CSVOpenFailure.cannotOpen
        }
        try Task.checkCancellation()
        guard let text = CSVTable.decode(data) else { throw CSVOpenFailure.unreadableText }
        try Task.checkCancellation()
        let saved = CSVSavedFormat.match(text: text, in: savedFormats)
        let table = saved?.table ?? CSVTable.parse(text)
        if let saved, let known = saved.format.mapping {
            return CSVLoadedFile(fileName: url.lastPathComponent, text: text, table: table, mapping: known,
                                 usedSavedFormat: true, savedAccount: saved.format.accountId)
        }
        return CSVLoadedFile(fileName: url.lastPathComponent, text: text, table: table,
                             mapping: CSVMapping.detect(in: table), usedSavedFormat: false, savedAccount: nil)
    }
}

/// Formatos de banco recordados en este dispositivo (sólo columnas, nunca datos del archivo).
enum SavedCSVFormats {
    private static let key = "stm.csv.formats"

    static func load() -> [CSVSavedFormat] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CSVSavedFormat].self, from: data)) ?? []
    }

    static func remember(_ format: CSVSavedFormat) {
        let list = CSVSavedFormat.remember(format, in: load())
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}
