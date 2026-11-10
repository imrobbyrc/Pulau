// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulau",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pulau", resources: [.copy("Resources/ProviderIcons"), .copy("Resources/SettingsIcons")]),
        .testTarget(name: "PulauTests", dependencies: ["Pulau"]),
    ]
)
