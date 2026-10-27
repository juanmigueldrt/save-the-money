// swift-tools-version: 5.10
import PackageDescription

// Colores, tipografías, espaciados y componentes de Save the Money,
// sacados de las variables y estilos de texto del archivo de diseño.
let package = Package(
    name: "STMUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "STMUI", targets: ["STMUI"]),
    ],
    dependencies: [
        .package(path: "../STMCore"),
    ],
    targets: [
        .target(name: "STMUI", dependencies: ["STMCore"]),
    ]
)
