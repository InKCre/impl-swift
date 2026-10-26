import AppKit
import Capture
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct CaptureImagePreview: View {
    let material: Capture.Material
    var height: CGFloat = 220
    @State private var previewURL: URL?
    @State private var issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                do { previewURL = try Self.makePreviewFile(material) } catch {
                    issue = error.localizedDescription
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("查看原图", systemImage: "eye").font(.caption).foregroundStyle(.tint)
                    if let data = material.data, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: height)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel("用快速查看打开采集原图")
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { previous, _ in
            if let previous { try? FileManager.default.removeItem(at: previous) }
        }
        .onDisappear { closePreview() }
        .onChange(of: material.id) { closePreview() }
    }

    private func closePreview() {
        if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
        previewURL = nil
    }

    static func makePreviewFile(_ material: Capture.Material) throws -> URL {
        guard let data = material.data, let mime = material.mimeType,
            let suffix = UTType(mimeType: mime)?.preferredFilenameExtension
        else { throw CocoaError(.fileReadCorruptFile) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkcre-preview-\(UUID().uuidString)").appendingPathExtension(
                suffix)
        guard
            FileManager.default.createFile(
                atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
