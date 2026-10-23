import Foundation
import LocalFiles
import PeerCore

@MainActor
public final class LocalFilesExtension: NativeExtension {
  public let descriptor = LocalFilesContract.descriptor
  public let model: LocalFilesModel
  public var present: (() -> Void)?
  private let context: PeerHostContext
  public init(context: PeerHostContext) {
    self.context = context
    model = LocalFilesModel(context: context)
  }
  public func start() throws { try model.start() }
  public func stop() async throws { await model.stop() }
  public func showMain() { present?() }
  public func setEnabled(_ enabled: Bool) async throws {
    guard let target = try await context.connections.load() else { return }
    do {
      try await PeerDatabase.shared.setEnabled(
        enabled, target: target,
        password: context.credentials.read(for: target.id), extension: descriptor)
    } catch { throw PeerDatabase.failure(error) }
  }
}
