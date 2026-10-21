import AppKit
import SwiftUI
@preconcurrency import ApplicationServices

struct ConnectionView: View {
    @ObservedObject var model: CaptureModel
    @State private var selectionAllowed = AXIsProcessTrusted()
    @State private var screenAllowed = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section("此 Mac Peer") {
                LabeledContent("当前能力", value: "收集：选区、粘贴、截图、想法")
                LabeledContent("信息库", value: model.connection?.name ?? "尚未配置")
                if let connection = model.connection {
                    LabeledContent("Peer 身份") { Text(connection.peerID.uuidString).textSelection(.enabled) }
                    if model.checkingConnection {
                        HStack { ProgressView().controlSize(.small); Text("正在检查连接…") }
                    } else if let issue = model.peerConnectionIssue {
                        Text("最近检查未通过：\(issue)").foregroundStyle(.secondary)
                    } else if let date = model.lastContactAt {
                        LabeledContent("最近检查通过") { Text(date, format: .dateTime.month().day().hour().minute().second()) }
                        Text("信息库写入连接可用").font(.caption).foregroundStyle(.secondary)
                    } else { Text("等待首次联络；已配置连接不代表在线。").foregroundStyle(.secondary) }
                }
                LabeledContent("本机待收入", value: "\(model.pendingCount) 项")
                Text("此 Mac 与其他 Peer 共享同一个信息库。关闭主窗口后仍会保留草稿、处理待办；退出 InKCre 才停止运行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("连接共享信息库") {
                if let target = model.connection {
                    LabeledContent("PostgREST 地址") { Text(target.postgrestURL.absoluteString).textSelection(.enabled) }
                    if let web = target.webURL {
                        LabeledContent("Web 地址") { Text(web.absoluteString).textSelection(.enabled) }
                    }
                } else {
                    Text("连接信息库后可以收入。未连接时仍可采集、保留草稿和导出材料。")
                        .foregroundStyle(.secondary)
                }
                Button(model.connection == nil ? "连接信息库…" : "编辑连接…") {
                    model.editingConnection = model.connection
                    model.showingConnectionEditor = true
                }
                if model.connection != nil {
                    Button("重新检查连接") { model.checkConnection() }.disabled(model.checkingConnection)
                }
            }
            Section("快捷键") {
                ShortcutSettingsView(shortcuts: model.shortcuts)
            }
            Section("系统权限") {
                LabeledContent("读取选区", value: selectionAllowed ? "已允许" : "尚未允许")
                if !selectionAllowed {
                    Button("允许读取选区（辅助功能）") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                }
                LabeledContent("屏幕录制", value: screenAllowed ? "已允许" : "尚未允许")
                if !screenAllowed {
                    Button("请求屏幕录制权限") { model.requestScreenRecordingAccess(); refreshPermissions() }
                }
                Button("打开屏幕录制权限设置") { model.openScreenRecordingSettings() }
                Text("选区与截图分别需要系统授权；输入和明确粘贴不需要这两项权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $model.showingConnectionEditor) {
            ConnectionEditor(model: model, target: model.editingConnection)
        }
        .onDisappear { model.shortcuts.cancelRecording() }
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        selectionAllowed = AXIsProcessTrusted()
        screenAllowed = CGPreflightScreenCaptureAccess()
    }
}
