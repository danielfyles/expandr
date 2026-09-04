import SwiftUI
import AppKit

/// Holds a reference to a text view so buttons elsewhere can insert text at its
/// caret (used for dropping {{variable}} references into the Replacement field).
final class TextInsertionTarget: ObservableObject {
    weak var textView: NSTextView?

    /// Insert `string` at the current caret/selection, focusing the field so the
    /// change is visible; falls back to nothing if no field is registered.
    func insert(_ string: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(string, replacementRange: textView.selectedRange())
    }
}

/// A plain-text editor that grows to fit its content (no internal scrolling),
/// down to a minimum height. SwiftUI's `TextEditor` can't auto-size on macOS 13,
/// so this wraps a non-scrolling `NSTextView` that reports its content height as
/// its intrinsic size.
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 54
    var placeholder: String = ""
    var isEditable: Bool = true
    var insertionTarget: TextInsertionTarget? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> GrowingNSTextView {
        let view = GrowingNSTextView()
        view.minHeightConstant = minHeight
        view.placeholder = placeholder
        insertionTarget?.textView = view
        view.delegate = context.coordinator
        view.isEditable = isEditable
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
        view.placeholder = placeholder
        view.isEditable = isEditable
        insertionTarget?.textView = view
        if view.string != text { view.string = text }
        view.invalidateIntrinsicContentSize()
        view.needsDisplay = true  // refresh the placeholder as the text empties/fills
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
    var placeholder: String = ""

    // Draw placeholder text when empty (NSTextView has no built-in placeholder).
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: attributes)
    }

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
