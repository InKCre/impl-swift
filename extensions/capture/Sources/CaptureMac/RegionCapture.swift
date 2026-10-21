// SPDX-License-Identifier: Apache-2.0
// References and adapts Cida by Xuanwo and contributors. Modified for InKCre persistent capture.
// Source revision and complete license: Legal/Cida/.
import AppKit
import Capture
import PeerCore
import ScreenCaptureKit

struct ScreenRecordingPermissionError: LocalizedError {
    var errorDescription: String? {
        "系统尚未允许当前 InKCre 读取屏幕。请在设置中授权，随后完全退出并重新打开应用。"
    }
}

@MainActor
final class RegionCapture {
    private var captureTask: Task<Void, Never>?
    private var windows: [NSWindow] = []
    private var completion: ((Result<Data?, Error>) -> Void)?
    private let hasPermission: () -> Bool
    var isCapturing: Bool { completion != nil }

    init(hasPermission: @escaping () -> Bool = CGPreflightScreenCaptureAccess) {
        self.hasPermission = hasPermission
    }

    func begin(completion: @escaping (Result<Data?, Error>) -> Void) {
        guard self.completion == nil else { return }
        // Checking is silent; requesting access is an explicit settings action, never a retry side effect.
        guard hasPermission() else {
            completion(.failure(ScreenRecordingPermissionError()))
            return
        }
        self.completion = completion
        guard !NSScreen.screens.isEmpty else {
            finish(.failure(PeerError.invalid("没有可用的屏幕，请重新截图。")))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = RegionWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.title = "框选截图"
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let overlay = RegionOverlay(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlay.didBeginSelection = { [weak self, weak overlay] in
                for window in self?.windows ?? [] {
                    if let other = window.contentView as? RegionOverlay, other !== overlay {
                        other.resetSelection()
                    }
                }
            }
            overlay.complete = { [weak self] rect in
                guard let self, !self.windows.isEmpty else { return }
                if let rect { self.capture(screen: screen, rect: rect) } else { self.finish(.success(nil)) }
            }
            window.contentView = overlay
            window.makeFirstResponder(overlay)
            windows.append(window)
            window.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { window.makeKey() }
        }
        NSCursor.crosshair.push()
    }

    func stop() async {
        completion = nil
        if !windows.isEmpty { hide() }
        captureTask?.cancel()
        await captureTask?.value
        captureTask = nil
    }

    private func hide() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSCursor.pop()
    }

    private func finish(_ result: Result<Data?, Error>) {
        if !windows.isEmpty { hide() }
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func capture(screen: NSScreen, rect: CGRect) {
        hide()
        captureTask = Task {
            do {
                guard
                    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? NSNumber
                else {
                    throw PeerError.invalid("无法识别所选屏幕。")
                }
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard !Task.isCancelled, completion != nil else { return }
                guard let display = content.displays.first(where: { $0.displayID == number.uint32Value })
                else {
                    throw PeerError.invalid("所选屏幕已断开，请重新截图。")
                }
                let own = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier
                }
                let filter = SCContentFilter(
                    display: display, excludingApplications: own, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                // Overlay coordinates are local, top-left points; SCK maps them to this display.
                configuration.sourceRect = rect
                configuration.width = max(1, Int((rect.width * CGFloat(filter.pointPixelScale)).rounded()))
                configuration.height = max(1, Int((rect.height * CGFloat(filter.pointPixelScale)).rounded()))
                configuration.showsCursor = false
                configuration.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration)
                guard !Task.isCancelled, completion != nil else { return }
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else {
                    throw PeerError.invalid("截图编码失败，请重试。")
                }
                try CapturePayload(
                    entry: .screenshot, materials: [Material(image: data, mimeType: "image/png")]
                ).validate()
                finish(.success(data))
            } catch {
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain,
                    failure.code == SCStreamError.Code.userDeclined.rawValue
                {
                    finish(.failure(ScreenRecordingPermissionError()))
                } else {
                    finish(.failure(error))
                }
            }
        }
    }
}

private final class RegionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class RegionOverlay: NSView {
    var complete: ((CGRect?) -> Void)?
    var didBeginSelection: (() -> Void)?
    private var start: CGPoint?
    private(set) var selection = CGRect.zero
    private let hint = NSTextField(labelWithString: "拖动框选本屏区域 · Esc 或右键取消")
    private let accept = NSButton(title: "截取 ↩", target: nil, action: nil)
    private let reset = NSButton(title: "重新框选", target: nil, action: nil)
    private let cancel = NSButton(title: "取消", target: nil, action: nil)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // A global shortcut can open this view while another app still owns the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 15, weight: .medium)
        for (button, action) in [
            (accept, #selector(confirmSelection)), (reset, #selector(resetSelection)),
            (cancel, #selector(cancelSelection)),
        ] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            addSubview(button)
        }
        addSubview(hint)
        accept.isEnabled = false
        reset.isEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        hint.frame = CGRect(x: 24, y: 22, width: max(200, bounds.width - 370), height: 25)
        cancel.frame = CGRect(x: bounds.maxX - 110, y: 20, width: 86, height: 32)
        accept.frame = CGRect(x: bounds.maxX - 212, y: 20, width: 94, height: 32)
        reset.frame = CGRect(x: bounds.maxX - 314, y: 20, width: 94, height: 32)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        shade.fill()
        if !selection.isEmpty {
            let border = NSBezierPath(rect: selection)
            NSColor.black.setStroke()
            border.lineWidth = 4
            border.stroke()
            NSColor.white.setStroke()
            border.lineWidth = 2
            border.stroke()
            for point in [
                CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
                CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY),
            ] {
                let handle = NSBezierPath(rect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                NSColor.white.setFill()
                handle.fill()
                NSColor.black.setStroke()
                handle.lineWidth = 1
                handle.stroke()
            }
        }
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(
            roundedRect: CGRect(x: 12, y: 12, width: bounds.width - 24, height: 50), xRadius: 10, yRadius: 10
        ).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        didBeginSelection?()
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        accept.isEnabled = false
        reset.isEnabled = false
        hint.stringValue = "拖动框选本屏区域 · Esc 或右键取消"
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(start.x - end.x), height: abs(start.y - end.y)
        ).intersection(bounds)
        hint.stringValue = "已选 \(Int(selection.width)) × \(Int(selection.height)) · 松手后确认截取"
        display()
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        let valid = selection.width >= 2 && selection.height >= 2
        accept.isEnabled = valid
        reset.isEnabled = !selection.isEmpty
        hint.stringValue =
            valid
            ? "已选 \(Int(selection.width)) × \(Int(selection.height)) · 点击截取或按回车"
            : "请拖动框选区域 · Esc 或右键取消"
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelSelection()
        case 36, 76: confirmSelection()
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) { cancelSelection() }
    override func rightMouseDown(with event: NSEvent) { cancelSelection() }

    @objc func resetSelection() {
        selection = .zero
        start = nil
        accept.isEnabled = false
        reset.isEnabled = false
        hint.stringValue = "拖动框选本屏区域 · Esc 或右键取消"
        needsDisplay = true
    }
    @objc func confirmSelection() {
        guard accept.isEnabled else { return }
        accept.isEnabled = false
        finishSelection(selection)
    }
    @objc func cancelSelection() { finishSelection(nil) }

    private func finishSelection(_ rect: CGRect?) {
        let callback = complete
        complete = nil
        callback?(rect)
    }
}
