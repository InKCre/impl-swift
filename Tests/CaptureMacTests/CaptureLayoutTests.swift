import AppKit
import SwiftUI
import PeerCore
import PeerMacUI
import Testing
@testable import CaptureMac

@Suite(.serialized) @MainActor
struct CaptureLayoutTests {
    @Test func emptyRecordsContentIsCenteredAcrossDetailWidths() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.layout.\(UUID().uuidString)")
        defer { model.cancelWork() }
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
    @Test func nativeConnectionEditorRendersWithoutOpeningAWindow() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.layout.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let view = NSHostingView(rootView: PeerConnectionEditor(settings: model.connections, credentials: model.credentials, target: nil, onSaved: { _ in }).environment(\.colorScheme, .light).background(Color.white))
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:520,height:440), styleMask: [.titled], backing:.buffered, defer:false)
        window.appearance = NSAppearance(named:.aqua)
        window.contentView = view
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        let size = view.fittingSize
        #expect(size.width >= 500 && size.height > 300)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("native-connection.png"))
        }
    }

}
