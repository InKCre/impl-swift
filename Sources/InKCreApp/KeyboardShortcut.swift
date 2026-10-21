import AppKit
import Carbon.HIToolbox
import CaptureCore

enum ShortcutAction: UInt32, CaseIterable, Codable, Identifiable, Sendable {
    case capture = 1, screenshot, paste, submit, hide
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
        case .capture: RecordedShortcut(keyCode: UInt16(kVK_ANSI_I), modifiers: [.control, .option], keyLabel: "I")
        case .screenshot: RecordedShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .option], keyLabel: "S")
        case .paste: RecordedShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift], keyLabel: "V")
        case .submit: RecordedShortcut(keyCode: UInt16(kVK_Return), modifiers: .command, keyLabel: "↩")
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
        let special: [Int: String] = [kVK_Return: "↩", kVK_Escape: "Esc", kVK_Tab: "⇥", kVK_Space: "空格",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟"]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        let label = special[Int(event.keyCode)]
            ?? functionKeys.firstIndex(of: Int(event.keyCode)).map { "F\($0 + 1)" }
            ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "按键 \(event.keyCode)"
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, keyLabel: label)
    }

    var modifiers: NSEvent.ModifierFlags { .init(rawValue: modifierBits) }
    var label: String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }
    var carbonModifiers: UInt32 {
        [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
            .reduce(0) { $0 | (modifiers.contains($1.0) ? UInt32($1.1) : 0) }
    }
    static func == (left: Self, right: Self) -> Bool {
        left.keyCode == right.keyCode && left.modifierBits == right.modifierBits
    }
    func validate(for action: ShortcutAction) throws {
        let plainEscape = action == .hide && keyCode == kVK_Escape && modifierBits == 0
        guard keyCode <= 127, !keyLabel.isEmpty,
              modifierBits & ~Self.allowedModifiers.rawValue == 0,
              plainEscape || !modifiers.intersection([.command, .control, .option]).isEmpty else {
            throw CaptureError.invalid("请同时按住 ⌘、⌃ 或 ⌥，避免影响正常输入。")
        }
    }
}
