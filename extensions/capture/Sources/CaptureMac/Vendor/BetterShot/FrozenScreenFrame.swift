// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, Kartik Labhshetwar
// Adapted for InKCre. Fixed source and modifications: Legal/BetterShot/ATTRIBUTION.txt.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The displayed frame is also the export source; selecting never takes a second shot.
struct FrozenScreenFrame: Sendable {
    let displayID: CGDirectDisplayID
    let pointsRect: CGRect
    let image: CGImage

    nonisolated func croppedImage(in region: CGRect) throws -> CGImage {
        guard pointsRect.width > 0, pointsRect.height > 0,
              region.width > 0, region.height > 0, pointsRect.contains(region) else {
            throw NSError(domain: "InKCre.FrozenScreenCapture", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "所选区域已超出冻结画面，请重新截图。"
            ])
        }
        let sx = CGFloat(image.width) / pointsRect.width
        let sy = CGFloat(image.height) / pointsRect.height
        let pixels = CGRect(
            x: (region.minX - pointsRect.minX) * sx,
            y: (region.minY - pointsRect.minY) * sy,
            width: region.width * sx,
            height: region.height * sy
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let cropped = image.cropping(to: pixels) else { throw CocoaError(.fileReadCorruptFile) }
        return cropped
    }

    nonisolated func png(in region: CGRect) throws -> Data {
        let cropped = try croppedImage(in: region)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
