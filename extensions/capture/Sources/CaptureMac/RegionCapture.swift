// SPDX-License-Identifier: Apache-2.0
// Capture coordination originally adapted from Cida by Xuanwo and contributors.
// InKCre now uses the BetterShot selection component; sources and changes: Legal/.
import AppKit
import Capture
import PeerCore
import ScreenCaptureKit

struct ScreenRecordingPermissionError: LocalizedError {
    var errorDescription: String? {
        "系统尚未允许当前 InKCre 读取屏幕。请在设置中授权，随后完全退出并重新打开应用。"
    }
}

@MainActor
final class RegionCapture {
    private var captureTask: Task<Void, Never>?
    private var completion: ((Result<Data?, Error>) -> Void)?
    private let hasPermission: () -> Bool
    private let freezeScreens: () async throws -> [FrozenScreenFrame]
    private let overlay: RegionSelectionOverlay
    var isCapturing: Bool { completion != nil }

    init(
        hasPermission: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        freezeScreens: @escaping () async throws -> [FrozenScreenFrame] = RegionCapture.freezeScreens,
        overlay: RegionSelectionOverlay = RegionSelectionOverlay()
    ) {
        self.hasPermission = hasPermission
        self.freezeScreens = freezeScreens
        self.overlay = overlay
    }

    func begin(completion: @escaping (Result<Data?, Error>) -> Void) {
        guard self.completion == nil else { return }
        // Requesting access belongs to the explicit settings action, never a screenshot retry.
        guard hasPermission() else {
            completion(.failure(ScreenRecordingPermissionError()))
            return
        }
        self.completion = completion
        captureTask = Task {
            do {
                let frames = try await freezeScreens()
                guard !Task.isCancelled else { return }
                guard !frames.isEmpty else { throw PeerError.invalid("没有可用的屏幕，请重新截图。") }
                let outcome = await overlay.selectRegion(frozenFrames: frames)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .cancelled:
                    finish(.success(nil))
                case .region(let selection):
                    guard let frame = frames.first(where: { $0.displayID == selection.displayID }) else {
                        throw PeerError.invalid("找不到所选画面，请重新截图。")
                    }
                    let data = try await Task.detached(priority: .userInitiated) {
                        try frame.png(in: selection.pointsRect)
                    }.value
                    guard !Task.isCancelled else { return }
                    try CapturePayload(entry: .screenshot, materials: [Material(image: data, mimeType: "image/png")]).validate()
                    finish(.success(data))
                }
            } catch {
                guard !Task.isCancelled else { return }
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain, failure.code == SCStreamError.Code.userDeclined.rawValue {
                    finish(.failure(ScreenRecordingPermissionError()))
                } else {
                    finish(.failure(error))
                }
            }
        }
    }

    func stop() async {
        completion = nil
        captureTask?.cancel()
        overlay.cancel()
        await captureTask?.value
        captureTask = nil
    }

    private func finish(_ result: Result<Data?, Error>) {
        let callback = completion
        completion = nil
        captureTask = nil
        callback?(result)
    }

    private static func freezeScreens() async throws -> [FrozenScreenFrame] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var frames: [FrozenScreenFrame] = []
        for screen in NSScreen.screens {
            try Task.checkCancellation()
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                throw PeerError.invalid("屏幕配置已改变，请重新截图。")
            }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            frames.append(FrozenScreenFrame(displayID: display.displayID, pointsRect: display.frame, image: image))
        }
        return frames
    }
}
