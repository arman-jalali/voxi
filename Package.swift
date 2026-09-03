// swift-tools-version: 5.10
// Voxi: SwiftPM build of the app executable (no Xcode required — builds with
// Command Line Tools). scripts/build-app.sh assembles the .app bundle around
// the produced binary.

import PackageDescription

let package = Package(
    name: "Voxi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Voxi", targets: ["Voxi"])
    ],
    dependencies: [
        .package(path: "JotCore")
    ],
    targets: [
        .executableTarget(
            name: "Voxi",
            dependencies: [
                .product(name: "JotCore", package: "JotCore")
            ],
            path: "App/Sources"
        )
    ]
)
