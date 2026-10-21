import AppKit
import ApplicationServices
import Capture
import PeerCore
import SwiftUI

@MainActor
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The configurable panel shortcut handles dismissal, including an intentionally disabled Esc.
    override func cancelOperation(_ sender: Any?) {}
}

@MainActor
public final class CaptureExtension: NSObject, NativeExtension, NSWindowDelegate, NSUserInterfaceValidations {
    public let descriptor = CaptureClient.descriptor
    private let context: PeerHostContext
    public init(context: PeerHostContext) {
        self.context = context
        super.init()
    }
    private var commandItem: NSMenuItem?
    private var statusItem: NSStatusItem?
    private var panel: CapturePanel?
    private var mainWindow: PeerMainWindow?
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
        canChangeCaptureContext && model?.submitting != true
    }

    public func start() throws {
        stopping = false
        if let model {
            try model.shortcuts.start()
            configureMenu()
            model.start(restore: false)
            showMain()
            return
        }
        do {
            let model = try CaptureModel(
                directory: context.directory.appendingPathComponent("extensions/inkcre-capture"),
                identity: context.identity, connections: context.connections)
            self.model = model
            let mainWindow = PeerMainWindow(model: model)
            mainWindow.delegate = self
            self.mainWindow = mainWindow
            let panel = CapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: 570, height: 640),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.title = "随手收入 InKCre"
            panel.minSize = NSSize(width: 500, height: 450)
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
            model.takeScreenshot = { [weak self] in self?.screenshot() }
            model.shortcuts.isCaptureWindow = { [weak panel, weak mainWindow] window in
                window === panel || window === mainWindow
            }
            model.shortcuts.perform = { [weak self, weak model] action in
                guard let self, let model, self.canChangeCaptureContext else { return }
                switch action {
                case .capture: self.showCapture()
                case .screenshot: self.quickScreenshot()
                case .paste:
                    if model.editorOwner == .quick || model.pane == .capture { model.pasteMaterial() }
                case .submit: if model.editorOwner == .quick || model.pane == .capture { model.submit() }
                case .hide: if NSApp.keyWindow === self.panel { self.hide() }
                }
            }
            try model.shortcuts.start()
            if let message = model.shortcuts.message { model.error = message }
            configureMenu()
            model.start()
            showMain()
        } catch {
            model?.cancelWork()
            model?.shortcuts.stop()
            panel?.orderOut(nil)
            mainWindow?.orderOut(nil)
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
            ("Peer 与连接", #selector(showSettings)),
        ] {
            let command = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            command.target = self
            menu.addItem(command)
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        let commands = NSMenuItem(title: "采集", action: nil, keyEquivalent: "")
        let capture = NSMenu(title: "采集")
        for (title, action, key) in [
            ("新想法", #selector(newThought), "n"), ("快捷采集", #selector(showQuick), ""),
            ("采集记录", #selector(showQueue), ""), ("采集设置", #selector(showSettings), ""),
        ] {
            capture.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        commands.submenu = capture
        NSApp.mainMenu?.insertItem(commands, at: 1)
        commandItem = commands
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
            let snapshot = await Task.detached { SelectedText.read(pid: pid, applicationID: bundleID) }.value
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
                    await Task.detached(operation: { SelectedText.isCurrent(pid: pid, snapshot: snapshot) })
                        .value,
                    model.selectionRequest == request,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                else { return }
                await model.receive(
                    CapturePayload(
                        entry: .selection, origin: snapshot.origin, materials: [Material(text: text)]),
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
        model?.openSettings()
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
                            entry: .screenshot, materials: [Material(image: data, mimeType: "image/png")]),
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
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
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

    public func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === mainWindow, panel?.isVisible == true {
            panel?.makeFirstResponder(nil)
            panel?.orderOut(nil)
            model?.editorOwner = .main
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        guard let target = try await context.connections.load() else { return }
        let password = try context.credentials.read(for: target.id)
        do {
            try await PeerDatabase.shared.setEnabled(
                enabled, target: target, password: password, extension: descriptor)
        } catch {
            if case PeerError.connection = PeerDatabase.failure(error) {
                throw PeerError.connection("离线：本机开关生效，共享意图未更新。重连以信息库选择为准。")
            }
            throw PeerDatabase.failure(error)
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
        mainWindow?.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let commandItem { NSApp.mainMenu?.removeItem(commandItem) }
        commandItem = nil
        try await model.flush()
        panel = nil
        mainWindow = nil
        self.model = nil
    }
}
