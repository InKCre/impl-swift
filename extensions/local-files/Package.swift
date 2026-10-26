// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InKCreLocalFiles", platforms: [.macOS(.v15)],
    products: [
        .library(name: "LocalFiles", targets: ["LocalFiles"]),
        .library(name: "LocalFilesMac", targets: ["LocalFilesMac"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PeerCore"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3"),
    ],
    targets: [
        .target(
            name: "LocalFiles",
            dependencies: [.product(name: "PeerCore", package: "PeerCore"), "SwiftSoup"],
            resources: [.copy("Resources/extension.json")]),
        .target(
            name: "LocalFilesMac",
            dependencies: ["LocalFiles", .product(name: "PeerCore", package: "PeerCore")]),
    ]
)
