import AppKit
import SwiftUI

@MainActor
final class PeerMainWindow: NSWindow, NSWindowDelegate {
    private let host: PeerHost

    @objc func toggleSidebar(_ sender: Any?) {
        withAnimation {
            host.columnVisibility = host.columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(toggleSidebar(_:)) else {
            return super.validateUserInterfaceItem(item)
        }
        (item as? NSMenuItem)?.title = host.columnVisibility == .detailOnly ? "显示侧栏" : "隐藏侧栏"
        return attachedSheet == nil
    }

    init(host: PeerHost) {
        self.host = host
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "InKCre"
        toolbarStyle = .unified
        minSize = NSSize(width: 760, height: 520)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenPrimary]
        delegate = self
        contentViewController = NSHostingController(rootView: PeerMainView(host: host))
        if !setFrameUsingName("InKCreMainWindow") {
            setContentSize(NSSize(width: 1000, height: 720))
            center()
        }
        setFrameAutosaveName("InKCreMainWindow")
    }
    func windowDidBecomeKey(_ notification: Notification) { host.capture.mainWindowBecameKey() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { host.capture.windowShouldClose(sender) }
}
