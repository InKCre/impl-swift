import AppKit
import CaptureCore
import SwiftUI
import ApplicationServices

@main
enum InKCreApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The configurable panel shortcut handles dismissal, including an intentionally disabled Esc.
    override func cancelOperation(_ sender: Any?) {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserInterfaceValidations {
    private var statusItem: NSStatusItem?
    private var panel: CapturePanel?
    private var mainWindow: PeerMainWindow?
    private var model: CaptureModel?
    private let regionCapture = RegionCapture()
    private var previousApplication: NSRunningApplication?

    private var canChangeCaptureContext: Bool {
        !regionCapture.isCapturing && NSApp.modalWindow == nil
            && mainWindow?.attachedSheet == nil && panel?.attachedSheet == nil
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        canChangeCaptureContext && model?.submitting != true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        do {
            let identity = Bundle.main.bundleIdentifier ?? "dev.inkcre.capture"
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identity)
            let model = try CaptureModel(directory: directory, identity: identity)
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
                case .paste: if model.editorOwner == .quick || model.pane == .capture { model.pasteMaterial() }
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
            let alert = NSAlert()
            alert.messageText = "InKCre 无法打开本地资料"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
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
        menu.addItem(withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "InKCre", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "InKCre")
        appMenu.addItem(withTitle: "关于 InKCre", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 InKCre", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "文件")
        file.addItem(withTitle: "新想法", action: #selector(newThought), keyEquivalent: "n").target = self
        file.addItem(withTitle: "快捷采集", action: #selector(showQuick), keyEquivalent: "").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file
        mainMenu.addItem(fileItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [
            ("撤销", Selector(("undo:")), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a"),
        ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        let view = NSMenu(title: "显示")
        let sidebar = view.addItem(withTitle: "显示/隐藏侧栏", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let fullscreen = view.addItem(withTitle: "进入全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view
        mainMenu.addItem(viewItem)
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windows = NSMenu(title: "窗口")
        windows.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windows.addItem(withTitle: "显示主窗口", action: #selector(showMain), keyEquivalent: "").target = self
        windows.addItem(.separator())
        windows.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windows
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windows
        NSApp.mainMenu = mainMenu
    }

    @objc private func showCapture() {
        guard canChangeCaptureContext, let model, !model.submitting else { return }
        prepareQuickCapture()
        let request = UUID()
        model.selectionRequest = request
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { showQuick(); return }
        previousApplication = application
        guard AXIsProcessTrusted() else {
            model.newThought(notice: "尚未允许辅助功能访问。可直接写下想法、明确粘贴，或在设置中开启选区采集。")
            return
        }
        let pid = application.processIdentifier
        let bundleID = application.bundleIdentifier
        Task {
            let snapshot = await Task.detached { SelectedText.read(pid: pid, applicationID: bundleID) }.value
            guard model.selectionRequest == request,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            var text = snapshot.text
            if text == nil, !snapshot.secure {
                text = await SelectedText.copyFallback(pid: pid, snapshot: snapshot) {
                    model.selectionRequest == request
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                }
            }
            guard model.selectionRequest == request,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            if let text {
                guard await Task.detached(operation: { SelectedText.isCurrent(pid: pid, snapshot: snapshot) }).value,
                      model.selectionRequest == request,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                await model.receive(
                    CapturePayload(entry: .selection, origin: snapshot.origin, materials: [Material(text: text)]),
                    request: request
                )
            } else {
                let notice = snapshot.secure
                    ? "密码或安全输入区域不会被采集。"
                    : "未取得可靠选区。可以明确复制后粘贴、框选截图，或直接写想法。"
                model.newThought(notice: notice)
            }
        }
    }
    @objc private func newThought() { guard canChangeCaptureContext else { return }; showMain(); model?.newThought() }
    @objc private func quickThought() { guard canChangeCaptureContext else { return }; prepareQuickCapture(); model?.newThought() }
    @objc private func quickPaste() { guard canChangeCaptureContext else { return }; prepareQuickCapture(); model?.pasteMaterial() }
    @objc private func quickScreenshot() { guard canChangeCaptureContext else { return }; prepareQuickCapture(); screenshot() }
    @objc private func showQueue() { guard canChangeCaptureContext else { return }; model?.pane = .queue; showMain() }
    @objc private func showSettings() { guard canChangeCaptureContext else { return }; model?.openSettings() }
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
                guard let data else { self.showCaptureSurface(); return }
                Task {
                    await model.receive(
                        CapturePayload(entry: .screenshot, materials: [Material(image: data, mimeType: "image/png")]),
                        request: request
                    )
                }
            case .failure(let error):
                if error is ScreenRecordingPermissionError {
                    model.screenCaptureNotice = error.localizedDescription
                    if owner == .main { model.pane = .capture }
                } else { model.error = error.localizedDescription }
                self.showCaptureSurface()
            }
        }
    }

    private func prepareQuickCapture() {
        if let current = NSWorkspace.shared.frontmostApplication,
           current.processIdentifier != ProcessInfo.processInfo.processIdentifier {
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

    @objc private func showMain() {
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
        if model?.editorOwner == .quick { showQuick() }
        else { showMain() }
    }

    private func hide() {
        model?.shortcuts.cancelRecording()
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        model?.editorOwner = .main
        model?.saveSoon()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { hide(); return false }
        sender.makeFirstResponder(nil)
        model?.saveSoon()
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === mainWindow, panel?.isVisible == true {
            panel?.makeFirstResponder(nil)
            panel?.orderOut(nil)
            model?.editorOwner = .main
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        NSApp.keyWindow?.makeFirstResponder(nil)
        Task {
            do {
                try await model.flush()
                model.stop()
                model.shortcuts.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                model.error = error.localizedDescription
                showCaptureSurface()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
