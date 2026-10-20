// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Orby",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Orby", targets: ["Orby"]),
        .executable(name: "orby-bridge", targets: ["orby-bridge"]),
    ],
    targets: [
        // Wire protocol + process helpers shared by the app and the hook bridge.
        .target(name: "NotchShared"),
        // UI-free logic: session engine, hook installer, socket server, parsers.
        .target(name: "NotchCore", dependencies: ["NotchShared"]),
        .executableTarget(name: "orby-bridge", dependencies: ["NotchShared"]),
        .executableTarget(
            name: "Orby",
            dependencies: ["NotchCore", "NotchShared"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore", "NotchShared"]),
    ],
    swiftLanguageModes: [.v5]
)
