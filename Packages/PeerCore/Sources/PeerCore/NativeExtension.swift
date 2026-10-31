import Foundation

public struct NativeExtensionDescriptor: Codable, Sendable, Equatable {
    public let name: String
    public let distribution: String
    public let version: String
    public init(name: String, distribution: String, version: String) {
        self.name = name
        self.distribution = distribution
        self.version = version
    }

    /// SwiftPM and the packaged app read the same shipped manifest.
    public static func bundled(
        resourceBundle: String, developmentBundle: @autoclosure () -> Bundle
    ) -> Self {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.url(forResource: resourceBundle, withExtension: "bundle"),
                let packaged = Bundle(url: url)
            else { preconditionFailure("Missing packaged extension: \(resourceBundle)") }
            bundle = packaged
        } else {
            bundle = developmentBundle()
        }
        guard let url = bundle.url(forResource: "extension", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let descriptor = try? JSONDecoder().decode(Self.self, from: data)
        else { preconditionFailure("Invalid extension manifest: \(resourceBundle)") }
        return descriptor
    }

}

@MainActor
public protocol NativeExtension: AnyObject {
    var descriptor: NativeExtensionDescriptor { get }
    func start() throws
    func stop() async throws
    func showMain()
}
