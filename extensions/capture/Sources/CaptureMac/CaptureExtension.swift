import AppKit
import ApplicationServices
import Capture
import Combine
import PeerCore
import SwiftUI

public enum CapturePage: Hashable { case capture, queue }

@MainActor
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The configurable panel shortcut handles dismissal, including an intentionally disabled Esc.
    override func cancelOperation(_ sender: Any?) {}
}

@MainActor
public final class CaptureExtension: NSObject, NativeExtension, NSWindowDelegate,
    NSUserInterfaceValidations
{
    public let descriptor = CaptureClient.descriptor
    private let context: PeerHostContext
    public init(context: PeerHostContext) {
        self.context = context
        super.init()
    }
    public var showPreferences: (() -> Void)?
    public var editConnection: ((ConnectionTarget?, (@MainActor () -> Void)?) -> Void)?

    public func makeSettingsViewController() -> NSViewController? {
        model.map { NSHostingController(rootView: CaptureSettingsView(model: $0)) }
    }

    public func connectionDidChange(_ target: ConnectionTarget) { model?.connection = target }

    public var canOpenSettings: Bool {
        model == nil || (canChangeCaptureContext && model?.submitting != true)
    }

    public func finishEditingSettings() { model?.shortcuts.cancelRecording() }

    public func prepareForSettings() {
        model?.shortcuts.cancelRecording()
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        model?.editorOwner = .main
        model?.saveSoon()
    }

    private var commandItem: NSMenuItem?
    private var statusItem: NSStatusItem?
    private var shortcutObservation: AnyCancellable?
    private var panel: CapturePanel?
    public weak var mainWindow: NSWindow?
    public var presentMain: (() -> Void)?
    public var navigate: ((CapturePage) -> Void)?
    public var showingCapturePage = true

    public func selectPage(_ page: CapturePage) { model?.pane = page }
    public func pageView() -> AnyView {
        if let model { return AnyView(CapturePageView(model: model)) }
        return AnyView(ContentUnavailableView("采集扩展已停用", systemImage: "viewfinder"))
    }
    private var model: CaptureModel?
    private let regionCapture = RegionCapture()
    private var selectionTask: Task<Void, Never>?
    private var stopping = false
    private var previousApplication: NSRunningApplication?

    private var canChangeCaptureContext: Bool {
        !stopping && model != nil && !regionCapture.isCapturing && NSApp.modalWindow == nil
            && !NSApp.windows.contains(where: { $0.attachedSheet != nil })
    }

    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard canChangeCaptureContext, let model, !model.submitting,
            model.shortcuts.recording == nil
        else { return false }
        if item.action == #selector(performShortcut(_:)), let item = item as? NSMenuItem,
            let action = ShortcutAction(rawValue: UInt32(item.tag))
        {
            return canPerform(action, in: NSApp.keyWindow)
        }
        return model.error == nil && model.removalRequest == nil
    }

    public func start() throws {
        stopping = false
        if let model {
            try model.shortcuts.start()
            configureMenu()
            model.start(restore: false)
            return
        }
        do {
            let model = try CaptureModel(
                directory: context.directory.appendingPathComponent("extensions/inkcre-capture"),
                identity: context.identity, connections: context.connections)
            self.model = model
            let panel = CapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: 570, height: 640),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.title = "随手收入 InKCre"
            panel.contentMinSize = NSSize(width: 500, height: 500)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: QuickCaptureView(model: model))
            panel.center()
            self.panel = panel
            model.presentEditor = { [weak self] in self?.showCaptureSurface() }
            model.dismissQuickCapture = { [weak self] in self?.hide() }
            model.showMain = { [weak self] in self?.showMain() }
            model.showQuick = { [weak self] in self?.showQuick() }
            model.editConnection = { [weak self] target, completion in
                self?.editConnection?(target, completion)
            }
            model.takeScreenshot = { [weak self] in self?.screenshot() }
            model.shortcuts.isCaptureWindow = { [weak panel, weak mainWindow] window in
                window === panel || window === mainWindow
            }
            model.shortcuts.canPerform = { [weak self] action, window in
                self?.canPerform(action, in: window) == true
            }
            model.shortcuts.perform = { [weak self, weak model] action in
                guard let self, let model else { return }
                switch action {
                case .capture: self.showCapture()
                case .screenshot: self.quickScreenshot()
                case .paste: model.pasteMaterial()
                case .submit: model.submit()
                case .hide: self.hide()
                }
            }
            try model.shortcuts.start()
            if let message = model.shortcuts.message { model.captureNotice = message }
            configureMenu()
            model.start()
        } catch {
            model?.cancelWork()
            model?.shortcuts.stop()
            panel?.orderOut(nil)
            throw error
        }
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = BrandAssets.menuIcon
        let menu = NSMenu()
        for (title, selector) in [
            ("显示主窗口", #selector(showMain)),
            ("随手收集", #selector(showCapture)),
            ("写下想法", #selector(quickThought)),
            ("粘贴材料", #selector(quickPaste)),
            ("框选截图", #selector(quickScreenshot)),
            ("采集记录", #selector(showQueue)),
            ("采集设置…", #selector(showSettings)),
        ] {
            let command = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            command.target = self
            menu.addItem(command)
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        let commands = NSMenuItem(title: "采集", action: nil, keyEquivalent: "")
        let capture = NSMenu(title: "采集")
        capture.addItem(withTitle: "新想法", action: #selector(newThought), keyEquivalent: "n")
            .target = self
        for action in ShortcutAction.allCases {
            let item = NSMenuItem(
                title: action.title, action: #selector(performShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(action.rawValue)
            capture.addItem(item)
        }
        capture.addItem(.separator())
        capture.addItem(withTitle: "采集记录", action: #selector(showQueue), keyEquivalent: "").target =
            self
        capture.addItem(withTitle: "采集设置…", action: #selector(showSettings), keyEquivalent: "")
            .target = self
        commands.submenu = capture
        NSApp.mainMenu?.insertItem(commands, at: 1)
        commandItem = commands
        shortcutObservation = model?.shortcuts.$bindings.sink { bindings in
            for item in capture.items {
                guard let action = ShortcutAction(rawValue: UInt32(item.tag)) else { continue }
                item.keyEquivalent = bindings[action]?.menuKeyEquivalent ?? ""
                item.keyEquivalentModifierMask = bindings[action]?.modifiers ?? []
            }
        }
    }

    private func canPerform(_ action: ShortcutAction, in window: NSWindow?) -> Bool {
        guard canChangeCaptureContext, let model, model.shortcuts.recording == nil else {
            return false
        }
        let quick = window === panel && model.editorOwner == .quick
        let editor =
            quick
            || (showingCapturePage && window === mainWindow && model.pane == .capture
                && model.editorOwner == .main)
        return model.canPerform(action, isEditor: editor, isQuickPanel: quick)
    }

    @objc private func performShortcut(_ sender: NSMenuItem) {
        guard let action = ShortcutAction(rawValue: UInt32(sender.tag)) else { return }
        model?.shortcuts.execute(action, in: NSApp.keyWindow)
    }

    @objc private func showCapture() {
        guard canChangeCaptureContext, let model, !model.submitting else { return }
        prepareQuickCapture()
        let request = UUID()
        model.selectionRequest = request
        guard let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            showQuick()
            return
        }
        previousApplication = application
        guard AXIsProcessTrusted() else {
            model.newThought(notice: "尚未允许辅助功能访问。可直接写下想法、明确粘贴，或在设置中开启选区采集。")
            return
        }
        let pid = application.processIdentifier
        let bundleID = application.bundleIdentifier
        selectionTask?.cancel()
        selectionTask = Task {
            let snapshot = await Task.detached {
                SelectedText.read(pid: pid, applicationID: bundleID)
            }.value
            guard model.selectionRequest == request,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }
            var text = snapshot.text
            if text == nil, !snapshot.secure {
                text = await SelectedText.copyFallback(pid: pid, snapshot: snapshot) {
                    model.selectionRequest == request
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                }
            }
            guard model.selectionRequest == request,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }
            if let text {
                guard
                    await Task.detached(operation: {
                        SelectedText.isCurrent(pid: pid, snapshot: snapshot)
                    })
                    .value,
                    model.selectionRequest == request,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                else { return }
                await model.receive(
                    CapturePayload(
                        entry: .selection, origin: snapshot.origin,
                        materials: [Material(text: text)]),
                    request: request
                )
            } else {
                let notice =
                    snapshot.secure
                    ? "密码或安全输入区域不会被采集。"
                    : "未取得可靠选区。可以明确复制后粘贴、框选截图，或直接写想法。"
                model.newThought(notice: notice)
            }
        }
    }
    @objc private func newThought() {
        guard canChangeCaptureContext else { return }
        showMain()
        model?.newThought()
    }
    @objc private func quickThought() {
        guard canChangeCaptureContext else { return }
        prepareQuickCapture()
        model?.newThought()
    }
    @objc private func quickPaste() {
        guard canChangeCaptureContext else { return }
        prepareQuickCapture()
        model?.pasteMaterial()
    }
    @objc private func quickScreenshot() {
        guard canChangeCaptureContext else { return }
        prepareQuickCapture()
        screenshot()
    }
    @objc private func showQueue() {
        guard canChangeCaptureContext else { return }
        model?.pane = .queue
        showMain()
    }
    @objc private func showSettings() {
        guard canChangeCaptureContext else { return }
        showPreferences?()
    }
    @objc private func screenshot() {
        guard canChangeCaptureContext, let model, !model.submitting else { return }
        model.selectionRequest = UUID()
        let request = model.selectionRequest
        let owner = model.editorOwner
        let restoreMain = mainWindow?.isVisible == true
        model.screenCaptureNotice = nil
        panel?.orderOut(nil)
        mainWindow?.orderOut(nil)
        regionCapture.begin { [weak self] result in
            guard let self else { return }
            model.editorOwner = owner
            if restoreMain { self.mainWindow?.orderBack(nil) }
            switch result {
            case .success(let data):
                guard let data else {
                    self.showCaptureSurface()
                    return
                }
                model.perform {
                    await model.receive(
                        CapturePayload(
                            entry: .screenshot,
                            materials: [Material(image: data, mimeType: "image/png")]),
                        request: request
                    )
                }
            case .failure(let error):
                if error is ScreenRecordingPermissionError {
                    model.screenCaptureNotice = error.localizedDescription
                    if owner == .main { model.pane = .capture }
                } else {
                    model.error = error.localizedDescription
                }
                self.showCaptureSurface()
            }
        }
    }

    private func prepareQuickCapture() {
        if let current = NSWorkspace.shared.frontmostApplication,
            current.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            previousApplication = current
        }
        model?.shortcuts.cancelRecording()
        mainWindow?.makeFirstResponder(nil)
        model?.editorOwner = .quick
    }

    @objc private func showQuick() {
        guard canChangeCaptureContext else { return }
        prepareQuickCapture()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc public func showMain() {
        guard !regionCapture.isCapturing else { return }
        if mainWindow?.attachedSheet != nil || NSApp.modalWindow != nil {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            return
        }
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        model?.editorOwner = .main
        if let model { navigate?(model.pane) }
        presentMain?()
    }

    private func showCaptureSurface() {
        if model?.editorOwner == .quick { showQuick() } else { showMain() }
    }

    private func hide() {
        model?.shortcuts.cancelRecording()
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        model?.editorOwner = .main
        model?.saveSoon()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        {
            previousApplication?.activate()
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel {
            hide()
            return false
        }
        sender.makeFirstResponder(nil)
        model?.saveSoon()
        return true
    }

    public func mainWindowBecameKey() {
        if panel?.isVisible == true {
            panel?.makeFirstResponder(nil)
            panel?.orderOut(nil)
            model?.editorOwner = .main
        }
    }

    public func stop() async throws {
        guard let model else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        stopping = true
        model.cancelWork()
        model.shortcuts.stop()
        selectionTask?.cancel()
        await regionCapture.stop()
        await selectionTask?.value
        selectionTask = nil
        await model.stop()
        panel?.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let commandItem { NSApp.mainMenu?.removeItem(commandItem) }
        commandItem = nil
        shortcutObservation = nil
        try await model.flush()
        panel = nil
        self.model = nil
    }
}
