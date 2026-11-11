// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BMAPKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BMAPKit", targets: ["BMAPKit"]),
    ],
    targets: [
        // Protocol logic + Bluetooth transport. No UI.
        .target(name: "BMAPKit"),
        // Small command line tool to test against real hardware.
        .executableTarget(name: "bosebar-cli", dependencies: ["BMAPKit"]),
        .testTarget(name: "BMAPKitTests", dependencies: ["BMAPKit"]),
    ]
)
