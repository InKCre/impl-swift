// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InKCre", platforms: [.macOS(.v15)],
    products: [.executable(name: "InKCre", targets: ["InKCreApp"])],
    dependencies: [.package(path: "Packages/PeerCore"), .package(path: "extensions/capture")],
    targets: [
        .executableTarget(
            name: "InKCreApp",
            dependencies: [
                .product(name: "PeerCore", package: "PeerCore"),
                .product(name: "PeerMacUI", package: "PeerCore"),
                .product(name: "CaptureMac", package: "capture"),
            ]),
        .testTarget(
            name: "CaptureTests",
            dependencies: [
                .product(name: "Capture", package: "capture"),
                .product(name: "PeerCore", package: "PeerCore"),
            ], path: "Tests/CaptureTests", resources: [.copy("Fixtures")]),
        .testTarget(
            name: "CaptureMacTests",
            dependencies: [
                .product(name: "CaptureMac", package: "capture"),
                .product(name: "Capture", package: "capture"),
                .product(name: "PeerCore", package: "PeerCore"),
                .product(name: "PeerMacUI", package: "PeerCore"),
            ], path: "Tests/CaptureMacTests"),
    ]
)
