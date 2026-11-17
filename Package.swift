// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Orbit", targets: ["Orbit"])],
    targets: [.executableTarget(name: "Orbit")],
    swiftLanguageModes: [.v5]
)
