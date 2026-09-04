import SwiftUI
import AppKit

/// Drives Tab focus through every field ourselves, so it works regardless of the
/// macOS "Keyboard navigation" system setting (which otherwise makes Tab skip
/// dropdowns/radios/buttons). A local key monitor consumes Tab / Shift-Tab and
/// advances `current`; the view mirrors `current` into its `@FocusState` and
/// draws a focus ring from it.
final class FocusController: ObservableObject {
    @Published var current: String?
    var order: [String] = []
    // Metadata so we can operate dropdown/radio fields from the keyboard, since
    // SwiftUI Pickers aren't keyboard-operable via .focused on macOS 13.
    var kinds: [String: FieldKind] = [:]
    var options: [String: [String]] = [:]
    weak var values: ValuesStore?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 48:  // Tab
                self.advance(backwards: event.modifierFlags.contains(.shift))
                return nil
            case 125, 126:  // Down (125) / Up (126)
                if self.adjustCurrent(backwards: event.keyCode == 126) { return nil }
                return event
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func advance(backwards: Bool) {
        guard !order.isEmpty else { return }
        let next: Int
        if let cur = current, let idx = order.firstIndex(of: cur) {
            next = backwards ? (idx - 1 + order.count) % order.count : (idx + 1) % order.count
        } else {
            next = backwards ? order.count - 1 : 0
        }
        current = order[next]
    }

    /// Up/Down on a focused choice/list cycles its selected value. Returns true
    /// if it handled the key (so text fields keep their normal arrow behaviour).
    private func adjustCurrent(backwards: Bool) -> Bool {
        guard let cur = current, let kind = kinds[cur],
              kind == .choice || kind == .list,
              let opts = options[cur], !opts.isEmpty, let values else { return false }
        let currentValue = values.map[cur] ?? opts[0]
        let idx = opts.firstIndex(of: currentValue) ?? 0
        let next = backwards ? (idx - 1 + opts.count) % opts.count : (idx + 1) % opts.count
        values.map[cur] = opts[next]
        return true
    }
}

/// Shared, mutable form values so the focus controller can change dropdown/radio
/// selections in response to arrow keys.
final class ValuesStore: ObservableObject {
    @Published var map: [String: String]
    init(_ map: [String: String]) { self.map = map }
}

/// Expandr brand palette, sampled from the expandr.app holding page.
extension Color {
    static let brandBG        = Color(red: 250/255, green: 243/255, blue: 230/255) // #FAF3E6
    static let brandCard      = Color(red: 255/255, green: 252/255, blue: 246/255) // #FFFCF6
    static let brandInk       = Color(red: 46/255,  green: 33/255,  blue: 24/255)  // #2E2118
    static let brandMuted     = Color(red: 107/255, green: 87/255,  blue: 72/255)  // #6B5748
    static let brandAccent    = Color(red: 201/255, green: 112/255, blue: 47/255)  // #C9702F
    static let brandAccentDeep = Color(red: 138/255, green: 63/255, blue: 22/255)  // #8A3F16
}

extension NSColor {
    static let brandBG = NSColor(red: 250/255, green: 243/255, blue: 230/255, alpha: 1)
}

/// A multiline text field where **Enter submits** and **Shift+Enter** inserts a
/// newline — so a form's Enter-to-submit works even from inside the message box.
struct SubmittingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onSubmit: () -> Void
    var onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmitTextView()
        textView.onSubmit = onSubmit
        textView.onFocus = onFocus
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = BrandFont.bodyNSFont(14)
        textView.textColor = NSColor(Color.brandInk)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.focusRingType = .none  // no blue focus ring

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SubmitTextView else { return }
        if textView.string != text { textView.string = text }
        textView.onSubmit = onSubmit
        textView.onFocus = onFocus
        // Tab moved focus here → make it first responder so typing lands.
        if isFocused, let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SubmittingTextEditor
        init(_ parent: SubmittingTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView { parent.text = tv.string }
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onFocus: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            super.insertNewline(sender)  // Shift+Enter → newline
        } else {
            onSubmit?()                  // Enter → submit
        }
    }

    // Clicking into the box updates the shared focus state.
    override func becomeFirstResponder() -> Bool {
        onFocus?()
        return super.becomeFirstResponder()
    }
}
