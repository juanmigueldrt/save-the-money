import SwiftUI
import STMCore
import STMUI

/// Secciones de la app. En iPhone son pestañas; en Mac, la barra lateral.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case summary, budget, cashFlow, subscriptions, goals, household, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Resumen"
        case .budget: "Presupuesto"
        case .cashFlow: "Flujo"
        case .subscriptions: "Suscripciones"
        case .goals: "Metas"
        case .household: "Hogar"
        case .more: "Más opciones"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "house"
        case .budget: "chart.pie"
        case .cashFlow: "arrow.left.arrow.right"
        case .subscriptions: "repeat"
        case .goals: "flag"
        case .household: "person.2"
        case .more: "ellipsis.circle"
        }
    }

    /// Pestañas del iPhone: suscripciones y hogar se abren desde Más opciones.
    static let phoneTabs: [AppSection] = [.summary, .budget, .cashFlow, .goals, .more]
}

struct RootView: View {
    @State private var selection: AppSection? = .summary

    var body: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ForEach(AppSection.phoneTabs) { section in
                NavigationStack {
                    SectionPlaceholder(section: section)
                }
                .tabItem { Label(section == .more ? "Más" : section.title, systemImage: section.systemImage) }
                .tag(Optional(section))
            }
        }
        .tint(Palette.ember)
        #else
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            SectionPlaceholder(section: selection ?? .summary)
        }
        .tint(Palette.ember)
        #endif
    }
}

/// Pantalla provisional de cada sección hasta que llegue su fase.
struct SectionPlaceholder: View {
    let section: AppSection
    @Environment(\.appConfig) private var config

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                Text(section.title)
                    .font(Typography.title32)
                    .foregroundStyle(Palette.ink)
                if section == .budget {
                    HStack(spacing: Spacing.s16) {
                        ForEach(BudgetGroup.allCases, id: \.self) { group in
                            SemicircleGauge(progress: GroupProgress(group: group, allocated: Money(minor: 100_000), spent: .zero))
                        }
                    }
                    .card()
                }
                Text("Esta pantalla llega en una próxima fase.")
                    .font(Typography.body16)
                    .foregroundStyle(Palette.graphite)
                if config.isMissingSupabaseKey {
                    Text("Falta la clave de Supabase: copia Config/Secrets.example.xcconfig a Config/Secrets.xcconfig.")
                        .font(Typography.small12)
                        .foregroundStyle(Palette.graphite)
                }
            }
            .padding(Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.linen)
    }
}

#Preview {
    RootView()
}
