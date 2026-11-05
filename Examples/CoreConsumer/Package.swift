// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoreConsumer", platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../Packages/PeerCore")],
    targets: [
        .executableTarget(
            name: "CoreConsumer",
            dependencies: [.product(name: "PeerCore", package: "PeerCore")])
    ])
