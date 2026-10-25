import AppKit
import SwiftUI

@MainActor
final class PeerMainWindow: NSWindow {
    private let model: CaptureModel

    @objc func toggleSidebar(_ sender: Any?) {
        withAnimation {
            model.columnVisibility = model.columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(toggleSidebar(_:)) else {
            return super.validateUserInterfaceItem(item)
        }
        (item as? NSMenuItem)?.title = model.columnVisibility == .detailOnly ? "显示侧栏" : "隐藏侧栏"
        return attachedSheet == nil
    }

    init(model: CaptureModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
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
