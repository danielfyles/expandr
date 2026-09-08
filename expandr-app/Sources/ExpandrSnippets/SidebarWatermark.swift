import SwiftUI
import AppKit

/// A pale, silvery panda glyph anchored at the foot of the sidebar — purely
/// decorative. The glyph is an alpha-only template (outline, ears, eyes, nose;
/// clear face) so it takes whatever tint it's given and adapts to dark mode.
/// Loaded from the app bundle like `offline-fix.png`; a dev build has no
/// bundle resource, in which case nothing is drawn.
struct SidebarWatermark: View {
    // Tuning knobs.
    static let width: CGFloat = 96          // glyph width in points
    static let bottomPadding: CGFloat = 60  // clears the gear row, with room to spare
    static let opacity: Double = 0.6        // on top of the already-pale tint

    private static let glyph: NSImage? = {
        guard let url = Bundle.main.url(forResource: "panda-outline", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let glyph = Self.glyph {
            Image(nsImage: glyph)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.width)
                .foregroundStyle(.tertiary)
                .opacity(Self.opacity)
                .padding(.bottom, Self.bottomPadding)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
