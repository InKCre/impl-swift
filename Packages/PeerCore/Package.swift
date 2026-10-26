// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PeerCore", platforms: [.macOS(.v15)],
    products: [
        .library(name: "PeerCore", targets: ["PeerCore"]),
        .library(name: "PeerMacUI", targets: ["PeerMacUI"]),
    ],
    dependencies: [.package(url: "https://github.com/vapor/postgres-nio.git", from: "1.32.0")],
    targets: [
        .target(
            name: "PeerCore", dependencies: [.product(name: "PostgresNIO", package: "postgres-nio")]
        ),
        .target(name: "PeerMacUI", dependencies: ["PeerCore"]),
    ]
)
