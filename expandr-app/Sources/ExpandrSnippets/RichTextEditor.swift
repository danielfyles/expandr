import SwiftUI
import AppKit

/// Formatting actions for the rich editor. Holds the text view so toolbar
/// buttons can act on the current selection. The vocabulary is deliberately
/// small — bold, italic, code, link, bullet/numbered list, heading — and every
/// action writes only attributes `MarkdownRichText` knows how to serialise.
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?
    private typealias M = MarkdownRichText

    // MARK: Inline styles

    func toggleBold() { toggleTrait(bold: true) }
    func toggleItalic() { toggleTrait(bold: false) }

    private func toggleTrait(bold: Bool) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let range = tv.selectedRange()
        let has: (NSFont) -> Bool = bold ? M.isBold : M.isItalic
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let font = attrs[.font] as? NSFont ?? M.bodyFont
            let on = has(font)
            attrs[.font] = M.styled(font, bold: bold ? !on : M.isBold(font), italic: bold ? M.isItalic(font) : !on)
            tv.typingAttributes = attrs
            return
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
            if storage.attribute(M.codeKey, at: r.location, effectiveRange: nil) != nil { return }
            if !has(v as? NSFont ?? M.bodyFont) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
            if storage.attribute(M.codeKey, at: r.location, effectiveRange: nil) != nil { return }
            let f = v as? NSFont ?? M.bodyFont
            let nf = M.styled(f, bold: bold ? !allHave : M.isBold(f), italic: bold ? M.isItalic(f) : !allHave)
            storage.addAttribute(.font, value: nf, range: r)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    func toggleCode() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let range = tv.selectedRange()
        if range.length == 0 {
            var attrs = tv.typingAttributes
            if attrs[M.codeKey] != nil { attrs.removeValue(forKey: M.codeKey); attrs[.font] = M.bodyFont }
            else { attrs[M.codeKey] = true; attrs[.font] = M.codeFont }
            tv.typingAttributes = attrs
            return
        }
        var allCode = true
        storage.enumerateAttribute(M.codeKey, in: range, options: []) { v, _, _ in if v == nil { allCode = false } }
        storage.beginEditing()
        if allCode {
            storage.removeAttribute(M.codeKey, range: range)
            storage.addAttribute(.font, value: M.bodyFont, range: range)
        } else {
            storage.addAttribute(M.codeKey, value: true, range: range)
            storage.addAttribute(.font, value: M.codeFont, range: range)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    func addLink(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let tv = textView, let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let value: Any = URL(string: trimmed) ?? trimmed
        let range = tv.selectedRange()
        if range.length == 0 {
            var attrs = tv.typingAttributes
            attrs[.link] = value
            tv.insertText(NSAttributedString(string: trimmed, attributes: attrs), replacementRange: range)
            return
        }
        storage.addAttribute(.link, value: value, range: range)
        tv.didChangeText()
    }

    // MARK: Paragraph styles

    /// Toggle a list kind ("bullet" / "number") on the paragraphs in the selection.
    func toggleList(_ kind: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let paras = Self.paragraphRanges(in: storage, covering: tv.selectedRange())
        let allAlready = paras.allSatisfy { storage.length > 0 && $0.location < storage.length
            && (storage.attribute(M.listKey, at: $0.location, effectiveRange: nil) as? String) == kind }
        storage.beginEditing()
        for para in paras.reversed() {   // back to front so earlier ranges stay valid
            let content = Self.paragraphContent(para, in: storage)
            let hadMarker = M.stripMarker(storage, content)
            let markerLen = hadMarker.location - content.location
            if markerLen > 0 { storage.deleteCharacters(in: NSRange(location: content.location, length: markerLen)) }
            let newContent = NSRange(location: content.location, length: content.length - markerLen)
            storage.removeAttribute(M.listKey, range: newContent)
            storage.removeAttribute(M.headingKey, range: newContent)
            if !allAlready {
                var attrs = M.bodyAttributes; attrs[M.listKey] = kind
                let marker = kind == "number" ? M.numberMarker(1) : M.bulletMarker
                storage.insert(NSAttributedString(string: marker, attributes: attrs), at: newContent.location)
                storage.addAttribute(M.listKey, value: kind,
                                     range: NSRange(location: newContent.location, length: newContent.length + (marker as NSString).length))
                Self.normaliseFonts(storage, in: NSRange(location: newContent.location, length: newContent.length + (marker as NSString).length), to: M.bodyFont)
            }
        }
        storage.endEditing()
        Self.renumber(storage)
        tv.didChangeText()
    }

    /// Set heading level 1…3 on the selected paragraphs, or 0 for body text.
    func setHeading(_ level: Int) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let paras = Self.paragraphRanges(in: storage, covering: tv.selectedRange())
        storage.beginEditing()
        for para in paras.reversed() {
            let content = Self.paragraphContent(para, in: storage)
            let stripped = M.stripMarker(storage, content)
            let markerLen = stripped.location - content.location
            if markerLen > 0 { storage.deleteCharacters(in: NSRange(location: content.location, length: markerLen)) }
            let r = NSRange(location: content.location, length: content.length - markerLen)
            storage.removeAttribute(M.listKey, range: r)
            if level == 0 {
                storage.removeAttribute(M.headingKey, range: r)
                Self.normaliseFonts(storage, in: r, to: M.bodyFont)
            } else {
                storage.addAttribute(M.headingKey, value: level, range: r)
                Self.normaliseFonts(storage, in: r, to: M.headingFont(level))
            }
        }
        storage.endEditing()
        Self.renumber(storage)
        tv.didChangeText()
        var typing = tv.typingAttributes
        typing[.font] = level == 0 ? M.bodyFont : M.headingFont(level)
        if level == 0 { typing.removeValue(forKey: M.headingKey) } else { typing[M.headingKey] = level }
        tv.typingAttributes = typing
    }

    // MARK: Enter key

    /// Continue lists (or leave an empty item), and drop back to body text after a
    /// heading. Returns true when handled.
    static func handleNewline(in tv: NSTextView) -> Bool {
        guard let storage = tv.textStorage, storage.length > 0 else { return false }
        let sel = tv.selectedRange()
        let para = (storage.string as NSString).paragraphRange(for: NSRange(location: sel.location, length: 0))
        guard para.location < storage.length else { return false }
        let attrs = storage.attributes(at: para.location, effectiveRange: nil)
        if let list = attrs[M.listKey] as? String {
            let content = paragraphContent(para, in: storage)
            let stripped = M.stripMarker(storage, content)
            if stripped.length == 0 {
                // Enter on an empty item leaves the list.
                storage.replaceCharacters(in: content, with: NSAttributedString(string: "", attributes: M.bodyAttributes))
                tv.setSelectedRange(NSRange(location: content.location, length: 0))
                tv.typingAttributes = M.bodyAttributes
                tv.didChangeText()
                return true
            }
            var a = M.bodyAttributes; a[M.listKey] = list
            let marker = list == "number" ? M.numberMarker(1) : M.bulletMarker
            tv.insertText(NSAttributedString(string: "\n" + marker, attributes: a), replacementRange: sel)
            renumber(storage)
            tv.didChangeText()
            return true
        }
        if attrs[M.headingKey] != nil {
            tv.insertText(NSAttributedString(string: "\n", attributes: M.bodyAttributes), replacementRange: sel)
            tv.typingAttributes = M.bodyAttributes
            return true
        }
        return false
    }

    // MARK: Helpers

    static func paragraphRanges(in storage: NSTextStorage, covering sel: NSRange) -> [NSRange] {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return [NSRange(location: 0, length: 0)] }
        let whole = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: min(sel.length, ns.length - min(sel.location, ns.length))))
        var result: [NSRange] = []
        var loc = whole.location
        while loc < whole.location + whole.length {
            let p = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            result.append(p)
            if p.length == 0 { break }
            loc = p.location + p.length
        }
        return result.isEmpty ? [whole] : result
    }

    /// A paragraph range minus its trailing newline.
    static func paragraphContent(_ para: NSRange, in storage: NSTextStorage) -> NSRange {
        let ns = storage.string as NSString
        var r = para
        if r.length > 0, ns.character(at: r.location + r.length - 1) == 0x0A { r.length -= 1 }
        return r
    }

    /// Reset fonts in a range to `base`, keeping bold/italic traits and code runs.
    static func normaliseFonts(_ storage: NSTextStorage, in range: NSRange, to base: NSFont) {
        storage.enumerateAttributes(in: range, options: []) { a, r, _ in
            if a[M.codeKey] != nil { storage.addAttribute(.font, value: M.codeFont, range: r); return }
            let f = a[.font] as? NSFont ?? M.bodyFont
            storage.addAttribute(.font, value: M.styled(base, bold: M.isBold(f) && base.pointSize == M.bodyFont.pointSize, italic: M.isItalic(f)), range: r)
        }
    }

    /// Renumber consecutive numbered-list lines 1, 2, 3… after edits.
    static func renumber(_ storage: NSTextStorage) {
        let lines = M.lines(of: storage)
        var edits: [(NSRange, String)] = []
        var n = 0
        for (range, kind) in lines {
            if kind == .number {
                n += 1
                let text = (storage.string as NSString).substring(with: range)
                if let m = text.range(of: "^[0-9]+\\.\u{00A0}", options: .regularExpression) {
                    let cur = String(text[m]); let want = M.numberMarker(n)
                    if cur != want { edits.append((NSRange(location: range.location, length: (cur as NSString).length), want)) }
                }
            } else { n = 0 }
        }
        guard !edits.isEmpty else { return }
        storage.beginEditing()
        for (r, want) in edits.reversed() {
            var attrs = storage.attributes(at: r.location, effectiveRange: nil)
            attrs[.font] = M.bodyFont
            storage.replaceCharacters(in: r, with: NSAttributedString(string: want, attributes: attrs))
        }
        storage.endEditing()
    }
}

