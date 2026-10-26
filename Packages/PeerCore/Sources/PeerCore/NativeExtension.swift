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
}

@MainActor
public protocol NativeExtension: AnyObject {
    var descriptor: NativeExtensionDescriptor { get }
    func start() throws
    func stop() async throws
    func showMain()
}
