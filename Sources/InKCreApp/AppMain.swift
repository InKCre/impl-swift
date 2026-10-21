import AppKit
import CaptureMac
import PeerCore
import PeerMacUI
import SwiftUI

@main
enum InKCreApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = PeerHost()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class PeerHost: NSObject, NSApplicationDelegate {
    private let context: PeerHostContext
    private let runtime: BundledExtensionRuntime
    private var module: any NativeExtension { runtime.module }
    override init() {
        let identity = Bundle.main.bundleIdentifier ?? "dev.inkcre.capture"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(identity)
        context = PeerHostContext(identity: identity, directory: directory)
        runtime = BundledExtensionRuntime(module: CaptureExtension(context: context))
        super.init()
    }
    private var presence: Task<Void, Never>?
    private var connectionIssue: String?
    private var manager: NSWindow?
    private var toggle: NSButton?
    private var status: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            NSApp.applicationIconImage = icon
        }
        installHostMenu()
        do {
            try runtime.startIfEnabled()
        } catch { show(error) }
        presence = Task {
            while !Task.isCancelled {
                do {
                    if let target = try await context.connections.load() {
                        _ = try await PeerDatabase.shared.register(
                            target, password: context.credentials.read(for: target.id))
                    }
                    connectionIssue = nil
                } catch { connectionIssue = PeerDatabase.failure(error).localizedDescription }
                updateStatus()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        if !runtime.running { showExtensions(nil) }
    }

    private func installHostMenu() {
        let main = NSMenu()
        func addMenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        let app = addMenu("InKCre")
        app.addItem(
            withTitle: "关于 InKCre", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        app.addItem(withTitle: "设置…", action: #selector(showExtensions(_:)), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Peer 连接…", action: #selector(showConnection(_:)), keyEquivalent: "").target =
            self
        app.addItem(withTitle: "开源许可与致谢…", action: #selector(showLicenses(_:)), keyEquivalent: "").target =
            self
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏 InKCre", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(
            withTitle: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(
            withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(
            withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = addMenu("编辑")
        for (title, action, key) in [
            ("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a"),
        ] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        let view = addMenu("显示")
        view.addItem(
            withTitle: "显示/隐藏侧栏", action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s"
        ).keyEquivalentModifierMask = [.command, .control]
        view.addItem(withTitle: "进入全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        let window = addMenu("窗口")
        window.addItem(
            withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Peer 与扩展", action: #selector(showExtensions(_:)), keyEquivalent: "")
            .target = self
        window.addItem(
            withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    @objc private func showExtensions(_ sender: Any?) {
        if manager == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 250),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "InKCre 扩展"
            window.isReleasedWhenClosed = false
            let title = NSTextField(labelWithString: "随手收集 · \(module.descriptor.name)")
            title.font = .boldSystemFont(ofSize: 16)
            let version = NSTextField(
                labelWithString: "\(module.descriptor.distribution) · \(module.descriptor.version) · 随应用交付")
            version.textColor = .secondaryLabelColor
            let button = NSButton(
                checkboxWithTitle: "在此 Mac 启用", target: self, action: #selector(changeEnabled(_:)))
            let label = NSTextField(wrappingLabelWithString: "")
            let stack = NSStackView(views: [title, version, button, label])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView?.addSubview(stack)
            if let content = window.contentView {
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                    stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                    stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                ])
            }
            toggle = button
            status = label
            manager = window
            window.center()
        }
        updateStatus()
        NSApp.activate(ignoringOtherApps: true)
        manager?.makeKeyAndOrderFront(nil)
    }

    @objc private func changeEnabled(_ sender: NSButton) {
        guard !runtime.applying else { return }
        let enable = sender.state == .on
        sender.isEnabled = false
        status?.stringValue = "正在应用…"
        Task {
            defer { updateStatus() }
            do { try await runtime.setEnabled(enable) } catch { show(error) }
        }
    }

    private func updateStatus() {
        toggle?.state = runtime.enabled ? .on : .off
        toggle?.isEnabled = !runtime.applying
        status?.stringValue =
            runtime.applying
            ? "正在应用…"
            : runtime.syncIssue ?? connectionIssue ?? (runtime.running ? "本机运行中" : "已停用；本机材料与共享内容保留")
    }

    @objc private func showConnection(_ sender: Any?) {
        showExtensions(nil)
        Task {
            do {
                let target = try await context.connections.load()
                guard let manager, manager.attachedSheet == nil else { return }
                let sheet = NSWindow(
                    contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
                let close: @MainActor @Sendable () -> Void = { [weak manager, weak sheet] in
                    guard let manager, let sheet else { return }
                    manager.endSheet(sheet)
                    sheet.orderOut(nil)
                }
                let content = NSHostingView(
                    rootView: PeerConnectionEditor(
                        settings: context.connections, credentials: context.credentials,
                        target: target, onCancel: close,
                        onSaved: { [weak self] _ in
                            close()
                            guard let self else { return }
                            Task {
                                do {
                                    await self.runtime.waitUntilIdle()
                                    try await self.runtime.stop()
                                    try self.runtime.startIfEnabled()
                                    self.updateStatus()
                                } catch { self.show(error) }
                            }
                        }))
                sheet.contentView = content
                sheet.setContentSize(content.fittingSize)
                manager.beginSheet(sheet, completionHandler: { _ in })
            } catch { show(error) }
        }
    }

    @objc private func showLicenses(_ sender: Any?) {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "InKCre 扩展操作未完成"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if runtime.running { module.showMain() } else { showExtensions(nil) }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        presence?.cancel()
        Task {
            do {
                await runtime.waitUntilIdle()
                try await runtime.stop()
                await presence?.value
                await PeerDatabase.shared.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                show(error)
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
