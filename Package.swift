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
        )
    ]
)
