import AppKit
import SwiftUI
@preconcurrency import ApplicationServices

struct CaptureSettingsView: View {
    @ObservedObject var model: CaptureModel
    @State private var selectionAllowed = AXIsProcessTrusted()
    @State private var screenAllowed = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
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
        .onDisappear { model.shortcuts.cancelRecording() }
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        selectionAllowed = AXIsProcessTrusted()
        screenAllowed = CGPreflightScreenCaptureAccess()
    }
}
