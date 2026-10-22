// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, Kartik Labhshetwar
// Adapted for InKCre. Fixed source and modifications: Legal/BetterShot/ATTRIBUTION.txt.
import AppKit

struct RegionSelection {
    let pointsRect: CGRect
    let displayID: CGDirectDisplayID
}

enum RegionSelectionOutcome {
    case region(RegionSelection)
    case cancelled
}

@MainActor
final class RegionSelectionOverlay {
    private var overlayWindows: [NSWindow] = []
    private var selectionViews: [SelectionView] = []
    private var continuation: CheckedContinuation<RegionSelectionOutcome, Never>?
    private var cursorPushed = false
    private let present: ([NSWindow]) -> Void

    init(present: @escaping ([NSWindow]) -> Void = { windows in
        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        (windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? windows.first)?.makeKey()
    }) {
        self.present = present
    }

    func selectRegion(frozenFrames: [FrozenScreenFrame]) async -> RegionSelectionOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let frame = frozenFrames.first(where: { $0.displayID == number.uint32Value }) else { continue }
                let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .screenSaver
                window.hasShadow = false
                window.acceptsMouseMovedEvents = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.title = "框选截图"
                let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                         scaleFactor: CGFloat(frame.image.width) / frame.pointsRect.width) { [weak self] rect in
                    let global = RegionGeometry.globalRect(local: rect, screenFrame: screen.frame)
                    self?.finish(.region(RegionSelection(
                        pointsRect: RegionGeometry.pointsRect(global: global, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height),
                        displayID: frame.displayID)))
                } onCancel: { [weak self] in self?.cancel() }
                view.onBeginSelection = { [weak self, weak view] in
                    self?.selectionViews.forEach { if $0 !== view { $0.clearSelection() } }
                }
                let backdrop = FrozenBackdropView(image: frame.image, frame: view.frame)
                backdrop.addSubview(view)
                window.contentView = backdrop
                window.makeFirstResponder(view)
                overlayWindows.append(window)
                selectionViews.append(view)
            }
            guard !overlayWindows.isEmpty else { finish(.cancelled); return }
            present(overlayWindows)
            if overlayWindows.contains(where: \.isVisible) {
                NSCursor.crosshair.push()
                cursorPushed = true
            }
        }
    }

    func cancel() { finish(.cancelled) }

    private func finish(_ outcome: RegionSelectionOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        for window in overlayWindows { window.orderOut(nil); window.close() }
        overlayWindows.removeAll()
        selectionViews.removeAll()
        continuation.resume(returning: outcome)
    }
}

// MARK: - Overlay Window (prevents AppKit cursor resets)

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cursorUpdate(with event: NSEvent) {
        // Swallow cursor updates — we manage the cursor ourselves in SelectionView
    }
}

// MARK: - Frozen Backdrop

final class FrozenBackdropView: NSView {
    private let image: NSImage

    init(image: CGImage, frame: NSRect) {
        self.image = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) { image.draw(in: bounds) }
}

// MARK: - Selection View

