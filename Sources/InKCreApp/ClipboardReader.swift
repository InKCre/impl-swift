import AppKit
import CaptureCore
import UniformTypeIdentifiers

@MainActor
enum ClipboardReader {
    static func materials() throws -> [Material] {
        var result: [Material] = []
        let supported: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "image/png"), (.init(UTType.jpeg.identifier), "image/jpeg"),
            (.init(UTType.gif.identifier), "image/gif"), (.init(UTType.webP.identifier), "image/webp"),
        ]
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            var image: Material?
            for (type, mime) in supported {
                if let data = item.data(forType: type) {
                    image = Material(image: data, mimeType: mime)
                    break
                }
            }
            if let image { result.append(image); continue }
            if let data = item.data(forType: .tiff),
               let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                result.append(Material(image: png, mimeType: "image/png"))
                continue
            }
            if item.types.contains(.fileURL) {
                throw CaptureError.invalid("首版不导入文件。请粘贴文字、链接或图片本身。")
            }
            if let text = item.string(forType: .string) ?? item.string(forType: .URL), !text.isEmpty {
                result.append(Material(text: text))
            }
        }
        try CapturePayload(entry: .paste, materials: result).validate()
        return result
    }
}
