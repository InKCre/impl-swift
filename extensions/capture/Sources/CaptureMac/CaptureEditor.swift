import AppKit
import Capture
import PeerCore
import SwiftUI

struct CaptureEditor: View {
    @ObservedObject var model: CaptureModel
    var isQuickCapture = false
    private enum Field: Hashable { case thought, annotation }
    @FocusState private var focusedField: Field?
    @State private var showsAnnotation = false
    private var isManual: Bool { model.draft.payload?.entry == .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isQuickCapture {
                HStack {
                    Button("新想法", systemImage: "square.and.pencil") { model.newThought() }
                    Button("粘贴材料", systemImage: "doc.on.clipboard") { model.pasteMaterial() }
                    Button("框选截图", systemImage: "viewfinder") { model.takeScreenshot?() }
                    Spacer()
                    Button("收起") { model.dismissQuickCapture?() }
                }
            }
            if let notice = model.captureNotice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if let notice = model.screenCaptureNotice {
                VStack(alignment: .leading, spacing: 6) {
                    Text(notice).font(.callout)
                    HStack {
                        Button("请求屏幕录制权限") { model.requestScreenRecordingAccess() }
                        Button("打开系统设置") { model.openScreenRecordingSettings() }
                    }
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if isManual {
                Text("此刻的想法").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { model.thought }, set: { model.thought = $0 }))
                    .focused($focusedField, equals: .thought)
                    .font(.body).frame(minHeight: 100, maxHeight: .infinity)
                    .accessibilityLabel("此刻的想法")
            }
            if let image = standaloneImage {
                HStack {
                    Text("本次图片").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("移除", systemImage: "xmark") { model.requestRemoveMaterial(image.id) }
                }
                CaptureImagePreview(material: image, height: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if !isManual || additionalMaterials {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("本次材料").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(
                            Array((model.draft.payload?.materials ?? []).enumerated()),
                            id: \.element.id
                        ) { index, material in
                            if !isManual
                                || material.id
                                    != model.draft.payload?.materials.first(where: {
                                        $0.kind == .text
                                    })?.id
                            {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("材料 \(index + 1)").font(.caption).foregroundStyle(
                                            .secondary)
                                        Spacer()
                                        Button("移除", systemImage: "xmark") {
                                            model.requestRemoveMaterial(material.id)
                                        }
                                        .accessibilityLabel("移除第 \(index + 1) 项材料")
                                    }
                                    if material.kind == .text {
                                        Text(material.text ?? "").textSelection(.enabled).frame(
                                            maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        CaptureImagePreview(material: material)
                                    }
                                }
                            }
                        }
                        if let origin = model.draft.payload?.origin {
                            VStack(alignment: .leading, spacing: 3) {
                                if let title = origin.title { Text(title) }
                                if let url = origin.url { Text(url).textSelection(.enabled) }
                                if let application = origin.applicationID { Text(application) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            }
            if !isManual || showsAnnotation || !model.annotation.isEmpty {
                DisclosureGroup("补充想法（可选）", isExpanded: $showsAnnotation) {
                    TextEditor(
                        text: Binding(get: { model.annotation }, set: { model.annotation = $0 })
                    )
                    .focused($focusedField, equals: .annotation)
                    .frame(height: 70).accessibilityLabel("用户附注，与原文分别保存")
                }
            }
            Divider()
            if let record = model.submittedRecord {
                HStack {
                    Label(
                        "上次采集：\(record.statusLabel)",
                        systemImage: record.state == .confirmed ? "checkmark.circle" : "tray")
                    Spacer()
                    Button("查看记录") { model.showRecord(record) }
                }.font(.callout)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model.saveStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let target = model.connection {
                    Text("收入到 \(target.name)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).help("\(target.host):\(target.port)/\(target.database)")
                } else {
                    Text("收入前需连接信息库").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if isQuickCapture {
                    Button("取消本次") { model.cancelCapture() }
                } else {
                    Button("删除草稿", systemImage: "trash", role: .destructive) {
                        model.requestDiscard(model.draft)
                    }
                    .disabled(!model.hasContent)
                }
                Spacer()
                Button("导出材料") { model.export(model.draft) }.disabled(!model.hasContent)
                Button("收入", systemImage: "tray.and.arrow.down") { model.submit() }
                    .buttonStyle(.borderedProminent).disabled(!model.hasContent || model.submitting)
            }
        }.padding().disabled(model.submitting)
            .onAppear {
                showsAnnotation = !model.annotation.isEmpty
                focusEditor()
            }
            .onChange(of: model.draft.id) {
                showsAnnotation = !model.annotation.isEmpty
                focusEditor()
            }
            .onChange(of: showsAnnotation) { _, expanded in
                if expanded { focusedField = .annotation }
            }
            .onChange(of: model.submitting) { _, busy in if !busy { focusEditor() } }
    }

    private var standaloneImage: Capture.Material? {
        guard let payload = model.draft.payload, payload.materials.count == 1,
            payload.materials[0].kind == .image, payload.origin == nil
        else { return nil }
        return payload.materials[0]
    }

    private var additionalMaterials: Bool {
        let materials = model.draft.payload?.materials ?? []
        return materials.contains { $0.kind == .image }
            || materials.filter { $0.kind == .text }.count > 1
    }

    private func focusEditor() {
        guard !model.submitting else { return }
        focusedField = isManual ? .thought : (showsAnnotation ? .annotation : nil)
    }
}
