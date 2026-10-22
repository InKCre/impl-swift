import AppKit
import Capture
import PeerCore
import SwiftUI

struct CaptureRecordsView: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        Group {
            if model.records.isEmpty {
                ContentUnavailableView("还没有采集记录", systemImage: "tray",
                                       description: Text("草稿、待收入和已收入的记录会显示在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(record.statusLabel).font(.headline)
                                    Spacer()
                                    Text(record.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                                if let text = record.payload?.materials.first(where: { $0.kind == .text })?.text {
                                    Text(text).lineLimit(3)
                                } else if let material = record.payload?.materials.first(where: { $0.kind == .image }),
                                          let data = material.data, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 100)
                                        .accessibilityLabel("记录中的图片")
                                }
                                if let annotation = record.payload?.annotation, !annotation.isEmpty {
                                    Text(annotation).lineLimit(3).foregroundStyle(.secondary)
                                }
                                if let message = record.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                                if let target = record.target { Text(target.name).font(.caption).foregroundStyle(.secondary) }
                                if let result = record.result { Text("Block \(result.rootBlockID)").font(.caption).textSelection(.enabled) }
                                HStack {
                                    if record.state == .draft {
                                        Button("继续编辑") { model.resume(record) }
                                    } else if record.state == .confirmed {
                                        if record.result?.availability == .deleted {
                                            Text("共享内容已删除").font(.caption).foregroundStyle(.secondary)
                                        } else if model.resultURL(for: record) == nil {
                                            Button("配置 Web 地址…") { model.openConnectionSettings(target: record.target) }
                                        } else {
                                            Button("打开") { model.openResult(record) }
                                        }
                                    } else {
                                        Button(record.state == .cancelled ? "继续收入" : "立即重试") { model.retry(record) }
                                        if record.state != .cancelled {
                                            Button("取消收入") { model.cancel(record) }
                                        }
                                        Button("修复连接") { model.openConnectionSettings(target: record.target) }
                                    }
                                    Button("删除记录", role: .destructive) { model.requestDiscard(record) }
                                    if record.payload != nil { Button("导出材料") { model.export(record) } }
                                }
                            }
                            Divider()
                        }
                    }.padding()
                }
            }
        }.disabled(model.submitting)
    }
}
