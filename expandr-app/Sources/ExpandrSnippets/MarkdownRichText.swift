import AppKit
import Foundation

/// Markdown ⇄ NSAttributedString for the rich snippet editor.
///
/// The editor shows real formatting; the file stores Markdown (espanso's
/// `markdown:` key, rendered by pulldown-cmark). Supported vocabulary — the
/// "basic formatting" set: paragraphs with hard line breaks, headings 1–3,
/// bullet and numbered lists, **bold**, _italic_, `code`, and links. Anything
/// outside it is kept as text and reported by `hasUnsupportedSyntax` so the UI
/// can warn before a lossy save.
///
/// Line model: every editor line is a heading, a list item, a body line, or
/// empty. Consecutive body lines form one paragraph joined by backslash hard
/// breaks (robust in YAML block scalars, unlike trailing spaces); an empty line
/// is a paragraph break; headings and list items are blocks of their own.
enum MarkdownRichText {

    // MARK: Style vocabulary (fixed — no user-chosen fonts or sizes)

    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static func headingFont(_ level: Int) -> NSFont {
        NSFont.systemFont(ofSize: level <= 1 ? 22 : (level == 2 ? 18 : 15), weight: .bold)
    }
    /// Paragraph-level markers: heading level (Int 1…3), list kind ("bullet"/"number").
    static let headingKey = NSAttributedString.Key("app.expandr.heading")
    static let listKey = NSAttributedString.Key("app.expandr.list")
    /// Inline-code marker (the font alone is ambiguous once traits mix).
    static let codeKey = NSAttributedString.Key("app.expandr.code")

