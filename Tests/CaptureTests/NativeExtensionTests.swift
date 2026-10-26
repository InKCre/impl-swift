import Foundation
import PeerCore
import Testing

@MainActor private final class Module: NativeExtension {
    let descriptor = NativeExtensionDescriptor(
        name: "inkcre/test", distribution: "swift_bundled", version: "0.1.0")
    var starts = 0
    var stops = 0
    var intents: [Bool] = []
    var failure: PeerError?
    var stoppedBeforeSync = false
    func start() throws { starts += 1 }
    func stop() async throws { stops += 1 }
    func setEnabled(_ enabled: Bool) async throws {
        intents.append(enabled)
        stoppedBeforeSync = stops > 0
        if let failure { throw failure }
    }
    func showMain() {}
}

@Test @MainActor func nativeExtensionLifecycleKeepsRuntimeSeparateFromEnabledIntent() async throws {
    let domain = "dev.inkcre.extension-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let module = Module()
    let runtime = BundledExtensionRuntime(module: module, defaults: defaults)
    try runtime.startIfEnabled()
    #expect(runtime.running && module.starts == 1)
    try await runtime.stop()
    #expect(!runtime.running && runtime.enabled && module.intents.isEmpty)
    try runtime.startIfEnabled()
    try await runtime.setEnabled(false)
    #expect(!runtime.running && !runtime.enabled && module.intents == [false])
    let restarted = BundledExtensionRuntime(module: module, defaults: defaults)
    try restarted.startIfEnabled()
    #expect(!restarted.running && module.starts == 2)
    try await restarted.setEnabled(true)
    #expect(restarted.running && module.starts == 3)
    #expect(module.intents == [false, true])
    try await restarted.stop()
}

@Test(arguments: [PeerError.needsAction("凭据不可用"), .connection("数据库离线")])
@MainActor func disablingLocallySurvivesSharedStateFailure(_ failure: PeerError) async throws {
    let domain = "dev.inkcre.extension-tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let module = Module()
    module.failure = failure
    let runtime = BundledExtensionRuntime(module: module, defaults: defaults)
    try runtime.startIfEnabled()
    try await runtime.setEnabled(false)
    #expect(!runtime.running && !runtime.enabled && module.stops == 1)
    #expect(module.stoppedBeforeSync)
    #expect(runtime.syncIssue?.contains(failure.localizedDescription) == true)
    let reopened = BundledExtensionRuntime(module: module, defaults: defaults)
    try reopened.startIfEnabled()
    #expect(!reopened.running)
    if case .needsAction = failure {
        await #expect(throws: PeerError.self) { try await reopened.setEnabled(true) }
        #expect(!reopened.running && !reopened.enabled)
    }
}
