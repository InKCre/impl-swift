//
//  FontManager.swift
//  D3LibMin
//
//  Created by Jackson Guo on 2025/7/26.
//

import SwiftUI

struct FontManager {
    static let spaceGroteskMedium = "SpaceGrotesk-Medium"
    
    static func registerFonts() {
        // Try to register the font
        if let fontURL = Bundle.main.url(forResource: spaceGroteskMedium, withExtension: "ttf") {
            if let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
               let font = CGFont(fontDataProvider) {
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterGraphicsFont(font, &error) {
                    print("Successfully registered font: \(spaceGroteskMedium)")
                } else {
                    print("Failed to register font: \(error?.takeUnretainedValue().localizedDescription ?? "Unknown error")")
                }
            } else {
                print("Could not create font from data provider")
            }
        } else {
            print("Could not find font file: \(spaceGroteskMedium).ttf")
            print("Make sure the font file is added to the Xcode project and included in the app bundle")
        }
    }
}

extension Font {
    static func spaceGroteskMedium(size: CGFloat) -> Font {
        // Try to use custom font, fallback to system font if not available
        if let _ = UIFont(name: FontManager.spaceGroteskMedium, size: size) {
            return Font.custom(FontManager.spaceGroteskMedium, size: size)
        } else {
            return Font.system(size: size, weight: .medium)
        }
    }
} 