// swift-tools-version: 5.10
import PackageDescription

// Lógica de dominio de Save the Money. No depende de SwiftUI ni de Supabase,
// así que sus pruebas corren en Linux (CI) y en el Mac sin simulador.
let package = Package(
    name: "STMCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "STMCore", targets: ["STMCore"]),
    ],
    targets: [
        .target(name: "STMCore"),
        .testTarget(name: "STMCoreTests", dependencies: ["STMCore"]),
    ]
)
