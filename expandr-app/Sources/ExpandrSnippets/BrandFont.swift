import SwiftUI
import CoreText
import AppKit

/// Brand typography: Fraunces (serif display) for headings, Newsreader (serif
/// text) for body. Both are *variable* fonts, so we register the bundled files
/// once and build each `Font` by setting the `wght`/`opsz` axes via CoreText —
/// otherwise we'd only ever get each font's default instance (Fraunces Black,
/// Newsreader Regular).
enum BrandFont {
    // Ensures registration happens exactly once, lazily, before first use.
    private static let registered = registerBundledFonts()

    /// Fraunces. Default weight ~semibold; `opsz` follows the point size so large
    /// headings pick up the display-optimised shapes.
    static func heading(_ size: CGFloat, weight: CGFloat = 560) -> Font {
        _ = registered
        return Font(ctFont(family: "Fraunces", size: size,
                           axes: [wght: weight, opsz: min(max(size, 9), 144)]))
    }

    /// Newsreader. Default weight regular; `opsz` at its 18pt optical default.
    static func body(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        _ = registered
        return Font(ctFont(family: "Newsreader 16pt", size: size,
                           axes: [wght: weight, opsz: 18]))
    }

    // Variation axis four-char codes as their UInt32 identifiers.
    private static let wght = 0x7767_6874  // 'wght'
    private static let opsz = 0x6F70_737A  // 'opsz'

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

    /// Register the bundled `.ttf`s with the process font manager. Idempotent:
    /// a second attempt (already-registered) is harmless and ignored.
    private static func registerBundledFonts() -> Bool {
        guard let fontsDir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else {
            return false
        }
        for file in ["Fraunces.ttf", "Newsreader.ttf"] {
            let url = fontsDir.appendingPathComponent(file)
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }
}
