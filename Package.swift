// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hmectl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "hmectl", targets: ["hmectl"])
    ],
    targets: [
        .target(name: "HMECore"),
        .executableTarget(name: "hmectl", dependencies: ["HMECore"]),
        .testTarget(name: "HMECoreTests", dependencies: ["HMECore"]),
    ]
)
