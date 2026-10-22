import AppKit
import Testing

struct AppIconTests {
    @Test func iconsetHasTransparentMacMarginsAtEveryScale() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("extensions/capture/Sources/CaptureMac/Resources/Brand/AppIcon.iconset")
        for (name, pixels, fraction) in [
            ("16x16", 16, 0.875), ("16x16@2x", 32, 0.875),
            ("32x32", 32, 0.875), ("32x32@2x", 64, 0.875),
            ("128x128", 128, 0.8046875), ("128x128@2x", 256, 0.8046875),
            ("256x256", 256, 0.8046875), ("256x256@2x", 512, 0.8046875),
            ("512x512", 512, 0.8046875), ("512x512@2x", 1024, 0.8046875),
        ] {
            let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: folder.appendingPathComponent("icon_\(name).png"))))
            #expect(bitmap.pixelsWide == pixels && bitmap.pixelsHigh == pixels)
            let inset = Double(pixels) * (1 - fraction) / 2
            for vertical in [false, true] {
                let visible = (0..<pixels).filter { offset in
                    let color = bitmap.colorAt(x: vertical ? pixels / 2 : offset, y: vertical ? offset : pixels / 2)
                    return (color?.alphaComponent ?? 0) > 0.05
                }
                let first = try #require(visible.first)
                let last = try #require(visible.last)
                #expect(abs(Double(first) - inset) <= 1)
                #expect(abs(Double(pixels - last - 1) - inset) <= 1)
            }
            #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
            #expect(try #require(bitmap.colorAt(x: pixels / 2, y: pixels / 2)).alphaComponent == 1)
        }
    }
}
