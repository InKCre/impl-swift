import AppKit
import Capture
import PeerCore
import SwiftUI

struct CaptureRecordsView: View {
    @ObservedObject var model: CaptureModel
    @State private var passwordRecord: CaptureRecord?
    @State private var webRecord: CaptureRecord?
    var body: some View {
        Group {
            if model.records.isEmpty {
                ContentUnavailableView(
                    "还没有采集记录", systemImage: "tray",
                    description: Text("草稿、待收入和已收入的记录会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.records) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(record.statusLabel).font(.headline)
                                        Spacer()
                                        Text(
                                            record.updatedAt,
                                            format: .dateTime.month().day().hour().minute()
                                        ).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let text = record.payload?.materials.first(where: {
                                        $0.kind == .text
                                    })?.text {
                                        Text(text).lineLimit(3)
                                    } else if let material = record.payload?.materials.first(
                                        where: { $0.kind == .image }),
                                        material.data != nil
                                    {
                                        CaptureImagePreview(material: material, height: 100)
                                    }
                                    if let annotation = record.payload?.annotation,
                                        !annotation.isEmpty
                                    {
                                        Text(annotation).lineLimit(3).foregroundStyle(.secondary)
                                    }
                                    if let payload = record.payload, record.state != .draft {
                                        DisclosureGroup("查看全部材料") {
                                            CaptureRecordMaterials(payload: payload)
                                        }
                                    }
                                    if let message = record.message {
                                        Text(message).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let target = record.target {
                                        Text(target.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let result = record.result {
                                        Text("Block \(result.rootBlockID)").font(.caption)
                                            .textSelection(.enabled)
                                    }
                                    HStack {
                                        if record.state == .draft {
                                            Button("继续编辑") { model.resume(record) }
                                        } else if record.state == .confirmed {
                                            if model.resultURL(for: record) == nil {
                                                Button("配置 Web 地址…") { webRecord = record }
                                            } else {
                                                Button("打开") { model.openResult(record) }
                                            }
                                        } else {
                                            Button(record.state == .cancelled ? "继续收入" : "立即重试") {
                                                model.retry(record)
                                            }
                                            if record.state != .cancelled {
                                                Button("取消收入") { model.cancel(record) }
                                            }
                                            Button("更新密码…") { passwordRecord = record }
                                        }
                                        Button("删除记录", role: .destructive) {
                                            model.requestDiscard(record)
                                        }
                                        if record.payload != nil {
                                            Button("导出材料") { model.export(record) }
                                        }
                                    }
                                }
                                .padding(8)
                                .background(
                                    model.selectedRecordID == record.id
                                        ? Color.accentColor.opacity(0.08) : Color.clear
                                )
                                .id(record.id)
                                Divider()
                            }
                        }.padding()
                    }
                    .onAppear {
                        if let id = model.selectedRecordID { proxy.scrollTo(id, anchor: .top) }
                    }
                    .onChange(of: model.selectedRecordID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }.disabled(model.submitting)
            .sheet(item: $passwordRecord) { record in
                CaptureRecordSettings(model: model, record: record, field: .password)
            }
            .sheet(item: $webRecord) { record in
                CaptureRecordSettings(model: model, record: record, field: .webAddress)
            }
    }
}

struct CaptureRecordMaterials: View {
    let payload: CapturePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(payload.materials.enumerated()), id: \.element.id) { index, material in
                VStack(alignment: .leading, spacing: 4) {
                    Text("材料 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                    if material.kind == .text {
                        Text(material.text ?? "").textSelection(.enabled)
                    } else {
                        CaptureImagePreview(material: material)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let origin = payload.origin {
                VStack(alignment: .leading, spacing: 3) {
                    if let title = origin.title { Text(title) }
                    if let url = origin.url { Text(url).textSelection(.enabled) }
                    if let application = origin.applicationID { Text(application) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let annotation = payload.annotation, !annotation.isEmpty {
                Text("补充想法").font(.caption).foregroundStyle(.secondary)
                Text(annotation).textSelection(.enabled)
            }
        }.padding(.vertical, 8)
    }
}
