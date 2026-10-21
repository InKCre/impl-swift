import AppKit
import SwiftUI

@MainActor
final class PeerMainWindow: NSWindow {
    init(model: CaptureModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "InKCre"
        toolbarStyle = .unified
        minSize = NSSize(width: 760, height: 520)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenPrimary]
        contentViewController = NSHostingController(rootView: PeerMainView(model: model))
        if !setFrameUsingName("InKCreMainWindow") { center() }
        setFrameAutosaveName("InKCreMainWindow")
    }
}
