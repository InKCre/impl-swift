import AppKit
import Testing
@testable import CaptureMac

@Suite(.serialized) @MainActor
struct RegionOverlayTests {
    @Test func deniedAccessReturnsAnInlineIssueWithoutOpeningAnOverlayOrRequestingPermission() {
        _ = NSApplication.shared
        let windows = NSApp.windows.count
        var checks = 0
        let capture = RegionCapture(hasPermission: { checks += 1; return false })
        var denied = 0
        for _ in 0..<3 {
            capture.begin { result in
                if case .failure(let error) = result, error is ScreenRecordingPermissionError { denied += 1 }
                else { Issue.record("拒绝访问不得进入框选或截取。") }
            }
        }
        #expect(checks == 3)
        #expect(denied == 3)
        #expect(!capture.isCapturing)
        #expect(NSApp.windows.count == windows)
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, in view: NSView) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                                       timestamp: 0, windowNumber: view.window!.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @Test func firstDragKeepsVisibleSelectionUntilExplicitConfirmation() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let view = RegionOverlay(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = view
        var completed = false
        var calls = 0
        var result: CGRect?
        view.complete = { result = $0; completed = true; calls += 1 }
        #expect(view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 400, y: 300), in: view))
        view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 100, y: 100), in: view))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 100, y: 100), in: view))
        #expect(view.selection == CGRect(x: 100, y: 100, width: 300, height: 200))
        #expect(!completed)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let edge = try #require(bitmap.colorAt(x: Int(100 * scale), y: Int(200 * scale)))
        let inside = try #require(bitmap.colorAt(x: Int(200 * scale), y: Int(200 * scale)))
        let outside = try #require(bitmap.colorAt(x: Int(40 * scale), y: Int(200 * scale)))
        #expect(edge.alphaComponent > 0.95)
        #expect(inside.alphaComponent < 0.05)
        #expect(outside.alphaComponent > 0.25 && outside.alphaComponent < 0.5)
        view.confirmSelection()
        view.confirmSelection()
        #expect(completed)
        #expect(calls == 1)
        #expect(result == view.selection)
    }

    @Test func resettingOrCancellingNeverCapturesAccidentalTinySelection() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let view = RegionOverlay(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = view
        var calls = 0
        view.complete = { rect in #expect(rect == nil); calls += 1 }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 200, y: 200), in: view))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 201, y: 201), in: view))
        view.confirmSelection()
        #expect(calls == 0)
        view.resetSelection()
        #expect(view.selection.isEmpty)
        view.cancelSelection()
        view.cancelSelection()
        #expect(calls == 1)
    }
}
