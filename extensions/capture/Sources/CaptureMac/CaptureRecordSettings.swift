import Capture
import PeerCore
import SwiftUI

struct CaptureRecordSettings: View {
    enum Field { case password, webAddress }
    @ObservedObject var model: CaptureModel
    let record: CaptureRecord
    let field: Field
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var saving = false
    @State private var issue: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(field == .password ? "更新这条记录的数据库密码" : "设置这条记录的 Web 地址")
                .font(.title2).bold()
            if let target = record.target {
                LabeledContent("信息库", value: "\(target.host):\(target.port)/\(target.database)")
                LabeledContent("运行角色", value: target.username)
                if field == .password {
                    LabeledContent("TLS", value: target.tls == .require ? "校验证书" : "本机开发连接")
                }
            }
            if field == .password {
                SecureField("新的数据库密码", text: $value).focused($inputFocused)
                Text("密码保存到原连接的 Keychain 项，并继续收入这条记录。数据库目标和当前使用的信息库不会改变。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Web 地址，例如 https://inkcre.example.com", text: $value).focused($inputFocused)
                Text("填写该信息库对应的 InKCre Web 地址，用于打开已收入内容。此操作不会更换当前连接。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "正在保存…" : saveTitle) {
                    saving = true
                    issue = nil
                    Task {
                        defer { saving = false }
                        do {
                            if field == .password {
                                try await model.updatePassword(value, for: record)
                                value = ""
                                dismiss()
                            } else {
                                let updated = try await model.updateWebAddress(value, for: record)
                                dismiss()
                                model.openResult(updated)
                            }
                        } catch { issue = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction).disabled(value.isEmpty)
            }
        }.padding(20).frame(width: 480).textFieldStyle(.roundedBorder)
            .disabled(saving).interactiveDismissDisabled(saving)
            .onAppear {
                if field == .webAddress { value = record.target?.webURL?.absoluteString ?? "" }
                inputFocused = true
            }
    }

    private var saveTitle: String {
        if field == .webAddress { return "保存并打开" }
        return record.state == .cancelled ? "保存并继续收入" : "保存并重试"
    }
}
