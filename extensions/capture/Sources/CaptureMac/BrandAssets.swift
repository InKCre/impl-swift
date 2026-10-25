import AppKit

@MainActor
enum BrandAssets {
    static let lightMark = image("MarkLight", size: 24)
    static let darkMark = image("MarkDark", size: 24)
    static let menuIcon: NSImage = {
        let icon = image("MenuTemplate", size: 20)
        icon.isTemplate = true
        icon.accessibilityDescription = "InKCre"
        return icon
    }()

    private static let resources: Bundle = {
        // SwiftPM's generated accessor searches beside the executable; a macOS app packages resources in Contents/Resources.
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard
                let url = Bundle.main.url(
                    forResource: "InKCreCapture_CaptureMac", withExtension: "bundle"),
                let bundle = Bundle(url: url)
            else { preconditionFailure("Missing packaged InKCre resources") }
            return bundle
        }
        return Bundle.module
    }()

    private static func image(_ name: String, size: CGFloat) -> NSImage {
        guard
            let url = resources.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
            let image = NSImage(contentsOf: url)
        else { preconditionFailure("Missing brand resource: \(name)") }
        image.size = NSSize(width: size, height: size)
        return image
    }
}