final class SelectionView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var mouseLocation: NSPoint?
    private(set) var selection: CGRect?
    private var activeHandle: RegionHandle?
    private var handleDragOrigin: NSPoint?
    private var handleDragRect: CGRect?
    var onBeginSelection: () -> Void = {}
    private var trackingArea: NSTrackingArea?
    private let scaleFactor: CGFloat
    private let crosshairCursor: NSCursor
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void

    private var finished = false
    private let toolbar = NSVisualEffectView()
    private let hint = NSTextField(labelWithString: "")
    let confirmButton = NSButton(title: "截取", target: nil, action: nil)
    let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private var controls: NSStackView!

    init(
        frame: CGRect, scaleFactor: CGFloat,
        onSelect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void
    ) {
        self.scaleFactor = scaleFactor
        self.crosshairCursor = .crosshair
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = .labelColor
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelection)
        confirmButton.setAccessibilityIdentifier("capture.confirm")
        cancelButton.setAccessibilityIdentifier("capture.cancel")
        controls = NSStackView(views: [hint, cancelButton, confirmButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.addSubview(controls)
        addSubview(toolbar)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图选区")
        setAccessibilityHelp("拖动框选，松手后可移动区域或拖动八个手柄调整。回车截取，Esc 或取消按钮退出。")
        updateToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: crosshairCursor)
        setCursor(crosshairCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        setCursor(crosshairCursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        let rect = if let start = dragStart, let current = dragCurrent { rectFromPoints(start, current) } else { selection }
        if let rect, rect.width > 2, rect.height > 2 { shade.appendRect(rect) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        shade.fill()

        if let start = dragStart, let current = dragCurrent {
            drawSelection(start: start, current: current)
        } else if let selection {
            drawAdjustableSelection(selection)
        } else if let mouse = mouseLocation {
            drawGuideLines(at: mouse)
        }
    }

    private func drawGuideLines(at point: NSPoint) {
        let lineColor = NSColor.white.withAlphaComponent(0.4)
        lineColor.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 0.5

        // Vertical guide line
        path.move(to: NSPoint(x: point.x, y: bounds.minY))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))

        // Horizontal guide line
        path.move(to: NSPoint(x: bounds.minX, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))

        path.stroke()
    }

    private func drawSelection(start: NSPoint, current: NSPoint) {
        let selectionRect = rectFromPoints(start, current)
        guard selectionRect.width > 2, selectionRect.height > 2 else { return }

        drawBorder(selectionRect)

        drawLabel(pixelSize(selectionRect), below: selectionRect)
    }

    private func drawAdjustableSelection(_ rect: CGRect) {
        drawBorder(rect)

        for handle in RegionHandle.allCases where handle != .move {
            let p = handle.point(in: rect)
            let dot = NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }

    }

    private func pixelSize(_ rect: CGRect) -> String {
        "\(Int(rect.width * scaleFactor)) × \(Int(rect.height * scaleFactor))"
    }

    private func drawBorder(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect)
        NSColor.black.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 3.5
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawLabel(_ text: String, below rect: CGRect) {
        let label = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attrs)
        let width = labelSize.width + 12
        let height = labelSize.height + 4
        let labelRect = CGRect(
            x: min(max(rect.midX - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: max(rect.minY - height - 4, bounds.minY + 8),
            width: width,
            height: height
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    // MARK: - Mouse Events

    func clearSelection() {
        selection = nil
        dragStart = nil
        dragCurrent = nil
        activeHandle = nil
        updateToolbar()
        needsDisplay = true
    }

    private func adjustmentHandle(at point: NSPoint) -> RegionHandle? {
        guard let selection, let handle = RegionAdjustment.handle(at: point, in: selection) else { return nil }
        return handle
    }

    private func updateCursor(at point: NSPoint) {
        guard let handle = adjustmentHandle(at: point) else {
            setCursor(crosshairCursor)
            return
        }
        setCursor(Self.cursor(for: handle, dragging: false))
    }

    private static func cursor(for handle: RegionHandle, dragging: Bool) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .move: return dragging ? .closedHand : .openHand
        case .topLeft: position = .topLeft
        case .top: position = .top
        case .topRight: position = .topRight
        case .right: position = .right
        case .bottomRight: position = .bottomRight
        case .bottom: position = .bottom
        case .bottomLeft: position = .bottomLeft
        case .left: position = .left
        }
        return .frameResize(position: position, directions: .all)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        mouseLocation = loc
        updateCursor(at: loc)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    func beginDrag(at loc: CGPoint, clickCount: Int = 1) {
        guard !finished else { return }
        if window?.isVisible == true { window?.makeKey() }
        window?.makeFirstResponder(self)
        mouseLocation = nil
        if clickCount == 2, let selection, selection.contains(loc) {
            confirmSelection()
            return
        }
        if let selection, let handle = adjustmentHandle(at: loc) {
            activeHandle = handle
            handleDragOrigin = loc
            handleDragRect = selection
            setCursor(Self.cursor(for: handle, dragging: true))
            return
        }
        setCursor(crosshairCursor)
        onBeginSelection()
        selection = nil
        dragStart = clamped(loc)
        dragCurrent = clamped(loc)
        updateToolbar()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(at: convert(event.locationInWindow, from: nil))
    }

    func updateDrag(at loc: CGPoint) {
        guard !finished else { return }
        let loc = clamped(loc)
        if let handle = activeHandle, let origin = handleDragOrigin, let base = handleDragRect {
            let delta = CGSize(width: loc.x - origin.x, height: loc.y - origin.y)
            selection = RegionAdjustment.apply(handle, delta: delta, to: base, within: bounds)
        } else if dragStart != nil {
            setCursor(crosshairCursor)
            dragCurrent = loc
        }
        updateToolbar()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        endDrag(at: convert(event.locationInWindow, from: nil))
    }

    func endDrag(at end: CGPoint) {
        guard !finished else { return }
        updateDrag(at: end)
        let end = clamped(end)
        if activeHandle != nil {
            activeHandle = nil
            handleDragOrigin = nil
            handleDragRect = nil
            updateCursor(at: end)
            updateToolbar()
            return
        }
        guard let start = dragStart else { return }
        dragStart = nil
        dragCurrent = nil
        let rect = rectFromPoints(start, end)

        if rect.width > 3, rect.height > 3 {
            selection = rect
            updateCursor(at: end)
        }
        updateToolbar()
        needsDisplay = true
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

    @objc func confirmSelection() {
        guard let selection, selection.width > 3, selection.height > 3 else { return }
        finish(selection)
    }

    @objc func cancelSelection() { finish(nil) }

    private func finish(_ rect: CGRect?) {
        guard !finished else { return }
        finished = true
        confirmButton.isEnabled = false
        cancelButton.isEnabled = false
        if let rect { onSelect(rect) } else { onCancel() }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func setCursor(_ cursor: NSCursor) {
        if window?.isVisible == true { cursor.set() }
    }

    override func layout() {
        super.layout()
        updateToolbar()
    }

    private func updateToolbar() {
        toolbar.isHidden = dragStart != nil || activeHandle != nil
        let valid = selection.map { $0.width > 3 && $0.height > 3 } ?? false
        confirmButton.isHidden = !valid
        confirmButton.isEnabled = valid && !finished
        hint.stringValue = selection.map { "\(pixelSize($0)) · 拖动移动，边缘调整" } ?? "拖动框选 · Esc 取消"
        setAccessibilityValue(hint.stringValue)
        controls.layoutSubtreeIfNeeded()
        let size = controls.fittingSize
        let x = selection.map { $0.maxX - size.width } ?? (bounds.midX - size.width / 2)
        var y = bounds.maxY - size.height - 20
        if let selection {
            y = selection.minY - size.height - 12
            if y < 8 { y = selection.maxY + 12 }
        }
        toolbar.frame = CGRect(x: min(max(x, 8), max(8, bounds.maxX - size.width - 8)),
                               y: min(max(y, 8), max(8, bounds.maxY - size.height - 8)),
                               width: size.width, height: size.height)
        controls.frame = toolbar.bounds
    }

    private func rectFromPoints(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
