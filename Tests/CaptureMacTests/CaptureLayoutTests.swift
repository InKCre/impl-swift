import AppKit
import Capture
import PeerCore
import PeerMacUI
import SwiftUI
import Testing

@testable import CaptureMac

@Suite(.serialized) @MainActor
struct CaptureLayoutTests {
    @Test func emptyRecordsContentIsCenteredAcrossDetailWidths() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(
            directory: directory, identity: "dev.inkcre.layout.\(UUID().uuidString)")
        defer { model.cancelWork() }
        for width in [520, 550, 790] {
            let renderer = ImageRenderer(
                content: CaptureRecordsView(model: model)
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
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                        continue
                    }
                    if color.redComponent < 0.9 || color.greenComponent < 0.9
                        || color.blueComponent < 0.9
                    {
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
                let output = URL(fileURLWithPath: path).appendingPathComponent(
                    "records-empty-\(width).png")
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
            }
        }
    }
    @Test func nativeConnectionEditorRendersWithoutOpeningAWindow() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(
            directory: directory, identity: "dev.inkcre.layout.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let view = NSHostingView(
            rootView: PeerConnectionEditor(
                settings: model.connections, credentials: model.credentials, target: nil,
                onSaved: { _ in }
            ).environment(\.colorScheme, .light).background(Color.white))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
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
            try #require(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: path).appendingPathComponent("native-connection.png"))
        }
    }

    @Test func captureSurfacesRenderOffscreen() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(
            directory: directory, identity: "dev.inkcre.surfaces.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: CapturePageView(model: model))
        window.setContentSize(NSSize(width: 760, height: 520))
        defer { window.orderOut(nil) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for pane in [CaptureModel.Pane.capture, .queue] {
                model.pane = pane
                try await snapshot(window, named: "main-\(pane)-\(appearance.rawValue)")
            }
            model.records = [CaptureRecord(payload: CapturePayload(annotation: "只有补充想法的草稿也必须有预览。"))]
            model.pane = .queue
            try await snapshot(window, named: "records-annotation-\(appearance.rawValue)")
            model.records = []
        }
        let auxiliary = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        defer { auxiliary.orderOut(nil) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            auxiliary.appearance = NSAppearance(named: appearance)
            auxiliary.contentViewController = NSHostingController(
                rootView: CaptureSettingsView(model: model))
            auxiliary.setContentSize(NSSize(width: 600, height: 560))
            try await snapshot(auxiliary, named: "capture-settings-\(appearance.rawValue)")
            model.editorOwner = .quick
            model.thought = "用于界面验收的合成想法，不读取剪贴板或屏幕。"
            auxiliary.contentViewController = NSHostingController(
                rootView: QuickCaptureView(model: model))
            auxiliary.setContentSize(NSSize(width: 500, height: 500))
            try await snapshot(auxiliary, named: "quick-\(appearance.rawValue)")
        }
        #expect(!window.isVisible && !auxiliary.isVisible)
    }

    @Test func captureJourneysRenderAtMinimumSizeWithReadableActions() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(
            directory: directory, identity: "dev.inkcre.journey-layout.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let source = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor.systemBlue.setFill()
            NSRect(x: 40, y: 600, width: 1120, height: 150).fill()
            ("截图原文 · 合成内容" as NSString).draw(
                at: NSPoint(x: 80, y: 650),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.white,
                ])
            ("原图 1200 × 800，可用快速查看阅读细节。" as NSString).draw(
                at: NSPoint(x: 80, y: 500),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black,
                ])
            return true
        }
        let tiff = try #require(source.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let material = Capture.Material(image: data, mimeType: "image/png")
        let preview = try CaptureImagePreview.makePreviewFile(material)
        defer { try? FileManager.default.removeItem(at: preview) }
        #expect(try Data(contentsOf: preview) == data)
        #expect(
            (try FileManager.default.attributesOfItem(atPath: preview.path)[.posixPermissions]
                as? NSNumber)?.intValue == 0o600)
        let target = ConnectionTarget(
            host: "original.test", database: "inkcre", username: "inkcre_core",
            name: "original.test/inkcre")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            model.editorOwner = .quick
            model.draft = CaptureRecord(
                payload: CapturePayload(materials: [
                    Capture.Material(text: "手写想法只有一个主要输入区，可以持续输入并自动保留。")
                ]))
            window.contentViewController = NSHostingController(
                rootView: QuickCaptureView(model: model))
            window.setContentSize(NSSize(width: 500, height: 500))
            try await snapshot(window, named: "journey-manual-\(appearance.rawValue)")
            model.draft = CaptureRecord(
                payload: CapturePayload(
                    entry: .screenshot, materials: [material], annotation: "这张图说明了什么？"))
            try await snapshot(window, named: "journey-image-\(appearance.rawValue)")
            model.draft = CaptureRecord(
                payload: CapturePayload(
                    entry: .paste,
                    materials: [
                        Capture.Material(
                            text: String(repeating: "原文内容可以滚动阅读；自己的想法在下面单独输入。\n", count: 16))
                    ]))
            try await snapshot(window, named: "journey-long-source-\(appearance.rawValue)")
            model.connection = target
            model.submit()
            for _ in 0..<100 where model.submittedRecord?.state != .needsAction {
                try await Task.sleep(for: .milliseconds(10))
            }
            let failed = try #require(model.submittedRecord)
            try await snapshot(window, named: "journey-feedback-\(appearance.rawValue)")
            model.showRecord(failed)
            window.contentViewController = NSHostingController(
                rootView: CaptureRecordsView(model: model))
            window.setContentSize(NSSize(width: 520, height: 480))
            try await snapshot(window, named: "journey-failure-record-\(appearance.rawValue)")
            let payload = try #require(failed.payload)
            window.contentViewController = NSHostingController(
                rootView:
                    ScrollView { CaptureRecordMaterials(payload: payload).padding() })
            window.setContentSize(NSSize(width: 520, height: 480))
            try await snapshot(window, named: "journey-all-materials-\(appearance.rawValue)")
            for field in [CaptureRecordSettings.Field.password, .webAddress] {
                window.contentViewController = NSHostingController(
                    rootView: CaptureRecordSettings(model: model, record: failed, field: field))
                window.setContentSize(NSSize(width: 520, height: 400))
                try await snapshot(
                    window, named: "journey-\(field)-\(appearance.rawValue)",
                    minimumSize: NSSize(width: 480, height: 250))
            }
        }
        #expect(!window.isVisible)
    }

    private func snapshot(
        _ window: NSWindow, named name: String,
        minimumSize: NSSize = NSSize(width: 500, height: 400)
    ) async throws {
        try await Task.sleep(for: .milliseconds(200))
        let view = try #require(window.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(
            bitmap.pixelsWide >= Int(minimumSize.width)
                && bitmap.pixelsHigh >= Int(minimumSize.height))
        if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
            try #require(bitmap.representation(using: .png, properties: [:])).write(
                to:
                    URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
        }
    }

}
