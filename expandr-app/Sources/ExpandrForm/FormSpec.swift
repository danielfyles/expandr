import Foundation

/// The JSON espanso already emits for a form (see espanso's ModuloFormConfig):
/// `{ title, layout, fields: { name: {type, default, values, multiline, separator} },
///    max_form_width, max_form_height }`. We read the identical shape.
struct FormSpec: Decodable {
    let title: String
    let layout: String
    let fields: [String: FieldSpec]
    let maxFormWidth: Int?
    let maxFormHeight: Int?

    enum CodingKeys: String, CodingKey {
        case title, layout, fields
        case maxFormWidth = "max_form_width"
        case maxFormHeight = "max_form_height"
    }
}

struct FieldSpec: Decodable {
    var type: String?
    var `default`: String?
    var multiline: Bool?
    var values: [String]?
    var separator: String?

    var kind: FieldKind {
        switch type {
        case "choice": return .choice
        case "list": return .list
        default: return (multiline == true) ? .multiline : .text
        }
    }
}

enum FieldKind { case text, multiline, choice, list }

/// One piece of a layout row: literal text, or a `[[field]]` reference.
enum LayoutToken {
    case text(String)
    case field(String)
}

/// Split a layout string into rows of tokens, matching espanso's parser:
/// each non-empty (trimmed) line is a row; `[[name]]` and legacy `{{name}}`
/// become field tokens, everything else is text.
func parseLayout(_ layout: String) -> [[LayoutToken]] {
    let regex = try! NSRegularExpression(pattern: #"\{\{(.*?)\}\}|\[\[(.*?)\]\]"#)
    var rows: [[LayoutToken]] = []

    for rawLine in layout.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }

        let ns = line as NSString
        var row: [LayoutToken] = []
        var cursor = 0

        for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                if !text.isEmpty { row.append(.text(text)) }
            }
            var name = ""
            if m.range(at: 1).location != NSNotFound {
                name = ns.substring(with: m.range(at: 1))
            } else if m.range(at: 2).location != NSNotFound {
                name = ns.substring(with: m.range(at: 2))
            }
            row.append(.field(name))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            let text = ns.substring(from: cursor)
            if !text.isEmpty { row.append(.text(text)) }
        }
        rows.append(row)
    }
    return rows
}
