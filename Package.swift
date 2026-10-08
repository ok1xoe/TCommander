// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TCommander",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TCommander", targets: ["TCApp"]),
        .library(name: "TCCore", targets: ["TCCore"]),
    ],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "CCurl", linkerSettings: [.linkedLibrary("curl")]),
        .target(name: "TCCore", dependencies: ["CArchive", "CCurl"]),
        .executableTarget(
            name: "TCApp",
            dependencies: ["TCCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // generátor webu a příručky (docs/manual → site/); spouští se skriptem scripts/build_site.sh
        .executableTarget(name: "DocsBuilder", dependencies: ["TCCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "TCCoreTests", dependencies: ["TCCore"]),
    ]
)
