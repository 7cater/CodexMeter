// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexMeter", targets: ["CodexMeter"])],
    targets: [
        .target(name: "CodexMeterCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodexMeter", dependencies: ["CodexMeterCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["CodexMeterCore"], path: "Tests/CodexMeterCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
