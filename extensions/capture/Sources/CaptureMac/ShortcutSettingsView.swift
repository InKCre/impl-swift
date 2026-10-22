import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var shortcuts: GlobalShortcuts

    var body: some View {
        ForEach(ShortcutAction.allCases) { action in
            HStack {
                VStack(alignment: .leading) {
                    Text(action.title)
                    Text(action.isGlobal ? "全局" : action == .hide ? "快捷面板" : "采集编辑器")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(shortcuts.recording == action ? "按下快捷键…" : shortcuts.bindings[action]?.label ?? "未设置") {
                    shortcuts.beginRecording(action)
                }
                .frame(minWidth: 110)
                .accessibilityLabel("\(action.title)快捷键")
                .accessibilityValue(shortcuts.recording == action ? "正在录入" : shortcuts.bindings[action]?.label ?? "未设置")
                Button("清除") { shortcuts.update(nil, for: action) }
                    .disabled(shortcuts.bindings[action] == nil)
                    .accessibilityLabel("清除\(action.title)快捷键")
                Button("默认") { shortcuts.update(action.defaultShortcut, for: action) }
                    .accessibilityLabel("恢复\(action.title)默认快捷键")
            }
        }
        Text("点击后按下组合键；Esc 取消录入。每项立即生效并保留。")
            .font(.caption).foregroundStyle(.secondary)
        if let message = shortcuts.message { Text(message).font(.callout).foregroundStyle(.red) }
    }
}
