import LocalFiles
import SwiftUI

public struct LocalFilesView: View {
    @ObservedObject var model: LocalFilesModel
    public init(model: LocalFilesModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            if let issue = model.issue {
                HStack(alignment: .top) {
                    Label(issue, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                    Spacer()
                    Button("重试") { Task { await model.refresh() } }.disabled(model.loading)
                }.padding().background(.quaternary)
            }
            if !model.running {
                empty("本地文件扩展已停用", symbol: "folder")
            } else if model.loading && model.sources.isEmpty {
                ProgressView("正在读取目录…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.target == nil {
                ContentUnavailableView {
                    Label("未连接信息库", systemImage: "network")
                } actions: {
                    Button("连接信息库…") { model.editConnection?() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.sources.isEmpty {
                ContentUnavailableView {
                    Label("尚未添加目录", systemImage: "folder.badge.plus")
                } actions: {
                    Button("添加目录…") { model.chooseDirectory() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                directoryHeader
                Divider()
                VSplitView {
                    fileList.frame(minHeight: 150, maxHeight: .infinity)
                    if let file = model.file {
                        FileDetail(
                            record: file, text: model.selectedText, loading: model.loadingText,
                            issue: model.textIssue, retry: { model.loadText() },
                            open: { model.openOriginal(file) },
                            reveal: { model.openOriginal(file, reveal: true) }
                        )
                        .frame(minHeight: 180, idealHeight: 280, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                if let source = model.source {
                    Button(
                        source.config.enabled ? "暂停监视" : "恢复监视",
                        systemImage: source.config.enabled ? "pause" : "play"
                    ) { model.toggle(source) }
                    .help(source.config.enabled ? "暂停监视" : "恢复监视")
                    Button("重新扫描", systemImage: "arrow.clockwise") { model.rescan(source) }
                        .help("重新扫描，包括失败文件")
                        .disabled(
                            !source.config.enabled || model.isScanning(source)
                                || !model.hasAccess(source))
                    Menu {
                        Button("重新选择目录…") { model.chooseDirectory(restoring: source) }
                        Button("移除目录…", role: .destructive) { model.removal = source }
                    } label: {
                        Label("目录操作", systemImage: "ellipsis.circle")
                    }
                }
                Button("添加目录…", systemImage: "folder.badge.plus") { model.chooseDirectory() }.help(
                    "添加目录"
                )
                .disabled(!model.running)
            }
        }
        .disabled(model.working)
        .alert(
            "移除这个目录？",
            isPresented: Binding(
                get: { model.removal != nil }, set: { if !$0 { model.removal = nil } }),
            presenting: model.removal
        ) { source in
            Button("移除目录", role: .destructive) { model.remove(source) }
            Button("取消", role: .cancel) { model.removal = nil }
        } message: { source in
            Text("停止监视 \(source.config.path)。已收入资料保留。")
        }
    }

    private var directoryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("目录", selection: $model.selectedSource) {
                ForEach(model.sources) { source in
                    Text(source.config.path).help(source.config.path).tag(Optional(source.id))
                }
            }.labelsHidden().accessibilityLabel("监视目录").frame(
                maxWidth: .infinity, alignment: .leading)
            if let source = model.source {
                HStack {
                    if model.isScanning(source) { ProgressView().controlSize(.small) }
                    Text(model.status(source)).lineLimit(2).help(model.status(source))
                    Spacer(minLength: 12)
                    if let date = source.state.scanned_at, !model.isScanning(source) {
                        Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(
                            .secondary
                        )
                        .help("最近完整扫描")
                    }
                    if !model.hasAccess(source) {
                        Button("选择目录…") { model.chooseDirectory(restoring: source) }
                    }
                }.font(.callout)
            }
        }.padding()
    }

    @ViewBuilder private var fileList: some View {
        if model.records.isEmpty {
            empty(model.source.map(model.isScanning) == true ? "正在扫描目录" : "没有可收入的文件", symbol: "doc")
        } else {
            Table(model.records, selection: $model.selectedFile) {
                TableColumn("文件") { record in
                    Text(record.name).lineLimit(1).truncationMode(.middle).help(record.path)
                }.width(min: 140, ideal: 250)
                TableColumn("状态") { record in
                    Text(
                        record.metadata.issue != nil
                            ? "提取失败" : record.metadata.available ? "已收入" : "原件失效"
                    )
                    .foregroundStyle(record.metadata.issue == nil ? Color.secondary : Color.orange)
                }.width(90)
                TableColumn("正文更新") { record in
                    if let date = record.metadata.revision?.extracted_at {
                        Text(date, format: .dateTime.month().day().hour().minute())
                    } else {
                        Text("—")
                    }
                }.width(min: 100, ideal: 140)
            }
        }
    }

    private func empty(_ title: String, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol).frame(
            maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileDetail: View {
    let record: FileRecord
    let text: String?
    let loading: Bool
    let issue: String?
    let retry: () -> Void
    let open: () -> Void
    let reveal: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.name).font(.headline).textSelection(.enabled)
                    Spacer()
                    Button("打开原件", action: open).disabled(!record.metadata.available)
                    Button("在 Finder 中显示", action: reveal).disabled(!record.metadata.available)
                }
                Text(record.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if let issue = record.metadata.issue {
                    Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .textSelection(.enabled)
                    if record.bodyID != nil { Text("以下为上次成功提取的正文").font(.callout) }
                } else if !record.metadata.available {
                    Label("原件已失效；已收入正文保留", systemImage: "doc.badge.ellipsis")
                }
                if record.metadata.revision?.scope == "main_document" {
                    Text("DOCX 主文档文字（不含脚注、批注）").font(.caption).foregroundStyle(.secondary)
                } else if record.metadata.revision?.scope == "text_layer" {
                    Text("PDF 文字层").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                if loading {
                    ProgressView("正在读取正文…").frame(maxWidth: .infinity, minHeight: 100)
                } else if let issue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                    Button("重试", action: retry)
                } else if let text {
                    Text(text.isEmpty ? "空白文本" : text).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("尚无已收入正文").foregroundStyle(.secondary)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
