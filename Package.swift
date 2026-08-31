// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Metron",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Metron",
            path: "Sources/Metron",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MetronTests",
            dependencies: ["Metron"],
            path: "Tests/MetronTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
