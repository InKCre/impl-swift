import LocalFilesMac
import SwiftUI

struct PeerMainView: View {
    @ObservedObject var host: PeerHost
    var body: some View {
        NavigationSplitView(columnVisibility: $host.columnVisibility) {
            List(
                selection: Binding(
                    get: { Optional(host.page) }, set: { if let page = $0 { host.page = page } })
            ) {
                Label("采集", systemImage: "square.and.pencil").tag(PeerHost.Page.capture)
                Label("记录", systemImage: "tray.full").tag(PeerHost.Page.records)
                Label("本地文件", systemImage: "folder").tag(PeerHost.Page.files)
                Label("Peer 与连接", systemImage: "network").tag(PeerHost.Page.peer)
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                switch host.page {
                case .capture, .records: host.capture.pageView()
                case .files:
                    if host.filesRuntime.running {
                        LocalFilesView(model: host.localFiles.model).disabled(
                            host.changingConnection)
                    } else {
                        ContentUnavailableView {
                            Label("本地文件扩展已停用", systemImage: "folder")
                        } actions: {
                            Button("启用本地文件") { host.changeEnabled(true, files: true) }.disabled(
                                host.filesRuntime.applying)
                        }
                    }
                case .peer: ConnectionSettingsView(host: host)
                }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(host.page.title)
        }
    }
}
