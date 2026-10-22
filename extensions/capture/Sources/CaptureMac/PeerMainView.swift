import SwiftUI

struct PeerMainView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: colorScheme == .dark ? BrandAssets.darkMark : BrandAssets.lightMark)
                        .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("InKCre").font(.headline)
                        Text("Mac Peer").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding()
                List(selection: Binding(get: { Optional(model.pane) }, set: {
                    guard let value = $0 else { return }
                    model.pane = value
                })) {
                    Label("采集", systemImage: "square.and.pencil").tag(CaptureModel.Pane.capture)
                    Label("记录", systemImage: "tray.full").tag(CaptureModel.Pane.queue)
                    Label("Peer 与连接", systemImage: "network").tag(CaptureModel.Pane.peer)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.connection?.name ?? "未连接信息库")
                    Text("\(model.pendingCount) 项待收入").foregroundStyle(.secondary)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding()
            }.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.pane {
                case .capture:
                    if model.editorOwner == .quick {
                        ContentUnavailableView {
                            Label("正在快捷采集", systemImage: "rectangle.on.rectangle")
                        } description: {
                            Text("当前草稿正在快捷面板中编辑。")
                        } actions: {
                            Button("在主窗口继续") { model.continueInMain() }
                        }
                    } else { CaptureEditor(model: model) }
                case .queue: CaptureRecordsView(model: model)
                case .peer: ConnectionView(model: model)
                }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.pane == .capture && model.editorOwner == .main {
                    Button("新想法", systemImage: "square.and.pencil") { model.newThought() }
                        .help("新想法（⌘N）")
                        .disabled(model.submitting)
                    Button("粘贴材料", systemImage: "doc.on.clipboard") { model.pasteMaterial() }
                        .help("粘贴材料")
                        .disabled(model.submitting)
                    Button("框选截图", systemImage: "viewfinder") { model.takeScreenshot?() }
                        .help("框选截图")
                        .disabled(model.submitting)
                }
                Button("快捷采集", systemImage: "rectangle.and.pencil.and.ellipsis") { model.showQuick?() }
                    .help("打开快捷采集面板")
            }
        }
        .modifier(CaptureAlerts(model: model, owner: .main))
    }

    private var title: String {
        switch model.pane {
        case .capture: "采集"
        case .queue: "记录"
        case .peer: "Peer 与连接"
        }
    }
}

struct QuickCaptureView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: colorScheme == .dark ? BrandAssets.darkMark : BrandAssets.lightMark)
                    .resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                Text("随手收入 InKCre").font(.headline)
                Spacer()
                Button("在主窗口继续") { model.continueInMain() }
            }.padding()
            Divider()
            if model.editorOwner == .quick { CaptureEditor(model: model, isQuickCapture: true) }
        }
        .frame(minWidth: 500, minHeight: 400)
        .modifier(CaptureAlerts(model: model, owner: .quick))
    }
}

private struct CaptureAlerts: ViewModifier {
    @ObservedObject var model: CaptureModel
    let owner: CaptureModel.EditorOwner

    private enum PresentedAlert {
        case error(String)
        case removal(CaptureModel.RemovalRequest)

        var title: String {
            switch self {
            case .error: "需要处理"
            case .removal(let request): request.title
            }
        }

        var message: String {
            switch self {
            case .error(let message): message
            case .removal(let request): request.message
            }
        }
    }

    private var presentedAlert: PresentedAlert? {
        if let error = model.error { return .error(error) }
        return model.removalRequest.map(PresentedAlert.removal)
    }

    func body(content: Content) -> some View {
        content.alert(presentedAlert?.title ?? "需要处理", isPresented: Binding(
            get: { presentedAlert != nil && model.editorOwner == owner },
            set: {
                if !$0 && model.editorOwner == owner {
                    model.error = nil
                    model.removalRequest = nil
                }
            }
        ), presenting: presentedAlert) { alert in
            switch alert {
            case .error:
                Button("知道了", role: .cancel) { model.error = nil }
            case .removal(let request):
                Button(request.actionTitle, role: .destructive) { model.confirmRemoval(request) }
                Button("取消", role: .cancel) { model.removalRequest = nil }
            }
        } message: { alert in Text(alert.message) }
    }
}
