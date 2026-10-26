// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InKCreCapture", platforms: [.macOS(.v15)],
    products: [
        .library(name: "Capture", targets: ["Capture"]),
        .library(name: "CaptureMac", targets: ["CaptureMac"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PeerCore"),
        .package(
            url: "https://github.com/InKCre/ui.git",
            revision: "15487b91b68ee3999ee6302276f621d0374757e6"),
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(
            name: "Capture",
            dependencies: ["CSQLite", .product(name: "PeerCore", package: "PeerCore")],
            resources: [.copy("Resources/extension.json")]),
        .target(
            name: "CaptureMac",
            dependencies: [
                "Capture", .product(name: "PeerCore", package: "PeerCore"),
                .product(name: "PeerMacUI", package: "PeerCore"),
                .product(name: "InKCreLogoAssets", package: "ui"),
            ], resources: [.copy("Resources/Brand")]),
    ]
)
