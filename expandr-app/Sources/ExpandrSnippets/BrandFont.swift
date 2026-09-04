import SwiftUI
import CoreText
import AppKit

/// Expandr brand palette, sampled from the expandr.app holding page.
extension Color {
    static let brandBG         = Color(red: 250/255, green: 243/255, blue: 230/255) // #FAF3E6
    static let brandCard       = Color(red: 255/255, green: 252/255, blue: 246/255) // #FFFCF6
    static let brandInk        = Color(red: 46/255,  green: 33/255,  blue: 24/255)  // #2E2118
    static let brandMuted      = Color(red: 107/255, green: 87/255,  blue: 72/255)  // #6B5748
    static let brandAccent     = Color(red: 201/255, green: 112/255, blue: 47/255)  // #C9702F
    static let brandAccentDeep = Color(red: 138/255, green: 63/255,  blue: 22/255)  // #8A3F16
    // Variable surface (a cool slate blue), to distinguish it from forms.
    static let brandBlue       = Color(red: 190/255, green: 198/255, blue: 214/255) // #BEC6D6
    static let brandSlate      = Color(red: 58/255,  green: 70/255,  blue: 88/255)  // #3A4658
    static let brandSage       = Color(red: 211/255, green: 214/255, blue: 190/255) // #D3D6BE
}

/// The cream ground + top orange glow used for form surfaces (matches the
/// expansion form interface).
struct FormSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.brandBG
            RadialGradient(
                colors: [Color.brandAccent.opacity(0.16), .clear],
                center: .top, startRadius: 0, endRadius: 280)
        }
    }
}

/// The slate-blue ground + top glow used for the variables surface.
struct VariableSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.brandBlue
            RadialGradient(
                colors: [Color.brandSlate.opacity(0.14), .clear],
                center: .top, startRadius: 0, endRadius: 280)
        }
    }
}

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