/// A rich-text editor that grows with its content, mirroring `GrowingTextEditor`
/// but bound to an `NSAttributedString`. Pastes are flattened to plain text so
/// foreign fonts and colours never enter the document.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var minHeight: CGFloat = 120
    var isEditable: Bool = true
    var insertionTarget: TextInsertionTarget? = nil
    var controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RichGrowingNSTextView {
        let view = RichGrowingNSTextView()
        view.minHeightConstant = minHeight
        view.delegate = context.coordinator
        view.isEditable = isEditable
        view.isRichText = true
        view.usesFontPanel = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.typingAttributes = MarkdownRichText.bodyAttributes
        view.textStorage?.setAttributedString(text)
        insertionTarget?.textView = view
        controller.textView = view
        return view
    }

    func updateNSView(_ view: RichGrowingNSTextView, context: Context) {
        view.minHeightConstant = minHeight
        view.isEditable = isEditable
        insertionTarget?.textView = view
        controller.textView = view
        if !view.attributedString().isEqual(to: text) {
            view.textStorage?.setAttributedString(text)
        }
        view.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            // Copy: attributedString() is the live storage, not a snapshot.
            parent.text = NSAttributedString(attributedString: view.attributedString())
            (view as? GrowingNSTextView)?.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return RichTextController.handleNewline(in: textView)
        }
    }
}

