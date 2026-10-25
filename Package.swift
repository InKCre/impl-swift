// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InKCre", platforms: [.macOS(.v15)],
    products: [.executable(name: "InKCre", targets: ["InKCreApp"])],
    dependencies: [
        .package(path: "Packages/PeerCore"), .package(path: "extensions/capture"),
        .package(path: "extensions/local-files"),
    ],
    targets: [
        .executableTarget(
            name: "InKCreApp",
            dependencies: [
                .product(name: "PeerCore", package: "PeerCore"),
                .product(name: "PeerMacUI", package: "PeerCore"),
                .product(name: "CaptureMac", package: "capture"),
                .product(name: "LocalFilesMac", package: "local-files"),
            ]),
        .testTarget(
            name: "LocalFilesTests",
            dependencies: [
                .product(name: "LocalFiles", package: "local-files"),
                .product(name: "LocalFilesMac", package: "local-files"),
                .product(name: "PeerCore", package: "PeerCore"),
            ], path: "Tests/LocalFilesTests"),
        .testTarget(name: "HostTests", dependencies: ["InKCreApp"], path: "Tests/HostTests"),
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
