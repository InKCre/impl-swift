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
        .package(
            url: "https://github.com/neolee/swift-readability.git",
            revision: "53be6c0d9c3723a7f9acb17324d435740347a872"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0"),
    ],
    targets: [
        .target(
            name: "LocalFiles",
            dependencies: [
                .product(name: "PeerCore", package: "PeerCore"), "SwiftSoup",
                .product(name: "Readability", package: "swift-readability"),
            ],
            resources: [.copy("Resources/extension.json")]),
        .target(
            name: "LocalFilesMac",
            dependencies: [
                "LocalFiles", .product(name: "PeerCore", package: "PeerCore"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"), "SwiftSoup",
            ]),
    ]
)
