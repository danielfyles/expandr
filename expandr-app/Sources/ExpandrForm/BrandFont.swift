import SwiftUI
import CoreText
import AppKit

/// Fraunces (headings) and Newsreader (body), matching the builder app. Both are
/// variable fonts, registered once from the SwiftPM resource bundle; each `Font`
/// is built by setting the `wght`/`opsz` axes via CoreText (otherwise we'd only
/// get the default instance — Fraunces Black, Newsreader Regular).
enum BrandFont {
    private static let registered = registerBundledFonts()

    static func heading(_ size: CGFloat, weight: CGFloat = 560) -> Font {
        _ = registered
        return Font(ctFont(family: "Fraunces", size: size,
                           axes: [wght: weight, opsz: min(max(size, 9), 144)]))
    }

    static func body(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        _ = registered
        return Font(ctBodyFont(size: size, weight: weight))
    }

    /// Newsreader as an `NSFont`, for AppKit views (the multiline text box).
    static func bodyNSFont(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        _ = registered
        return ctBodyFont(size: size, weight: weight) as NSFont
    }

    private static let wght = 0x7767_6874  // 'wght'
    private static let opsz = 0x6F70_737A  // 'opsz'

    private static func ctBodyFont(size: CGFloat, weight: CGFloat) -> CTFont {
        ctFont(family: "Newsreader 16pt", size: size, axes: [wght: weight, opsz: 18])
    }

    private static func ctFont(family: String, size: CGFloat, axes: [Int: CGFloat]) -> CTFont {
        var variation: [NSNumber: NSNumber] = [:]
        for (axis, value) in axes { variation[NSNumber(value: axis)] = NSNumber(value: Double(value)) }
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: variation,
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }

    private static func registerBundledFonts() -> Bool {
        for name in ["Fraunces", "Newsreader"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }
}
