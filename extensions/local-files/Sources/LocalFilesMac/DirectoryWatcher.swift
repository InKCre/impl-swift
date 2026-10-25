import CoreServices
import Foundation
import PeerCore

@MainActor
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init(path: String, changed: @escaping () -> Void) throws {
        self.changed = changed
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().changed()
                    }
                }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.8,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents
                        | kFSEventStreamCreateFlagNoDefer))
        else { throw PeerError.needsAction("无法监视目录。") }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            throw PeerError.needsAction("无法启动目录监视。")
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
