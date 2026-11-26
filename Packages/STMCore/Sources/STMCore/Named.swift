import Foundation

/// Elemento con nombre: `trimmedName` es el nombre sin espacios sobrantes, como se guarda y se muestra.
public protocol Named {
    var name: String { get }
}

extension Named {
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Elemento que se puede archivar: deja de contar sin borrarse.
public protocol Archivable {
    var archivedAt: Date? { get }
}

extension Archivable {
    public var isArchived: Bool { archivedAt != nil }
}
