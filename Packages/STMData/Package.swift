// swift-tools-version: 5.10
import PackageDescription

// Acceso a Supabase: implementa los servicios de STMCore con supabase-swift.
// La sesión la guarda supabase-swift en el Llavero del sistema.
let package = Package(
    name: "STMData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "STMData", targets: ["STMData"]),
    ],
    dependencies: [
        .package(path: "../STMCore"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.5.0"),
    ],
    targets: [
        .target(name: "STMData", dependencies: [
            "STMCore",
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
    ]
)