    static let bulletMarker = "\u{2022}\u{00A0}"                 // "• " with a no-break space
    static func numberMarker(_ n: Int) -> String { "\(n).\u{00A0}" }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor]
    }

    static func styled(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) } else { traits.remove(.bold) }
        if italic { traits.insert(.italic) } else { traits.remove(.italic) }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base
    }
    static func isBold(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.bold) }
    static func isItalic(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.italic) }

    // MARK: Line kinds

    enum LineKind: Equatable { case empty, body, heading(Int), bullet, number }

    static func lineKind(_ attr: NSAttributedString, _ range: NSRange) -> LineKind {
        guard range.length > 0 else { return .empty }
        let a = attr.attributes(at: range.location, effectiveRange: nil)
        if let level = a[headingKey] as? Int { return .heading(level) }
        if let list = a[listKey] as? String { return list == "number" ? .number : .bullet }
        return .body
    }

    /// Lines of the string as (range, kind), splitting on "\n".
    static func lines(of attr: NSAttributedString) -> [(NSRange, LineKind)] {
        let ns = attr.string as NSString
        var result: [(NSRange, LineKind)] = []
        var loc = 0
        for part in ns.components(separatedBy: "\n") {
            let r = NSRange(location: loc, length: (part as NSString).length)
            result.append((r, lineKind(attr, r)))
            loc += r.length + 1
        }
        return result
    }

    // MARK: Markdown → attributed

    private enum BlockKind { case heading(Int), bullet, number(Int), body }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: bodyAttributes)
        }

        var blocks: [(kind: BlockKind, text: NSMutableAttributedString)] = []
        var currentID: Int? = nil
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var blockID: Int? = nil
            var kind: BlockKind = .body
            var inList = false, ordered = false, ordinal = 1
            for c in run.presentationIntent?.components ?? [] {
                switch c.kind {
                case .paragraph: blockID = c.identity
                case .header(let level): blockID = c.identity; kind = .heading(min(max(level, 1), 3))
                case .codeBlock: blockID = c.identity
                case .listItem(let n): inList = true; ordinal = n
                case .orderedList: ordered = true
                default: break
                }
            }
            if inList, case .body = kind { kind = ordered ? .number(ordinal) : .bullet }
            let id = blockID ?? -1
            if blocks.isEmpty || id != currentID {
                blocks.append((kind, NSMutableAttributedString()))
                currentID = id
            }
            let inline = run.inlinePresentationIntent ?? []
            var piece = text
            if inline.contains(.softBreak) { piece = " " } else if inline.contains(.lineBreak) { piece = "\n" }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
            if inline.contains(.code) {
                attrs[.font] = codeFont; attrs[codeKey] = true
            } else {
                let base: NSFont
                if case .heading(let l) = blocks[blocks.count - 1].kind { base = headingFont(l) } else { base = bodyFont }
                attrs[.font] = styled(base, bold: inline.contains(.stronglyEmphasized), italic: inline.contains(.emphasized))
            }
            if let url = run.link { attrs[.link] = url }
            blocks[blocks.count - 1].text.append(NSAttributedString(string: piece, attributes: attrs))
        }

        let out = NSMutableAttributedString()
        var prev: BlockKind? = nil
        for b in blocks {
            if let prev {
                let sep: String
                switch (prev, b.kind) {
                case (.heading, _): sep = "\n"
                case (.bullet, .bullet), (.bullet, .number), (.number, .bullet), (.number, .number): sep = "\n"
                default: sep = "\n\n"
                }
                out.append(NSAttributedString(string: sep, attributes: bodyAttributes))
            }
            let line = NSMutableAttributedString()
            switch b.kind {
            case .heading(let l):
                line.append(b.text)
                line.addAttribute(headingKey, value: l, range: NSRange(location: 0, length: line.length))
            case .bullet:
                line.append(NSAttributedString(string: bulletMarker, attributes: bodyAttributes)); line.append(b.text)
                line.addAttribute(listKey, value: "bullet", range: NSRange(location: 0, length: line.length))
            case .number(let n):
                line.append(NSAttributedString(string: numberMarker(n), attributes: bodyAttributes)); line.append(b.text)
                line.addAttribute(listKey, value: "number", range: NSRange(location: 0, length: line.length))
            case .body:
                line.append(b.text)
            }
            out.append(line)
            prev = b.kind
        }
        return out
    }

    // MARK: Attributed → Markdown

    static func markdown(from attr: NSAttributedString) -> String {
        let all = lines(of: attr)
        var blocks: [String] = []
        var i = 0
        while i < all.count {
            let (range, kind) = all[i]
            switch kind {
            case .empty:
                i += 1
            case .heading(let level):
                blocks.append(String(repeating: "#", count: level) + " " + escapeLineStart(inlineMarkdown(attr, range, inHeading: true)))
                i += 1
            case .bullet, .number:
                var items: [String] = []; var n = 0
                while i < all.count, all[i].1 == .bullet || all[i].1 == .number {
                    let (r, k) = all[i]
                    let content = escapeLineStart(inlineMarkdown(attr, stripMarker(attr, r), inHeading: false))
                    if k == .number { n += 1; items.append("\(n). " + content) } else { n = 0; items.append("- " + content) }
                    i += 1
                }
                blocks.append(items.joined(separator: "\n"))
            case .body:
                var body: [String] = []
                while i < all.count, all[i].1 == .body {
                    body.append(escapeLineStart(inlineMarkdown(attr, all[i].0, inHeading: false)))
                    i += 1
                }
                blocks.append(body.joined(separator: "\\\n"))
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The content range of a list line, without our marker text.
    static func stripMarker(_ attr: NSAttributedString, _ range: NSRange) -> NSRange {
        let text = (attr.string as NSString).substring(with: range)
        var drop = 0
        if text.hasPrefix(bulletMarker) { drop = (bulletMarker as NSString).length }
        else if let m = text.range(of: "^[0-9]+\\.\u{00A0}", options: .regularExpression) {
            drop = (String(text[m]) as NSString).length
        }
        return NSRange(location: range.location + drop, length: range.length - drop)
    }

    static func inlineMarkdown(_ attr: NSAttributedString, _ range: NSRange, inHeading: Bool) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        // Links first, so a link spanning several styled runs stays one link.
        attr.enumerateAttribute(.link, in: range, options: []) { value, r, _ in
            let inner = styledInline(attr, r, inHeading: inHeading)
            if let value {
                let url = (value as? URL)?.absoluteString ?? "\(value)"
                out += "[" + inner + "](" + url + ")"
            } else {
                out += inner
            }
        }
        return out
    }

    private static func styledInline(_ attr: NSAttributedString, _ range: NSRange, inHeading: Bool) -> String {
        var out = ""
        attr.enumerateAttributes(in: range, options: []) { a, r, _ in
            let text = (attr.string as NSString).substring(with: r)
            if a[codeKey] != nil {
                let fence = String(repeating: "`", count: text.contains("`") ? 2 : 1)
                out += fence + text + fence
                return
            }
            let font = a[.font] as? NSFont ?? bodyFont
            let bold = !inHeading && isBold(font), italic = isItalic(font)
            let escaped = escape(text)
            let lead = String(escaped.prefix { $0 == " " })
            let rest = escaped.dropFirst(lead.count)
            let trail = String(rest.reversed().prefix { $0 == " " }.reversed())
            var core = String(rest.dropLast(trail.count))
            if !core.isEmpty {
                if bold && italic { core = "**_" + core + "_**" }
                else if bold { core = "**" + core + "**" }
                else if italic { core = "_" + core + "_" }
            }
            out += lead + core + trail
        }
        return out
    }

    /// Escape Markdown specials in literal text, leaving {{variable}} references intact.
    static func escape(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i...].hasPrefix("{{"), let close = s[i...].range(of: "}}") {
                out += s[i..<close.upperBound]; i = close.upperBound; continue
            }
            let ch = s[i]
            if "\\*_`[]<>".contains(ch) { out.append("\\") }
            out.append(ch)
            i = s.index(after: i)
        }
        return out
    }

    /// Escape a line that would otherwise start a block (heading, quote, list, rule).
    static func escapeLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#>-+".contains(first) { return "\\" + line }
        if let m = line.range(of: "^[0-9]+\\.", options: .regularExpression) {
            return String(line[m].dropLast()) + "\\." + line[m.upperBound...]
        }
        return line
    }

    // MARK: Queries & conversions

    static func hasFormatting(_ attr: NSAttributedString) -> Bool {
        var found = false
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { a, _, stop in
            if a[headingKey] != nil || a[listKey] != nil || a[codeKey] != nil || a[.link] != nil {
                found = true; stop.pointee = true; return
            }
            if let f = a[.font] as? NSFont, isBold(f) || isItalic(f) { found = true; stop.pointee = true }
        }
        return found
    }

    /// Plain text of a rich body (list markers become "• " / "1. " with normal spaces).
    static func plainText(from attr: NSAttributedString) -> String {
        attr.string.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Plain text for an `html:` snippet — tags stripped, entities decoded,
    /// <br>/<p> turned into line breaks. Main thread only (WebKit-backed).
    static func plainText(fromHTML html: String) -> String {
        if let a = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil) {
            // WebKit's importer uses U+2028/2029 for <br> and paragraph ends.
            return a.string
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .replacingOccurrences(of: "\u{2029}", with: "\n")
                .trimmingCharacters(in: .newlines)
        }
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Markdown the editor can't round-trip (kept as text, but a save simplifies it).
    static func hasUnsupportedSyntax(_ md: String) -> Bool {
        let patterns = [
            "(?m)^\\s*(>|```|~~~|\\|)",          // quotes, fences, tables
            "!\\[",                               // images
            "(?m)^\\s{2,}[-*+]\\s",               // nested lists
            "(?m)^(-{3,}|\\*{3,}|_{3,})\\s*$",    // rules
            "<[a-zA-Z/][^>]*>",                   // inline HTML
            "(?m)^\\s*#{4,}\\s",                  // h4+
        ]
        return patterns.contains { md.range(of: $0, options: .regularExpression) != nil }
    }
}
