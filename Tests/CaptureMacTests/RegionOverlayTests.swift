// Geometry and frozen-pixel cases adapted from BetterShot's checks, BSD-3-Clause.
// Copyright (c) 2026, Kartik Labhshetwar. See extensions/capture/Legal/BetterShot/.
import AppKit
import ImageIO
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

    private func drag(_ view: SelectionView, from start: CGPoint, to end: CGPoint) throws {
        view.mouseDown(with: try event(.leftMouseDown, at: start, in: view))
        view.mouseDragged(with: try event(.leftMouseDragged, at: end, in: view))
        view.mouseUp(with: try event(.leftMouseUp, at: end, in: view))
    }

    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 520), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func selectMoveResizeAndClickConfirmUsesOneVisibleAdjustableRegion() throws {
        let window = window()
        defer { window.close() }
        var results: [CGRect] = []
        let view = SelectionView(frame: window.contentView!.bounds, scaleFactor: 2,
                                 onSelect: { results.append($0) }, onCancel: { Issue.record("不应取消。") })
        window.contentView = view
        #expect(view.acceptsFirstMouse(for: nil))
        try drag(view, from: CGPoint(x: 500, y: 400), to: CGPoint(x: 100, y: 120))
        #expect(view.selection == CGRect(x: 100, y: 120, width: 400, height: 280))
        #expect(results.isEmpty)
        try drag(view, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 240, y: 230))
        #expect(view.selection == CGRect(x: 140, y: 150, width: 400, height: 280))
        try drag(view, from: CGPoint(x: 540, y: 430), to: CGPoint(x: 600, y: 470))
        let rect = CGRect(x: 140, y: 150, width: 460, height: 320)
        #expect(view.selection == rect)
        #expect(results.isEmpty)
        view.layoutSubtreeIfNeeded()
        let buttonRect = view.confirmButton.convert(view.confirmButton.bounds, to: view)
        #expect(view.bounds.contains(buttonRect))
        #expect(!view.confirmButton.isHidden && view.confirmButton.isEnabled)
        #expect(view.hitTest(CGPoint(x: buttonRect.midX, y: buttonRect.midY)) === view.confirmButton)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let edge = try #require(bitmap.colorAt(x: Int(rect.minX * scale), y: Int((view.bounds.height - rect.midY) * scale)))
        let inside = try #require(bitmap.colorAt(x: Int(rect.midX * scale), y: Int((view.bounds.height - rect.midY) * scale)))
        let outside = try #require(bitmap.colorAt(x: Int(40 * scale), y: Int(250 * scale)))
        #expect(edge.alphaComponent > 0.9)
        #expect(inside.alphaComponent < 0.05)
        #expect(outside.alphaComponent > 0.25 && outside.alphaComponent < 0.5)
        view.confirmButton.performClick(nil)
        view.confirmSelection()
        view.cancelSelection()
        #expect(results == [rect])
        #expect(!window.isVisible)
    }

    @Test func tinySelectionCanBeRedrawnAndCancelButtonOrEscapeNeverConfirms() throws {
        for escape in [false, true] {
            let window = window()
            defer { window.close() }
            var cancelled = 0
            let view = SelectionView(frame: window.contentView!.bounds, scaleFactor: 1,
                                     onSelect: { _ in Issue.record("取消不得产图。") }, onCancel: { cancelled += 1 })
            window.contentView = view
            try drag(view, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 201, y: 201))
            #expect(view.selection == nil)
            view.confirmSelection()
            #expect(cancelled == 0)
            try drag(view, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 300, y: 260))
            #expect(view.confirmButton.isEnabled)
            if escape {
                let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil,
                                                       characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                       isARepeat: false, keyCode: 53))
                view.keyDown(with: key)
            } else { view.cancelButton.performClick(nil) }
            view.cancelSelection()
            #expect(cancelled == 1)
        }
    }

    @Test func stopClosesActualOverlayAndDiscardsPendingResultWithoutPresentingWindows() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let frame = FrozenScreenFrame(displayID: number.uint32Value, pointsRect: CGDisplayBounds(number.uint32Value),
                                      image: try pixels(width: 8, height: 6))
        var windows: [NSWindow] = []
        let closing = WindowCloseObserver()
        let overlay = RegionSelectionOverlay(present: { windows = $0; windows.forEach { $0.delegate = closing } })
        let capture = RegionCapture(hasPermission: { true }, freezeScreens: { [frame] }, overlay: overlay)
        var callbacks = 0
        capture.begin { _ in callbacks += 1 }
        for _ in 0..<100 where windows.isEmpty { await Task.yield() }
        #expect(capture.isCapturing)
        #expect(windows.count == 1)
        #expect(windows.allSatisfy { !$0.isVisible })
        await capture.stop()
        #expect(!capture.isCapturing)
        #expect(callbacks == 0)
        #expect(windows.allSatisfy { !$0.isVisible })
        #expect(closing.closed == 1)
        overlay.cancel()
    }

    @Test func confirmedRegionReturnsOnlyFrozenPngThroughCaptureCoordinator() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let frame = FrozenScreenFrame(displayID: number.uint32Value, pointsRect: CGDisplayBounds(number.uint32Value),
                                      image: try pixels(width: 8, height: 6))
        var freezes = 0
        let overlay = RegionSelectionOverlay(present: { windows in
            let view = windows[0].contentView!.subviews[0] as! SelectionView
            view.beginDrag(at: CGPoint(x: screen.frame.width / 4, y: screen.frame.height / 4))
            view.endDrag(at: CGPoint(x: screen.frame.width * 3 / 4, y: screen.frame.height * 3 / 4))
            view.confirmButton.performClick(nil)
        })
        let capture = RegionCapture(hasPermission: { true }, freezeScreens: { freezes += 1; return [frame] }, overlay: overlay)
        let result: Result<Data?, Error> = await withCheckedContinuation { continuation in
            capture.begin { continuation.resume(returning: $0) }
        }
        let data = try #require(try result.get())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let expected = try frame.croppedImage(in: CGRect(x: frame.pointsRect.minX + frame.pointsRect.width / 4,
                                                       y: frame.pointsRect.minY + frame.pointsRect.height / 4,
                                                       width: frame.pointsRect.width / 2, height: frame.pointsRect.height / 2))
        #expect(rgba(image) == rgba(expected))
        #expect(freezes == 1)
        #expect(!capture.isCapturing)
    }

    @Test func frozenBackgroundAndControlsRenderInsideSmallDisplayInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let window = window()
            defer { window.close() }
            window.appearance = NSAppearance(named: name)
            let image = NSImage(size: window.contentView!.bounds.size)
            image.lockFocus()
            NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: image.size)).fill()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: 80, y: 80, width: 640, height: 360), xRadius: 12, yRadius: 12).fill()
            ("InKCre · 合成截图验收" as NSString).draw(at: CGPoint(x: 120, y: 365), withAttributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.black])
            ("选中眼前的信息，随手收入。\n\n框选后仍可移动、调整大小，再确认保存。\n这段文字与背景均为测试生成的合成内容。" as NSString).draw(
                in: CGRect(x: 120, y: 170, width: 550, height: 160), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray])
            image.unlockFocus()
            let backdrop = FrozenBackdropView(image: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)),
                                              frame: window.contentView!.bounds)
            let view = SelectionView(frame: backdrop.bounds, scaleFactor: 2, onSelect: { _ in }, onCancel: {})
            backdrop.addSubview(view)
            window.contentView = backdrop
            for state in ["ready", "selected", "edge"] {
                if state == "selected" { try drag(view, from: CGPoint(x: 100, y: 130), to: CGPoint(x: 690, y: 415)) }
                if state == "edge" { try drag(view, from: CGPoint(x: 740, y: 10), to: CGPoint(x: 790, y: 70)) }
                backdrop.layoutSubtreeIfNeeded()
                let button = state == "ready" ? view.cancelButton : view.confirmButton
                let rect = button.convert(button.bounds, to: view)
                #expect(rect.width > 35 && rect.height > 15)
                #expect(view.bounds.contains(rect))
                #expect(view.hitTest(CGPoint(x: rect.midX, y: rect.midY)) === button)
                let bitmap = try #require(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
                backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / backdrop.bounds.width
                let outside = try #require(bitmap.colorAt(x: Int(40 * scale), y: Int(260 * scale))?.usingColorSpace(.deviceRGB))
                #expect(outside.redComponent > 0.5 && outside.redComponent < 0.75)
                if state == "selected" {
                    let inside = try #require(bitmap.colorAt(x: Int(670 * scale), y: Int(370 * scale))?.usingColorSpace(.deviceRGB))
                    #expect(inside.redComponent > 0.95 && inside.alphaComponent > 0.95)
                }
                if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
                    let file = "capture-\(name.rawValue)-\(state).png"
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent(file))
                }
            }
        }
    }

    @Test func frozenCropUsesOriginalPixelsAtEachDisplayScaleAndGlobalOrigin() throws {
        let image = try pixels(width: 8, height: 6)
        let frame = FrozenScreenFrame(displayID: 2, pointsRect: CGRect(x: -4, y: -3, width: 4, height: 3), image: image)
        let region = CGRect(x: -3, y: -2.5, width: 2, height: 1.5)
        let cropped = try frame.croppedImage(in: region)
        #expect(cropped.width == 4 && cropped.height == 3)
        let bytes = rgba(cropped)
        for y in 0..<3 {
            for x in 0..<4 {
                let i = (y * 4 + x) * 4
                #expect(bytes[i] == UInt8((x + 2) * 20))
                #expect(bytes[i + 1] == UInt8((y + 1) * 30))
            }
        }
        let source = try #require(CGImageSourceCreateWithData(try frame.png(in: region) as CFData, nil))
        let png = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(rgba(png) == bytes)
        #expect(RegionGeometry.pointsRect(global: CGRect(x: -3, y: 101, width: 2, height: 1.5), primaryHeight: 100) == region)
        let single = FrozenScreenFrame(displayID: 3, pointsRect: CGRect(x: 100, y: 50, width: 8, height: 6), image: image)
        let singleCrop = try single.croppedImage(in: CGRect(x: 102, y: 51, width: 4, height: 3))
        #expect(singleCrop.width == 4 && singleCrop.height == 3)
        #expect(throws: (any Error).self) { try frame.croppedImage(in: .zero) }
        #expect(throws: (any Error).self) { try frame.croppedImage(in: CGRect(x: -5, y: -3, width: 2, height: 2)) }
    }

    @Test func resizingAcrossOppositeEdgeAndMovingStaysWithinDisplay() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(RegionAdjustment.apply(.left, delta: CGSize(width: 250, height: 0), to: selection, within: screen)
                == CGRect(x: 300, y: 100, width: 50, height: 100))
        #expect(RegionAdjustment.apply(.move, delta: CGSize(width: 900, height: -10), to: selection, within: screen)
                == CGRect(x: 800, y: 90, width: 200, height: 100))
    }

    private func pixels(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8]()
        for y in 0..<height { for x in 0..<width { bytes += [UInt8(x * 20), UInt8(y * 30), 80, 255] } }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

@MainActor private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    var closed = 0
    func windowWillClose(_ notification: Notification) { closed += 1 }
}
