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

private struct ConnectionSettingsView: View {
    @ObservedObject var host: PeerHost
    var body: some View {
        Form {
            Section("共享信息库") {
                if let target = host.connection {
                    LabeledContent("信息库", value: target.name)
                    LabeledContent(
                        "PostgreSQL", value: "\(target.host):\(target.port)/\(target.database)")
                    LabeledContent("运行角色", value: target.username)
                    if let web = target.webURL {
                        LabeledContent("Web 地址", value: web.absoluteString)
                    }
                } else {
                    Text("连接信息库后可以收入。未连接时仍可采集、保留草稿和导出材料。")
                        .foregroundStyle(.secondary)
                }
                Button(host.connection == nil ? "连接信息库…" : "编辑连接…") {
                    host.editConnection(host.connection)
                }
                if let issue = host.connectionIssue {
                    Text(issue).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Text("连接由此 Mac 的各扩展共享；密码保存在系统钥匙串中。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

private struct ExtensionSettingsView: View {
    @ObservedObject var host: PeerHost
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
                        : host.runtime.syncIssue
                            ?? (host.runtime.running
                                ? "本机运行中"
                                : host.runtime.enabled ? "尚未启动；请停用后重新启用。" : "已停用；本机材料与共享内容保留")
                )
                .foregroundStyle(.secondary)
                LabeledContent("版本", value: host.capture.descriptor.version)
                Text("随应用交付，提供选区、粘贴、截图与想法采集。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
