import AppKit
import Capture
import Carbon.HIToolbox
import PeerCore

enum ShortcutAction: UInt32, CaseIterable, Codable, Identifiable, Sendable {
    case capture = 1
    case screenshot, paste, submit, hide
    var id: UInt32 { rawValue }
    var isGlobal: Bool { self == .capture || self == .screenshot }
    var title: String {
        switch self {
        case .capture: "随手收集"
        case .screenshot: "框选截图"
        case .paste: "粘贴材料"
        case .submit: "收入"
        case .hide: "收起面板"
        }
    }
    var defaultShortcut: RecordedShortcut {
        switch self {
        case .capture:
            RecordedShortcut(
                keyCode: UInt16(kVK_ANSI_I), modifiers: [.control, .option], keyLabel: "I")
        case .screenshot:
            RecordedShortcut(
                keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .option], keyLabel: "S")
        case .paste:
            RecordedShortcut(
                keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift], keyLabel: "V")
        case .submit:
            RecordedShortcut(keyCode: UInt16(kVK_Return), modifiers: .command, keyLabel: "↩")
        case .hide: RecordedShortcut(keyCode: UInt16(kVK_Escape), modifiers: [], keyLabel: "Esc")
        }
    }
}

struct RecordedShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifierBits: UInt
    let keyLabel: String
    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifierBits = modifiers.intersection(Self.allowedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Escape: "Esc", kVK_Tab: "⇥", kVK_Space: "空格",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
            kVK_F20,
        ]
        let label =
            special[Int(event.keyCode)]
            ?? functionKeys.firstIndex(of: Int(event.keyCode)).map { "F\($0 + 1)" }
            ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "按键 \(event.keyCode)"
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, keyLabel: label)
    }

    var modifiers: NSEvent.ModifierFlags { .init(rawValue: modifierBits) }
    var label: String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }
    var menuKeyEquivalent: String {
        let special = [
            "↩": "\r", "Esc": "\u{1b}", "⇥": "\t", "空格": " ", "⌫": "\u{8}", "⌦": "\u{7f}",
            "←": "\u{f702}", "→": "\u{f703}", "↑": "\u{f700}", "↓": "\u{f701}",
            "↖": "\u{f729}", "↘": "\u{f72b}", "⇞": "\u{f72c}", "⇟": "\u{f72d}",
        ]
        if let key = special[keyLabel] { return key }
        if keyLabel.hasPrefix("F"), let number = Int(keyLabel.dropFirst()),
            (1...20).contains(number),
            let scalar = UnicodeScalar(0xf703 + number)
        {
            return String(scalar)
        }
        return keyLabel.lowercased()
    }

    var carbonModifiers: UInt32 {
        [
            (NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey),
            (.command, cmdKey),
        ]
        .reduce(0) { $0 | (modifiers.contains($1.0) ? UInt32($1.1) : 0) }
    }
    static func == (left: Self, right: Self) -> Bool {
        left.keyCode == right.keyCode && left.modifierBits == right.modifierBits
    }
    func validate(for action: ShortcutAction) throws {
        // Preserve the app's window, navigation and text-editing commands.
        let commandKeys = [
            kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_N,
            kVK_ANSI_Comma, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Z,
        ]
        let reserved =
            modifiers == .command && commandKeys.contains(Int(keyCode))
            || modifiers == [.command, .shift] && [kVK_ANSI_Z, kVK_ANSI_W].contains(Int(keyCode))
            || modifiers == [.command, .option] && [kVK_ANSI_H, kVK_ANSI_S].contains(Int(keyCode))
            || modifiers == [.command, .control] && keyCode == kVK_ANSI_F
        guard !reserved else { throw PeerError.invalid("\(label) 是应用的标准命令，请使用其他组合。原设置未更改。") }
        let plainEscape = action == .hide && keyCode == kVK_Escape && modifierBits == 0
        guard keyCode <= 127, !keyLabel.isEmpty,
            modifierBits & ~Self.allowedModifiers.rawValue == 0,
            plainEscape || !modifiers.intersection([.command, .control, .option]).isEmpty
        else {
            throw PeerError.invalid("请同时按住 ⌘、⌃ 或 ⌥，避免影响正常输入。")
        }
    }
}
