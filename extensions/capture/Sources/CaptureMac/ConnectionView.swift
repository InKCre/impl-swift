import AppKit
import SwiftUI
@preconcurrency import ApplicationServices

struct ConnectionView: View {
    @ObservedObject var model: CaptureModel

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
                    LabeledContent("PostgreSQL") { Text("\(target.host):\(target.port)/\(target.database)").textSelection(.enabled) }
                    LabeledContent("运行角色", value: target.username)
                    if let web = target.webURL {
                        LabeledContent("Web 地址") { Text(web.absoluteString).textSelection(.enabled) }
                    }
                } else {
                    Text("连接信息库后可以收入。未连接时仍可采集、保留草稿和导出材料。")
                        .foregroundStyle(.secondary)
                }
                Button(model.connection == nil ? "连接信息库…" : "编辑连接…") {
                    model.openConnectionSettings()
                }
                if model.connection != nil {
                    Button("重新检查连接") { model.checkConnection() }.disabled(model.checkingConnection)
                }
            }
        }
        .formStyle(.grouped)
    }
}
