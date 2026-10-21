// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InKCre",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "InKCre", targets: ["InKCreApp"]),
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CaptureCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "InKCreApp", dependencies: ["CaptureCore"], resources: [.copy("Resources/Brand")]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "InKCreAppTests", dependencies: ["InKCreApp"]),
    ]
)
