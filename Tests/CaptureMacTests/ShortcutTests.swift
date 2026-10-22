import AppKit
import Carbon.HIToolbox
import Capture
import PeerCore
import Testing
@testable import CaptureMac

@Suite(.serialized) @MainActor
struct ShortcutTests {
    @Test func captureShortcutDoesNotConsumeKeysWhileAnAttachedSheetOwnsInput() throws {
        _ = NSApplication.shared
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        window.beginSheet(sheet)
        defer { window.endSheet(sheet); window.orderOut(nil) }
        shortcuts.isCaptureWindow = { $0 === window }
        var performed = false
        shortcuts.perform = { _ in performed = true }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
        #expect(window.attachedSheet === sheet)
        #expect(shortcuts.handle(event) === event)
        #expect(!performed)
    }

    @Test func ordinaryUnicodeInputPassesThroughWithoutKeyboardLayoutTranslation() throws {
        _ = NSApplication.shared
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        shortcuts.isCaptureWindow = { _ in true }
        let text = "InKCre UI Audit 中文 👩🏽‍💻"
        let cg = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            cg.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        let event = try #require(NSEvent(cgEvent: cg))
        let original = try #require(event.characters)
        #expect(original == text)
        #expect(shortcuts.handle(event) === event)
        #expect(event.characters == original)
        var count = 0
        var result = [UniChar](repeating: 0, count: 256)
        cg.keyboardGetUnicodeString(maxStringLength: result.count, actualStringLength: &count, unicodeString: &result)
        #expect(String(utf16CodeUnits: result, count: count) == original)
    }

    @Test func unavailableActionsPassThroughAndAvailableActionsRunOnce() throws {
        _ = NSApplication.shared
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        shortcuts.isCaptureWindow = { _ in true }
        var enabled = false
        var performed = 0
        shortcuts.canPerform = { _, _ in enabled }
        shortcuts.perform = { _ in performed += 1 }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
        #expect(shortcuts.handle(event) === event)
        #expect(performed == 0)
        enabled = true
        #expect(shortcuts.handle(event) == nil)
        #expect(performed == 1)
    }

    @Test func invalidSavedBindingDoesNotPreventOpeningSettingsOrDisableOtherActions() throws {
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var saved = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        saved[.hide] = RecordedShortcut(keyCode: UInt16(kVK_ANSI_W), modifiers: .command, keyLabel: "W")
        let data = try JSONEncoder().encode(saved)
        defaults.set(data, forKey: GlobalShortcuts.settingsKey)
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        #expect(shortcuts.bindings[.hide] == nil)
        #expect(shortcuts.bindings[.capture] == ShortcutAction.capture.defaultShortcut)
        #expect(shortcuts.message?.contains("⌘W") == true)
        #expect(defaults.data(forKey: GlobalShortcuts.settingsKey) == data)
    }

    @Test func nativeWindowAndEditingCommandsCannotBeReassigned() throws {
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        for (key, label, modifiers) in [
            (kVK_ANSI_W, "W", NSEvent.ModifierFlags.command), (kVK_ANSI_Q, "Q", .command),
            (kVK_ANSI_Comma, ",", .command), (kVK_ANSI_V, "V", .command),
            (kVK_ANSI_S, "S", [.command, .option])
        ] {
            #expect(throws: PeerError.self) {
                try shortcuts.set(RecordedShortcut(keyCode: UInt16(key), modifiers: modifiers, keyLabel: label), for: .hide)
            }
        }
        #expect(shortcuts.bindings[.hide] == ShortcutAction.hide.defaultShortcut)
        #expect(defaults.data(forKey: GlobalShortcuts.settingsKey) == nil)
    }

    private func defaults() -> (UserDefaults, String) {
        let name = "dev.inkcre.shortcut-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func individualBindingsAndDisablingSurviveRestart() throws {
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        let replacement = RecordedShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control, .option], keyLabel: "K")
        try shortcuts.set(replacement, for: .capture)
        try shortcuts.set(nil, for: .screenshot)
        let reopened = try GlobalShortcuts(defaults: defaults)
        #expect(reopened.bindings[.capture] == replacement)
        #expect(reopened.bindings[.screenshot] == nil)
        #expect(reopened.bindings[.submit] == ShortcutAction.submit.defaultShortcut)
        #expect(reopened.bindings[.paste] == ShortcutAction.paste.defaultShortcut)
        try reopened.set(ShortcutAction.screenshot.defaultShortcut, for: .screenshot)
        #expect(reopened.bindings[.capture] == replacement)
    }

    @Test func duplicateAndPlainTypingCannotReplaceOldSettings() throws {
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        #expect(throws: PeerError.self) { try shortcuts.set(ShortcutAction.submit.defaultShortcut, for: .capture) }
        #expect(throws: PeerError.self) {
            try shortcuts.set(RecordedShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: .shift, keyLabel: "A"), for: .submit)
        }
        #expect(shortcuts.bindings[.capture] == ShortcutAction.capture.defaultShortcut)
        #expect(shortcuts.bindings[.submit] == ShortcutAction.submit.defaultShortcut)
        #expect(defaults.data(forKey: GlobalShortcuts.settingsKey) == nil)
    }

    @Test func failedSystemRegistrationPreservesOtherKeysAndSavedBinding() throws {
        _ = NSApplication.shared
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        let old = RecordedShortcut(keyCode: UInt16(kVK_F17), modifiers: [.control, .option, .command], keyLabel: "F17")
        let blocked = RecordedShortcut(keyCode: UInt16(kVK_F18), modifiers: [.control, .option, .command], keyLabel: "F18")
        try shortcuts.set(old, for: .capture)
        try shortcuts.set(nil, for: .screenshot)
        try shortcuts.start()
        defer { shortcuts.stop() }
        #expect(shortcuts.message == nil)
        var occupied: EventHotKeyRef?
        #expect(RegisterEventHotKey(UInt32(blocked.keyCode), blocked.carbonModifiers,
                                  EventHotKeyID(signature: 0x54455354, id: 77), GetApplicationEventTarget(), 0, &occupied) == noErr)
        defer { if let occupied { UnregisterEventHotKey(occupied) } }
        #expect(throws: PeerError.self) { try shortcuts.set(blocked, for: .capture) }
        #expect(shortcuts.bindings[.capture] == old)
        #expect(try GlobalShortcuts(defaults: defaults).bindings[.capture] == old)
        var probe: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(old.keyCode), old.carbonModifiers,
                                        EventHotKeyID(signature: 0x54455354, id: 78), GetApplicationEventTarget(), 0, &probe)
        defer { if let probe { UnregisterEventHotKey(probe) } }
        #expect(result != noErr)
    }

    @Test func recordingConsumesKeyWithoutExecutingActionAndEscapeCancels() throws {
        let (defaults, domain) = defaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let shortcuts = try GlobalShortcuts(defaults: defaults)
        var performed = false
        shortcuts.perform = { _ in performed = true }
        shortcuts.beginRecording(.paste)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option],
            timestamp: 0, windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_P)))
        #expect(shortcuts.handle(event) == nil)
        #expect(shortcuts.bindings[.paste]?.keyCode == UInt16(kVK_ANSI_P))
        #expect(!performed && shortcuts.recording == nil)
        shortcuts.beginRecording(.submit)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: UInt16(kVK_Escape)))
        #expect(shortcuts.handle(escape) == nil)
        #expect(shortcuts.recording == nil)
        #expect(shortcuts.bindings[.submit] == ShortcutAction.submit.defaultShortcut)
    }
}
