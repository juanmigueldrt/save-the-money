import Foundation

/// Diagrama de Sankey del flujo de caja de un mes:
/// ingresos → Necesidades / Deseos / Ahorro (y lo que queda sin gastar) → categorías.
public struct CashFlow: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case income, fromBalance, group(BudgetGroup), uncategorized, unspent, category(BudgetGroup?)
    }

    public struct Node: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var column: Int
        /// Céntimos, siempre positivo.
        public var value: Double
        public var role: Role
    }

    public struct Link: Hashable, Sendable {
        public var from: String
        public var to: String
        public var value: Double
    }

    public var nodes: [Node]
    public var links: [Link]

    public var isEmpty: Bool { nodes.isEmpty }

    public init(nodes: [Node], links: [Link]) {
        self.nodes = nodes
        self.links = links
    }

    public init(report: BudgetReport) {
        var nodes: [Node] = []
        var links: [Link] = []

        // Columna 2: categorías con gasto, colgando de su grupo.
        var middle: [Node] = []
        for progress in report.groups where progress.spent.minor > 0 {
            let groupId = "grupo:\(progress.group.rawValue)"
            middle.append(Node(id: groupId, title: progress.group.title, column: 1,
                               value: Double(progress.spent.minor), role: .group(progress.group)))
            for line in report.lines(in: progress.group) where line.spent.minor > 0 {
                let id = "categoria:\(line.category.id.uuidString)"
                nodes.append(Node(id: id, title: line.category.name, column: 2,
                                  value: Double(line.spent.minor), role: .category(progress.group)))
                links.append(Link(from: groupId, to: id, value: Double(line.spent.minor)))
            }
        }
        if report.uncategorized.minor > 0 {
            middle.append(Node(id: "sin-categoria", title: "Sin categoría", column: 1,
                               value: Double(report.uncategorized.minor), role: .uncategorized))
        }
        let spent = middle.reduce(0) { $0 + $1.value }
        let income = report.incomeSources.reduce(0) { $0 + Double($1.amount.minor) }
        if income > spent {
            middle.append(Node(id: "sin-gastar", title: "Sin gastar", column: 1, value: income - spent, role: .unspent))
        }

        // Columna 0: ingresos y, si se gastó más de lo que entró, lo que salió del saldo.
        var sources = report.incomeSources.enumerated().map { index, source in
            Node(id: "ingreso:\(index)", title: source.title, column: 0, value: Double(source.amount.minor), role: .income)
        }
        if spent > income {
            sources.append(Node(id: "del-saldo", title: "Del saldo", column: 0, value: spent - income, role: .fromBalance))
        }

        // Cada fuente reparte su importe entre los grupos en proporción a lo que se llevan.
        let total = sources.reduce(0) { $0 + $1.value }
        if total > 0 {
            for source in sources {
                for target in middle {
                    links.append(Link(from: source.id, to: target.id, value: source.value * target.value / total))
                }
            }
        }

        self.nodes = sources + middle + nodes
        self.links = links
    }
}

/// Posiciones del diagrama para un tamaño dado. Se calcula aquí, sin SwiftUI, para poder probarlo.
public struct SankeyLayout: Hashable, Sendable {
    public struct Rect: Hashable, Sendable {
        public var x, y, width, height: Double
        public var midY: Double { y + height / 2 }
    }

    /// Banda de un enlace: de un tramo del borde derecho del origen a un tramo del borde izquierdo del destino.
    public struct Band: Hashable, Sendable {
        public var from: String
        public var to: String
        public var sourceX: Double
        public var sourceTop: Double
        public var targetX: Double
        public var targetTop: Double
        public var thickness: Double
    }

    public var nodes: [String: Rect]
    public var bands: [Band]

    public init(flow: CashFlow, width: Double, height: Double, nodeWidth: Double = 10, gap: Double = 12) {
        let columns = Dictionary(grouping: flow.nodes, by: \.column)
        let columnCount = (columns.keys.max() ?? 0) + 1
        // Misma escala en todas las columnas para que los grosores sean comparables.
        let scale = columns.values.map { column -> Double in
            let total = column.reduce(0) { $0 + $1.value }
            let free = height - gap * Double(max(column.count - 1, 0))
            return total > 0 ? max(free, 1) / total : .infinity
        }.min() ?? 0
        let step = columnCount > 1 ? (width - nodeWidth) / Double(columnCount - 1) : 0

        var rects: [String: Rect] = [:]
        for (index, column) in columns {
            let used = column.reduce(0) { $0 + $1.value * scale } + gap * Double(max(column.count - 1, 0))
            var y = max(0, (height - used) / 2)
            for node in column {
                let h = node.value * scale
                rects[node.id] = Rect(x: Double(index) * step, y: y, width: nodeWidth, height: h)
                y += h + gap
            }
        }

        var outOffset: [String: Double] = [:]
        var inOffset: [String: Double] = [:]
        var bands: [Band] = []
        for link in flow.links where link.value > 0 {
            guard let source = rects[link.from], let target = rects[link.to] else { continue }
            let thickness = link.value * scale
            let sourceTop = source.y + outOffset[link.from, default: 0]
            let targetTop = target.y + inOffset[link.to, default: 0]
            outOffset[link.from, default: 0] += thickness
            inOffset[link.to, default: 0] += thickness
            bands.append(Band(from: link.from, to: link.to, sourceX: source.x + source.width, sourceTop: sourceTop,
                              targetX: target.x, targetTop: targetTop, thickness: thickness))
        }

        nodes = rects
        self.bands = bands
    }
}
