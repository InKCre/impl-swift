import AppKit
import InKCreLogoAssets

@MainActor
enum BrandAssets {
    static let lightMark = image(
        "inkcre-original-transparent-24px@2x", subdirectory: "png/2x/original-transparent", size: 24
    )
    static let darkMark = image(
        "inkcre-reverse-transparent-24px@2x", subdirectory: "png/2x/reverse-transparent", size: 24)
    static let menuIcon: NSImage = {
        let icon = image(
            "inkcre-black-transparent-20px@2x", subdirectory: "png/2x/black-transparent", size: 20)
        icon.isTemplate = true
        icon.accessibilityDescription = "InKCre"
        return icon
    }()

    private static let resources: Bundle = {
        // SwiftPM's generated accessor searches beside the executable; a macOS app packages resources in Contents/Resources.
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard
                let url = Bundle.main.url(
                    forResource: "InKCreUI_InKCreLogoAssets", withExtension: "bundle"),
                let bundle = Bundle(url: url)
            else { preconditionFailure("Missing packaged InKCre Logo assets") }
            return bundle
        }
        return InKCreLogoAssets.bundle
    }()

    private static func image(_ name: String, subdirectory: String, size: CGFloat) -> NSImage {
        guard
            let url = resources.url(
                forResource: name, withExtension: "png", subdirectory: subdirectory),
            let image = NSImage(contentsOf: url)
        else { preconditionFailure("Missing brand resource: \(name)") }
        image.size = NSSize(width: size, height: size)
        return image
    }
}
