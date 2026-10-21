import AppKit
import Carbon.HIToolbox
import CaptureCore
import Combine

@MainActor
final class GlobalShortcuts: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: RecordedShortcut]
    @Published private(set) var recording: ShortcutAction?
    @Published private(set) var message: String?
    var perform: ((ShortcutAction) -> Void)?
    var isCaptureWindow: ((NSWindow?) -> Bool)?
    private let defaults: UserDefaults
    private var keys: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    static let settingsKey = "individualShortcuts.v1"

    init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.settingsKey) {
            bindings = try JSONDecoder().decode([ShortcutAction: RecordedShortcut].self, from: data)
        } else {
            bindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
            // Preserve an existing preset, including deliberate disabling, on first upgrade.
            switch defaults.string(forKey: "shortcutPreset") {
            case "commandShift":
                for action in ShortcutAction.allCases where action.isGlobal {
                    let old = action.defaultShortcut
                    bindings[action] = RecordedShortcut(keyCode: old.keyCode, modifiers: [.command, .shift], keyLabel: old.keyLabel)
                }
            case "disabled": bindings[.capture] = nil; bindings[.screenshot] = nil
            default: break
            }
        }
        for (action, shortcut) in bindings { try validate(shortcut, for: action) }
    }

    func start() throws {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == 0x494e4b43,
                  let action = ShortcutAction(rawValue: identity.id) else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { if owner.recording == nil { owner.perform?(action) } }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw CaptureError.needsAction("无法启用快捷键事件，请重新打开 InKCre。") }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancelRecording() } }
        restoreGlobals()
    }

    func stop() {
        for key in keys.values { UnregisterEventHotKey(key) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        recording = nil
    }

    func set(_ shortcut: RecordedShortcut?, for action: ShortcutAction) throws {
        if let shortcut { try validate(shortcut, for: action) }
        var changed = bindings
        changed[action] = shortcut
        let data = try JSONEncoder().encode(changed)
        if handler != nil, recording == nil, action.isGlobal,
           shortcut != bindings[action] || keys[action] == nil {
            if let shortcut { try register(shortcut, for: action) }
            else if let old = keys.removeValue(forKey: action) { UnregisterEventHotKey(old) }
        }
        defaults.set(data, forKey: Self.settingsKey)
        bindings = changed
        message = nil
    }

    func update(_ shortcut: RecordedShortcut?, for action: ShortcutAction) {
        cancelRecording()
        do { try set(shortcut, for: action) }
        catch { message = error.localizedDescription }
    }

    func beginRecording(_ action: ShortcutAction) {
        for key in keys.values { UnregisterEventHotKey(key) }
        keys.removeAll()
        recording = action
        message = nil
    }

    func cancelRecording() {
        guard recording != nil else { return }
        recording = nil
        restoreGlobals()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        if let action = recording {
            guard !event.isARepeat else { return nil }
            let shortcut = RecordedShortcut(event: event)
            if event.keyCode == kVK_Escape, shortcut.modifierBits == 0 { cancelRecording(); return nil }
            do {
                try validate(shortcut, for: action)
                cancelRecording()
                try set(shortcut, for: action)
            } catch { message = error.localizedDescription }
            return nil
        }
        guard isCaptureWindow?(event.window) == true,
              NSApp.modalWindow == nil,
              event.window?.attachedSheet == nil,
              (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
        let modifiers = event.modifierFlags.intersection(RecordedShortcut.allowedModifiers).rawValue
        guard let action = ShortcutAction.allCases.first(where: {
            !$0.isGlobal && bindings[$0]?.keyCode == event.keyCode && bindings[$0]?.modifierBits == modifiers
        }) else { return event }
        if !event.isARepeat { perform?(action) }
        return nil
    }

    private func validate(_ shortcut: RecordedShortcut, for action: ShortcutAction) throws {
        try shortcut.validate(for: action)
        if let other = ShortcutAction.allCases.first(where: { $0 != action && bindings[$0] == shortcut }) {
            throw CaptureError.invalid("\(shortcut.label) 已用于“\(other.title)”，请换一个组合。原设置未更改。")
        }
    }

    private func register(_ shortcut: RecordedShortcut, for action: ShortcutAction) throws {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                        EventHotKeyID(signature: 0x494e4b43, id: action.rawValue),
                                        GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            throw CaptureError.needsAction("“\(action.title)”的 \(shortcut.label) 无法注册，可能已被系统或其他应用占用。请换一个组合。")
        }
        // Register the replacement first; failure must not remove the working shortcut.
        if let old = keys.updateValue(reference, forKey: action) { UnregisterEventHotKey(old) }
    }

    private func restoreGlobals() {
        guard handler != nil else { return }
        var failures: [String] = []
        for action in ShortcutAction.allCases where action.isGlobal && keys[action] == nil {
            guard let shortcut = bindings[action] else { continue }
            do { try register(shortcut, for: action) }
            catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { message = failures.joined(separator: "\n") }
    }
}