final class RichGrowingNSTextView: GrowingNSTextView {
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

/// The formatting toolbar shown above the rich editor.
struct RichFormattingBar: View {
    @ObservedObject var controller: RichTextController
    @State private var showLinkPrompt = false
    @State private var linkURL = ""

    var body: some View {
        HStack(spacing: 6) {
            tool("bold") { controller.toggleBold() }.help("Bold").keyboardShortcut("b", modifiers: .command)
            tool("italic") { controller.toggleItalic() }.help("Italic").keyboardShortcut("i", modifiers: .command)
            tool("chevron.left.forwardslash.chevron.right") { controller.toggleCode() }.help("Code")
            tool("link") { linkURL = ""; showLinkPrompt = true }.help("Link").keyboardShortcut("k", modifiers: .command)
            Divider().frame(height: 14)
            tool("list.bullet") { controller.toggleList("bullet") }.help("Bulleted list")
            tool("list.number") { controller.toggleList("number") }.help("Numbered list")
            Menu {
                Button("Body text") { controller.setHeading(0) }
                Button("Heading 1") { controller.setHeading(1) }
                Button("Heading 2") { controller.setHeading(2) }
                Button("Heading 3") { controller.setHeading(3) }
            } label: {
                Image(systemName: "textformat.size").frame(width: 18)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .help("Heading")
            Spacer()
            Text("Saved as Markdown").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .alert("Add link", isPresented: $showLinkPrompt) {
            TextField("https://…", text: $linkURL)
            Button("Add link") { controller.addLink(linkURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected text becomes a link. With nothing selected, the address itself is inserted.")
        }
    }

    private func tool(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18) }
            .buttonStyle(.bordered).controlSize(.small)
    }
}
