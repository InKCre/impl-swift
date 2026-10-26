import AppKit
import PeerCore
import SwiftUI

@MainActor
final class PeerSettingsWindow: NSWindow, NSWindowDelegate {
    private weak var host: PeerHost?
    enum Pane: Int { case connection, extensions, capture }
    private let tabs = NSTabViewController()

    init(host: PeerHost) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.host = host
        delegate = self
        title = "InKCre 设置"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 600, height: 540)
        tabs.tabStyle = .toolbar
        let connection = NSTabViewItem(
            viewController: NSHostingController(rootView: ConnectionSettingsView(host: host)))
        connection.label = "连接"
        connection.image = NSImage(systemSymbolName: "network", accessibilityDescription: "连接")
        let extensions = NSTabViewItem(
            viewController: NSHostingController(rootView: ExtensionSettingsView(host: host)))
        extensions.label = "扩展"
        extensions.image = NSImage(
            systemSymbolName: "puzzlepiece.extension", accessibilityDescription: "扩展")
        let capture = NSTabViewItem(viewController: captureController(host: host))
        capture.label = "采集"
        capture.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "采集")
        tabs.tabViewItems = [connection, extensions, capture]
        contentViewController = tabs
        center()
    }

    func windowWillClose(_ notification: Notification) { host?.capture.finishEditingSettings() }
    func windowDidResignKey(_ notification: Notification) { host?.capture.finishEditingSettings() }

    func select(_ pane: Pane) { tabs.selectedTabViewItemIndex = pane.rawValue }

    func refreshCaptureSettings(host: PeerHost) {
        replaceCaptureSettings(with: captureController(host: host))
    }

    func replaceCaptureSettings(with controller: NSViewController) {
        let selected = tabs.selectedTabViewItemIndex
        let previous = tabs.tabViewItems[Pane.capture.rawValue]
        let replacement = NSTabViewItem(viewController: controller)
        replacement.label = previous.label
        replacement.image = previous.image
        // NSTabViewController must update containment when replacing a hosted pane.
        tabs.removeTabViewItem(previous)
        tabs.insertTabViewItem(replacement, at: Pane.capture.rawValue)
        tabs.selectedTabViewItemIndex = selected
    }

    private func captureController(host: PeerHost) -> NSViewController {
        host.capture.makeSettingsViewController()
            ?? NSHostingController(
                rootView:
                    ContentUnavailableView(
                        "采集扩展已停用", systemImage: "viewfinder",
                        description: Text("在“扩展”中启用后，可设置采集快捷键和系统权限。")))
    }
}

struct ConnectionSettingsView: View {
    @ObservedObject var host: PeerHost
    var body: some View {
        Form {
            Section("连接") {
                if !host.savedConnections.isEmpty {
                    Picker(
                        "当前连接",
                        selection: Binding<UUID?>(
                            get: { host.connection?.id },
                            set: { id in if let id { Task { await host.selectConnection(id) } } }
                        )
                    ) {
                        ForEach(host.savedConnections) { target in
                            Text(target.name).tag(Optional(target.id))
                        }
                    }
                }
                HStack {
                    Button("添加连接…") { host.editConnection(nil) }
                    if let target = host.connection {
                        Button("编辑连接…") { host.editConnection(target) }
                    }
                }
            }.disabled(host.changingConnection)
            if let target = host.connection {
                Section("共享信息库") {
                    LabeledContent(
                        "PostgreSQL", value: "\(target.host):\(target.port)/\(target.database)")
                    LabeledContent("运行角色", value: target.username)
                    LabeledContent("Peer", value: target.peerID.uuidString.lowercased())
                        .textSelection(.enabled)
                    if let web = target.webURL {
                        LabeledContent("Web 地址", value: web.absoluteString)
                    }
                }
            }
            if let issue = host.connectionIssue {
                Text(issue).foregroundStyle(.red).textSelection(.enabled)
            }
        }.formStyle(.grouped)
    }
}

private struct ExtensionSettingsView: View {
    @ObservedObject var host: PeerHost
    @State private var selecting = false
    @State private var issue: String?
    @State private var result: String?
    var body: some View {
        Form {
            Section("随手收集") {
                Toggle(
                    "在此 Mac 启用",
                    isOn: Binding(get: { host.runtime.enabled }, set: { host.changeEnabled($0) })
                )
                .disabled(host.runtime.applying)
                Text(
                    host.runtime.applying
                        ? "正在应用…"
                        : (host.runtime.running
                            ? "本机运行中"
                            : host.runtime.enabled ? "尚未启动" : "已停用；本机材料与共享内容保留")
                )
                .foregroundStyle(.secondary)
                LabeledContent("版本", value: host.capture.descriptor.version)
                participation(host.capture.descriptor)
            }
            Section("本地文件") {
                Toggle(
                    "在此 Mac 启用",
                    isOn: Binding(
                        get: { host.filesRuntime.enabled },
                        set: { host.changeEnabled($0, files: true) })
                )
                .disabled(host.filesRuntime.applying)
                Text(
                    host.filesRuntime.applying
                        ? "正在应用…"
                        : (host.filesRuntime.running
                            ? "本机运行中" : host.filesRuntime.enabled ? "尚未启动" : "已停用")
                )
                .foregroundStyle(.secondary)
                LabeledContent("版本", value: host.localFiles.descriptor.version)
                participation(host.localFiles.descriptor)
            }
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            if let result { Text(result).textSelection(.enabled) }
        }.formStyle(.grouped)
    }

    @ViewBuilder private func participation(_ descriptor: NativeExtensionDescriptor) -> some View {
        if let target = host.connection {
            Button("在「\(target.name)」启用本机版本") {
                selecting = true
                issue = nil
                result = nil
                Task {
                    defer { selecting = false }
                    do {
                        try await host.useBundledVersion(descriptor, target: target)
                        result = "已在「\(target.name)」启用 \(descriptor.name) \(descriptor.version)"
                    } catch {
                        issue = error.localizedDescription
                    }
                }
            }
            .disabled(selecting || host.changingConnection)
        }
    }
}
