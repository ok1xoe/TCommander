// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macTC",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macTC", targets: ["TCApp"]),
        .library(name: "TCCore", targets: ["TCCore"]),
    ],
    targets: [
        .target(name: "TCCore"),
        .executableTarget(name: "TCApp", dependencies: ["TCCore"]),
        .testTarget(name: "TCCoreTests", dependencies: ["TCCore"]),
    ]
)
