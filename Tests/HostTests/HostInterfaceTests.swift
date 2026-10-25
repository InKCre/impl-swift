import AppKit
import PeerCore
import SwiftUI
import Testing

@testable import CaptureMac
@testable import InKCreApp

@Suite(.serialized) @MainActor
struct HostInterfaceTests {
    @Test func nativeSidebarShortcutAndSettingsTabsRemainAvailableWithoutCapture() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let domain = "dev.inkcre.host-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(false, forKey: "extensions.inkcre/capture.enabled")
        let host = PeerHost(
            context: PeerHostContext(identity: domain, directory: directory), defaults: defaults)
        let previousMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        defer {
            NSApp.mainMenu = previousMenu
            NSApp.windowsMenu = previousWindowsMenu
        }
        host.installHostMenu()
        let menu = try #require(NSApp.mainMenu)
        let viewMenu = try #require(menu.items.first(where: { $0.title == "显示" })?.submenu)
        let sidebar = try #require(
            viewMenu.items.first(where: {
                $0.action == #selector(NSSplitViewController.toggleSidebar(_:))
            }))
        #expect(sidebar.keyEquivalent == "s")
        #expect(sidebar.keyEquivalentModifierMask == [.command, .option])
        #expect(sidebar.target == nil)
        let settings = try #require(
            menu.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }))
        #expect(settings.keyEquivalentModifierMask == .command)
        #expect(host.validateUserInterfaceItem(settings))
        let window = PeerSettingsWindow(host: host)
        defer { window.orderOut(nil) }
        #expect(!window.isVisible)
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == ["连接", "扩展", "采集"])
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for pane in [PeerSettingsWindow.Pane.connection, .extensions, .capture] {
                window.select(pane)
                try await Task.sleep(for: .milliseconds(100))
                #expect(tabs.selectedTabViewItemIndex == pane.rawValue)
                let view = try #require(window.contentView?.superview)
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
                    try #require(bitmap.representation(using: .png, properties: [:])).write(
                        to:
                            URL(fileURLWithPath: path).appendingPathComponent(
                                "settings-\(pane)-\(appearance.rawValue).png"))
                }
            }
        }
        let captureModel = try CaptureModel(
            directory: directory.appendingPathComponent("capture"), identity: domain)
        defer { captureModel.cancelWork() }
        window.replaceCaptureSettings(
            with: NSHostingController(rootView: CaptureSettingsView(model: captureModel)))
        window.select(.capture)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(200))
            let view = try #require(window.contentView?.superview)
            view.layoutSubtreeIfNeeded()
            #expect(view.bounds.width >= 600 && view.bounds.height >= 400)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
                try #require(bitmap.representation(using: .png, properties: [:])).write(
                    to:
                        URL(fileURLWithPath: path).appendingPathComponent(
                            "settings-capture-enabled-\(appearance.rawValue).png"))
            }
        }
        #expect(!window.isVisible)
    }
}
