import AppKit
import SwiftUI
import Testing
@testable import InKCreApp

@Suite(.serialized) @MainActor
struct CaptureLayoutTests {
    @Test func emptyRecordsContentIsCenteredAcrossDetailWidths() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.layout.\(UUID().uuidString)")
        defer { model.stop() }
        for width in [520, 550, 790] {
            let renderer = ImageRenderer(content: CaptureRecordsView(model: model)
                .environment(\.colorScheme, .light)
                .frame(width: CGFloat(width), height: 517)
                .background(.white))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            var minX = width
            var maxX = -1
            // The system symbol is symmetric; punctuation makes text ink bounds asymmetric.
            var foundSymbol = false
            for y in 0..<bitmap.pixelsHigh {
                var hasInk = false
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent < 0.9 || color.greenComponent < 0.9 || color.blueComponent < 0.9 {
                        hasInk = true
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                    }
                }
                if foundSymbol && !hasInk { break }
                foundSymbol = foundSymbol || hasInk
            }
            #expect(maxX >= minX)
            #expect(abs(Double(minX + maxX) / 2 - Double(width - 1) / 2) < 1)
            if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
                let output = URL(fileURLWithPath: path).appendingPathComponent("records-empty-\(width).png")
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
            }
        }
    }
}
