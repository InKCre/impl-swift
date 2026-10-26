import AppKit
import CaptureMac
import LocalFilesMac
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
final class PeerHost: NSObject, NSApplicationDelegate, ObservableObject, NSUserInterfaceValidations
{
    let context: PeerHostContext
    let runtime: BundledExtensionRuntime
    let capture: CaptureExtension
    let localFiles: LocalFilesExtension
    let filesRuntime: BundledExtensionRuntime
    enum Page: Hashable {
        case capture, records, files, peer
        var title: String {
            switch self {
            case .capture: "采集"
            case .records: "记录"
            case .files: "本地文件"
            case .peer: "Peer 与连接"
            }
        }
    }
    @Published var columnVisibility = NavigationSplitViewVisibility.all
    @Published var page = Page.capture {
        didSet {
            capture.showingCapturePage = page == .capture || page == .records
            if page == .capture { capture.selectPage(.capture) }
            if page == .records { capture.selectPage(.queue) }
        }
    }
    private(set) var mainWindow: PeerMainWindow?
    override convenience init() {
        let identity = Bundle.main.bundleIdentifier ?? "dev.inkcre.capture"
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(identity)
        self.init(context: PeerHostContext(identity: identity, directory: directory))
    }

    init(context: PeerHostContext, defaults: UserDefaults = .standard) {
        self.context = context
        capture = CaptureExtension(context: context)
        runtime = BundledExtensionRuntime(module: capture, defaults: defaults)
        localFiles = LocalFilesExtension(context: context)
        filesRuntime = BundledExtensionRuntime(module: localFiles, defaults: defaults)
        super.init()
        capture.presentMain = { [weak self] in self?.showMain() }
        capture.navigate = { [weak self] page in
            self?.page = page == .capture ? .capture : .records
        }
        localFiles.present = { [weak self] in
            self?.page = .files
            self?.showMain()
        }
        localFiles.model.editConnection = { [weak self] in self?.editConnection(self?.connection) }
        capture.showPreferences = { [weak self] in self?.showSettings(.capture) }
        capture.editConnection = { [weak self] target, completion in
            self?.editConnection(target, onFinished: completion)
        }
    }
    private var presence: Task<Void, Never>?
    @Published var connectionIssue: String?
    @Published var connection: ConnectionTarget?
    @Published var savedConnections: [ConnectionTarget] = []
    @Published var changingConnection = false
    private var manager: PeerSettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            NSApp.applicationIconImage = icon
        }
        installHostMenu()
        makeMainWindow()
        do {
            try runtime.startIfEnabled()
            capture.selectPage(page == .records ? .queue : .capture)
        } catch { show(error) }
        do { try filesRuntime.startIfEnabled() } catch { show(error) }
        showMain()
        presence = Task {
            while !Task.isCancelled {
                do {
                    try await reloadConnections()
                    if let target = connection {
                        try await PeerDatabase.shared.register(
                            target, password: context.credentials.read(for: target.id))
                    }
                    connectionIssue = nil
                } catch { connectionIssue = PeerDatabase.failure(error).localizedDescription }
                let failures = await PeerDatabase.shared.renewLeases()
                if let id = connection?.id, let failure = failures[id] { connectionIssue = failure }
                updateStatus()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    func makeMainWindow() {
        guard mainWindow == nil else { return }
        mainWindow = PeerMainWindow(host: self)
        capture.mainWindow = mainWindow
    }

    @objc func showMain() {
        makeMainWindow()
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func installHostMenu() {
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
            withTitle: "关于 InKCre",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        app.addItem(withTitle: "设置…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
            .target = self
        app.addItem(withTitle: "Peer 连接…", action: #selector(showConnection(_:)), keyEquivalent: "")
            .target =
            self
        app.addItem(withTitle: "开源许可与致谢…", action: #selector(showLicenses(_:)), keyEquivalent: "")
            .target =
            self
        app.addItem(.separator())
        app.addItem(
            withTitle: "隐藏 InKCre", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(
            withTitle: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(
            withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(
            withTitle: "退出 InKCre", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
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
        ).keyEquivalentModifierMask = [.command, .option]
        view.addItem(
            withTitle: "进入全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"
        )
        .keyEquivalentModifierMask = [.command, .control]
        let window = addMenu("窗口")
        window.addItem(withTitle: "显示主窗口", action: #selector(showMain), keyEquivalent: "0").target =
            self
        window.addItem(
            withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"
        )
        window.addItem(
            withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(
            withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "扩展设置…", action: #selector(showExtensions(_:)), keyEquivalent: "")
            .target = self
        window.addItem(
            withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    @objc private func showPreferences(_ sender: Any?) { showSettings() }
    @objc private func showExtensions(_ sender: Any?) { showSettings(.extensions) }
    @objc private func showConnection(_ sender: Any?) { showSettings(.connection) }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if [
            #selector(showPreferences(_:)), #selector(showConnection(_:)),
            #selector(showExtensions(_:)),
        ].contains(item.action) {
            return manager?.attachedSheet != nil || capture.canOpenSettings
        }
        return true
    }

    private func showSettings(_ pane: PeerSettingsWindow.Pane? = nil) {
        guard manager?.attachedSheet != nil || capture.canOpenSettings else { return }
        capture.prepareForSettings()
        if manager == nil { manager = PeerSettingsWindow(host: self) }
        if let pane, manager?.attachedSheet == nil { manager?.select(pane) }
        NSApp.activate(ignoringOtherApps: true)
        manager?.makeKeyAndOrderFront(nil)
        Task {
            do { try await reloadConnections() } catch {
                connectionIssue = error.localizedDescription
            }
        }
    }

    func changeEnabled(_ enable: Bool, files: Bool = false) {
        let runtime = files ? filesRuntime : runtime
        guard !runtime.applying else { return }
        Task {
            objectWillChange.send()
            do { try await runtime.setEnabled(enable) } catch { show(error) }
            capture.selectPage(page == .records ? .queue : .capture)
            manager?.refreshCaptureSettings(host: self)
            updateStatus()
        }
    }

    func useBundledVersion(_ descriptor: NativeExtensionDescriptor, target: ConnectionTarget)
        async throws
    {
        let connection = try await context.connections.resolve(target)
        do {
            try await PeerDatabase.shared.useBundledVersion(
                descriptor, target: connection,
                password: context.credentials.read(for: connection.id))
            await localFiles.model.refresh()
        } catch { throw PeerDatabase.failure(error) }
    }

    private func updateStatus() { objectWillChange.send() }

    func reloadConnections() async throws {
        let saved = try await context.connections.loadAll()
        savedConnections = saved.connections
        connection = saved.current
    }

    func selectConnection(_ id: UUID) async {
        guard !changingConnection, capture.canOpenSettings else { return }
        changingConnection = true
        defer { changingConnection = false }
        do {
            let target = try await context.connections.select(id)
            await connectionDidChange(target)
        } catch { connectionIssue = error.localizedDescription }
    }

    private func connectionDidChange(_ target: ConnectionTarget) async {
        connection = target
        connectionIssue = nil
        capture.connectionDidChange(target)
        do { try await reloadConnections() } catch { connectionIssue = error.localizedDescription }
        await localFiles.model.connectionDidChange(target)
    }

    func editConnection(_ target: ConnectionTarget?, onFinished: (@MainActor () -> Void)? = nil) {
        guard !changingConnection, capture.canOpenSettings else { return }
        showSettings(.connection)
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
                target: target, saveTitle: onFinished == nil ? "保存" : "保存并返回采集", onCancel: close,
                onSaved: { [weak self] target in
                    self?.changingConnection = true
                    Task {
                        await self?.connectionDidChange(target)
                        self?.changingConnection = false
                        close()
                    }
                }))
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
        manager.beginSheet(sheet) { [weak manager] _ in
            if let onFinished {
                manager?.orderOut(nil)
                onFinished()
            }
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        showMain()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func stop(_ runtime: BundledExtensionRuntime) async throws {
        await runtime.waitUntilIdle()
        try await runtime.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        presence?.cancel()
        Task {
            do {
                async let captureStopped: Void = stop(runtime)
                async let filesStopped: Void = stop(filesRuntime)
                try await captureStopped
                try await filesStopped
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
