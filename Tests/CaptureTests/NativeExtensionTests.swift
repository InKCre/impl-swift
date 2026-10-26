import Foundation
import PeerCore
import Testing

@MainActor private final class Module: NativeExtension {
    let descriptor = NativeExtensionDescriptor(
        name: "inkcre/test", distribution: "swift_bundled", version: "0.1.0")
    var starts = 0
    var stops = 0
    func start() throws { starts += 1 }
    func stop() async throws { stops += 1 }
    func showMain() {}
}

@Test @MainActor func nativeExtensionLifecycleWorksWithoutAnyConnection() async throws {
    let domain = "dev.inkcre.extension-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let module = Module()
    let runtime = BundledExtensionRuntime(module: module, defaults: defaults)
    try runtime.startIfEnabled()
    #expect(runtime.running && module.starts == 1)
    try await runtime.stop()
    #expect(!runtime.running && runtime.enabled)
    try runtime.startIfEnabled()
    try await runtime.setEnabled(false)
    #expect(!runtime.running && !runtime.enabled && module.stops == 2)
    let restarted = BundledExtensionRuntime(module: module, defaults: defaults)
    try restarted.startIfEnabled()
    #expect(!restarted.running && module.starts == 2)
    try await restarted.setEnabled(true)
    #expect(restarted.running && module.starts == 3)
    try await restarted.stop()
}
