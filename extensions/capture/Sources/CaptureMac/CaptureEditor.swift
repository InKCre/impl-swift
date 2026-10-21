import AppKit
import Capture
import PeerCore
import SwiftUI

struct CaptureEditor: View {
    @ObservedObject var model: CaptureModel
    var isQuickCapture = false
    private enum Field: Hashable { case thought, annotation }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.draft.payload?.entry == .manual ? "此刻的想法" : "本次材料")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.draft.payload?.entry == .manual {
                        TextEditor(text: Binding(get: { model.thought }, set: { model.thought = $0 }))
                            .focused($focusedField, equals: .thought)
                            .font(.body).frame(minHeight: 140)
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("文字材料")
                    }
                    ForEach(Array((model.draft.payload?.materials ?? []).enumerated()), id: \.element.id) { index, material in
                        if material.kind != .text || model.draft.payload?.entry != .manual {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("材料 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("移除", systemImage: "xmark") { model.requestRemoveMaterial(material.id) }
                                        .accessibilityLabel("移除第 \(index + 1) 项材料")
                                }
                                if material.kind == .text {
                                    Text(material.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                } else if let data = material.data, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                        .accessibilityLabel("本次采集的图片")
                                } else {
                                    Text("图片原始字节已保留；系统无法预览此格式。").font(.caption)
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
                    Text("补充想法").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { model.annotation }, set: { model.annotation = $0 }))
                        .focused($focusedField, equals: .annotation)
                        .frame(minHeight: 64).padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("用户附注，与原文分别保存")
                }
            }
            Divider()
            Text(model.saveStatus).font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel(model.saveStatus)
            HStack {
                if isQuickCapture {
                    Button("取消本次") { model.cancelCapture() }
                } else {
                    Button("删除草稿", systemImage: "trash", role: .destructive) { model.requestDiscard(model.draft) }
                        .disabled(!model.hasContent)
                }
                Spacer()
                Button("导出材料") { model.export(model.draft) }
                    .disabled(!model.hasContent)
                Button("收入", systemImage: "tray.and.arrow.down") { model.submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasContent || model.submitting)
            }
        }.padding().disabled(model.submitting)
            .onAppear { focusEditor() }
            .onChange(of: model.draft.id) { focusEditor() }
            .onChange(of: model.submitting) { _, busy in if !busy { focusEditor() } }
    }

    private func focusEditor() {
        guard !model.submitting else { return }
        focusedField = model.draft.payload?.entry == .manual ? .thought : .annotation
    }
}
