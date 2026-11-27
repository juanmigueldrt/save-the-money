// swift-tools-version: 5.10
import PackageDescription

// Lógica de dominio de Save the Money. No depende de SwiftUI ni de Supabase,
// así que sus pruebas corren en Linux (CI) y en el Mac sin simulador.

// El catálogo de textos (ORC-110) solo existe en Apple: en Linux se queda fuera y vale el literal en español.
#if canImport(Darwin)
let language: LanguageTag? = "es"
let core = Target.target(name: "STMCore", resources: [.process("Localizable.xcstrings")])
#else
let language: LanguageTag? = nil
let core = Target.target(name: "STMCore", exclude: ["Localizable.xcstrings"])
#endif

let package = Package(
    name: "STMCore",
    defaultLocalization: language,
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "STMCore", targets: ["STMCore"]),
    ],
    targets: [
        core,
        .testTarget(name: "STMCoreTests", dependencies: ["STMCore"]),
    ]
)
