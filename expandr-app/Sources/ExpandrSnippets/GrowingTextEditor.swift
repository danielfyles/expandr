import SwiftUI
import AppKit

/// A plain-text editor that grows to fit its content (no internal scrolling),
/// down to a minimum height. SwiftUI's `TextEditor` can't auto-size on macOS 13,
/// so this wraps a non-scrolling `NSTextView` that reports its content height as
/// its intrinsic size.
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 54

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> GrowingNSTextView {
        let view = GrowingNSTextView()
        view.minHeightConstant = minHeight
        view.delegate = context.coordinator
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.textColor = .labelColor
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.string = text
        return view
    }

    func updateNSView(_ view: GrowingNSTextView, context: Context) {
        view.minHeightConstant = minHeight
        if view.string != text { view.string = text }
        view.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: GrowingTextEditor
        init(_ parent: GrowingTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? GrowingNSTextView else { return }
            parent.text = view.string
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class GrowingNSTextView: NSTextView {
    var minHeightConstant: CGFloat = 54

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeightConstant)
        }
        layoutManager.ensureLayout(for: textContainer)
        let contentHeight = layoutManager.usedRect(for: textContainer).height
            + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(minHeightConstant, contentHeight))
    }

    // Re-wrap and re-measure when the available width changes.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}
