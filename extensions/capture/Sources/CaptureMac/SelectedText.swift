// SPDX-License-Identifier: Apache-2.0
// References and adapts Cida by Xuanwo and contributors. Modified for InKCre persistent capture.
// Source revision and complete license: Legal/Cida/.
import AppKit
import ApplicationServices
import Capture
import Carbon.HIToolbox
import PeerCore

struct SelectionSnapshot: Sendable {
    var text: String?
    var origin: CaptureOrigin
    var rangeLength: Int = 0
    var secure = false
    var focus: SelectionFocus?
}

// AX references are immutable identities; IPC remains on a worker thread.
struct SelectionFocus: @unchecked Sendable {
    let element: AXUIElement
    let window: AXUIElement?
    let range: CFRange?
}

/// AX calls run off the main thread and each IPC has a bounded timeout.
enum SelectedText {
    static func read(pid: pid_t, applicationID: String?) -> SelectionSnapshot {
        var snapshot = SelectionSnapshot(origin: CaptureOrigin(applicationID: applicationID))
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.12)
        guard let focused = element(application, kAXFocusedUIElementAttribute) else {
            return snapshot
        }
        AXUIElementSetMessagingTimeout(focused, 0.12)
        snapshot.secure = string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
        guard !snapshot.secure else { return snapshot }
        let window = element(application, kAXFocusedWindowAttribute)
        if let window {
            AXUIElementSetMessagingTimeout(window, 0.12)
            snapshot.origin.title = string(window, kAXTitleAttribute)
            snapshot.origin.url = string(window, kAXDocumentAttribute)
        }
        snapshot.text = string(focused, kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 }
        var selectedRange: CFRange?
        if let value = attribute(focused, kAXSelectedTextRangeAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) {
                snapshot.rangeLength = range.length
                selectedRange = range
            }
        }
        // A delayed AX reply must not be attached to a different focused element.
        guard let current = element(application, kAXFocusedUIElementAttribute),
            CFEqual(current, focused)
        else {
            return SelectionSnapshot(origin: CaptureOrigin(applicationID: applicationID))
        }
        snapshot.focus = SelectionFocus(element: focused, window: window, range: selectedRange)
        return snapshot
    }

    static func isCurrent(pid: pid_t, snapshot: SelectionSnapshot) -> Bool {
        guard let focus = snapshot.focus else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.12)
        guard let current = element(application, kAXFocusedUIElementAttribute),
            CFEqual(current, focus.element)
        else { return false }
        AXUIElementSetMessagingTimeout(current, 0.12)
        if let window = focus.window {
            guard let currentWindow = element(application, kAXFocusedWindowAttribute),
                CFEqual(window, currentWindow)
            else { return false }
        }
        if let expected = focus.range {
            guard let value = attribute(current, kAXSelectedTextRangeAttribute),
                CFGetTypeID(value) == AXValueGetTypeID()
            else { return false }
            var actual = CFRange()
            guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &actual),
                actual.location == expected.location, actual.length == expected.length
            else { return false }
        }
        if let text = snapshot.text, string(current, kAXSelectedTextAttribute) != text {
            return false
        }
        return string(current, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        let value = attribute(element, name)
        if let url = value as? URL { return url.absoluteString }
        return value as? String
    }

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    @MainActor
    static func copyFallback(
        pid: pid_t, snapshot selection: SelectionSnapshot, isActive: () -> Bool
    ) async -> String? {
        let expectedLength = selection.rangeLength
        guard expectedLength > 0, !IsSecureEventInputEnabled(),
            isActive(),
            await Task.detached(operation: { isCurrent(pid: pid, snapshot: selection) }).value,
            isActive()
        else { return nil }
        let board = NSPasteboard.general
        let originalCount = board.changeCount
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        var size = 0
        for item in board.pasteboardItems ?? [] {
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                size += data.count
                guard size <= 32 * 1024 * 1024 else { return nil }
                representations[type] = data
            }
            snapshot.append(representations)
        }
        guard board.changeCount == originalCount, isActive(),
            let down = CGEvent(
                keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
            let up = CGEvent(
                keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        for _ in 0..<12 {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return nil }
            guard isActive() else { return nil }
            if board.changeCount != originalCount {
                let copiedCount = board.changeCount
                guard let text = board.string(forType: .string), text.utf16.count == expectedLength
                else { return nil }
                // Restore only the copy we observed; a later user copy always wins.
                if board.changeCount == copiedCount {
                    let items = snapshot.map { representations in
                        let item = NSPasteboardItem()
                        for (type, data) in representations { item.setData(data, forType: type) }
                        return item
                    }
                    board.clearContents()
                    if !items.isEmpty { board.writeObjects(items) }
                }
                guard
                    await Task.detached(operation: { isCurrent(pid: pid, snapshot: selection) })
                        .value,
                    isActive()
                else { return nil }
                return text
            }
        }
        return nil
    }
}
