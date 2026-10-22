import PeerCore
import SwiftUI

public struct PeerConnectionEditor: View {
    private let settings: ConnectionSettings
    private let credentials: CredentialStore
    private let onSaved: @MainActor (ConnectionTarget) -> Void
    private let onCancel: @MainActor () -> Void
    private let target: ConnectionTarget?
    private let saveTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var server: String
    @State private var port: String
    @State private var database: String
    @State private var username: String
    @State private var tls: ConnectionTarget.TLS
    @State private var web: String
    @State private var secret = ""
    @State private var saving = false
    @State private var issue: String?
    @FocusState private var addressFocused: Bool

    public init(
        settings: ConnectionSettings, credentials: CredentialStore, target: ConnectionTarget?,
        saveTitle: String = "保存",
        onCancel: @escaping @MainActor () -> Void = {},
        onSaved: @escaping @MainActor (ConnectionTarget) -> Void
    ) {
        self.settings = settings
        self.credentials = credentials
        self.target = target
        self.saveTitle = saveTitle
        self.onCancel = onCancel
        self.onSaved = onSaved
        _server = State(initialValue: target?.host ?? "")
        _port = State(initialValue: String(target?.port ?? 5432))
        _database = State(initialValue: target?.database ?? "inkcre")
        _username = State(initialValue: target?.username ?? "")
        _tls = State(initialValue: target?.tls ?? .require)
        _web = State(initialValue: target?.webURL?.absoluteString ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接共享信息库").font(.title2).bold()
            Form {
                TextField("PostgreSQL 主机", text: $server).focused($addressFocused)
                TextField("端口", text: $port)
                TextField("数据库", text: $database)
                TextField("运行角色", text: $username)
                Picker("TLS", selection: $tls) {
                    Text("校验证书").tag(ConnectionTarget.TLS.require)
                    Text("关闭（仅本机开发）").tag(ConnectionTarget.TLS.disable)
                }
                TextField("Web 地址（可选）", text: $web)
                SecureField("数据库密码", text: $secret)
            }.textFieldStyle(.roundedBorder).disabled(saving)
            Text("凭据保存在本机 Keychain。已有连接留空可沿用原凭据；更换库或运行角色会建立新连接，已有待办保留原目标。")
                .font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                    onCancel()
                }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "正在保存…" : saveTitle) {
                    saving = true
                    issue = nil
                    Task {
                        defer { saving = false }
                        do {
                            let saved = try await settings.saveEdited(
                                host: server, port: port, database: database, username: username, tls: tls,
                                web: web, password: secret, previous: target, credentials: credentials)
                            onSaved(saved)
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
