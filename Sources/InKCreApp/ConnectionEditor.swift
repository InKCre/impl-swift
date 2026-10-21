import CaptureCore
import SwiftUI

struct ConnectionEditor: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @State private var server: String
    @State private var web: String
    @State private var secret = ""
    @State private var saving = false
    @State private var issue: String?
    @FocusState private var addressFocused: Bool

    init(model: CaptureModel, target: ConnectionTarget?) {
        self.model = model
        _server = State(initialValue: target?.postgrestURL.absoluteString ?? "")
        _web = State(initialValue: target?.webURL?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接共享信息库").font(.title2).bold()
            Form {
                TextField("PostgREST 地址", text: $server).focused($addressFocused)
                TextField("Web 地址（可选）", text: $web)
                SecureField("部署签名凭据", text: $secret)
            }.textFieldStyle(.roundedBorder).disabled(saving)
            Text("凭据保存在本机 Keychain。已有连接留空可沿用原凭据；更换地址会建立新连接，旧待办仍属于原信息库。")
                .font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "正在保存…" : "保存并检查") {
                    saving = true
                    issue = nil
                    Task {
                        defer { saving = false }
                        do {
                            try await model.saveConnection(server: server, web: web, secret: secret)
                            secret = ""
                            dismiss()
                        } catch { issue = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(saving || server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 520)
            .interactiveDismissDisabled(saving)
            .onAppear { addressFocused = true }
    }
}
