import Foundation

/// A form field in the designer. espanso stores forms as a `type: form` variable
/// whose `params` hold a `layout` template and a `fields` mapping; we present that
/// as an ordered list of these, and (de)serialise between the two.
struct FormFieldSpec: Identifiable, Equatable {
    let id = UUID()
    var label: String            // display label (the text before [[name]] in the layout)
    var name: String             // the {{form.<name>}} key
    var kind: Kind
    var defaultValue: String
    var values: [String]         // choice / list options

    enum Kind: String, CaseIterable, Identifiable, Equatable {
        case text, multiline, choice, list
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return "Text"
            case .multiline: return "Multiline"
            case .choice: return "Dropdown"
            case .list: return "List"
            }
        }
    }
}

/// Parsing/serialising espanso form vars ⟷ `[FormFieldSpec]`.
enum FormBuilder {
    /// The first `type: form` variable in a snippet, if any.
    static func formVar(in snippet: Snippet) -> SnippetVar? {
        snippet.vars.first { $0.type == "form" }
    }

    /// Parse a form var's params into ordered fields (order + labels come from the
    /// layout; field configs from the `fields` mapping).
    static func parse(_ variable: SnippetVar) -> [FormFieldSpec] {
        let layout = variable.params["layout"] as? String ?? ""
        let fieldsMap = variable.params["fields"] as? [String: Any] ?? [:]

        var result: [FormFieldSpec] = []
        var seen = Set<String>()
        for (name, label) in layoutFields(layout) {
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(field(name: name, label: label, config: fieldsMap[name] as? [String: Any]))
        }
        // Any fields declared but not referenced in the layout, appended.
        for (name, config) in fieldsMap where !seen.contains(name) {
            result.append(field(name: name, label: prettify(name), config: config as? [String: Any]))
        }
        return result
    }

    private static func field(name: String, label: String, config: [String: Any]?) -> FormFieldSpec {
        let type = config?["type"] as? String
        let multiline = config?["multiline"] as? Bool ?? false
        let kind: FormFieldSpec.Kind
        switch type {
        case "choice": kind = .choice
        case "list": kind = .list
        default: kind = multiline ? .multiline : .text
        }
        let values = (config?["values"] as? [Any])?.compactMap { $0 as? String } ?? []
        return FormFieldSpec(
            label: label, name: name, kind: kind,
            defaultValue: config?["default"] as? String ?? "", values: values)
    }

    /// Build the `params` (layout + fields) for a form var from the field list.
    static func params(from fields: [FormFieldSpec]) -> [String: Any] {
        var layoutLines: [String] = []
        var fieldsMap: [String: Any] = [:]

        for f in fields where !f.name.isEmpty {
            let label = f.label.isEmpty ? "" : "\(f.label):"
            // A multiline field reads better with its label on its own line.
            if f.kind == .multiline {
                layoutLines.append(label.isEmpty ? "[[\(f.name)]]" : label)
                if !label.isEmpty { layoutLines.append("[[\(f.name)]]") }
            } else {
                layoutLines.append(label.isEmpty ? "[[\(f.name)]]" : "\(label) [[\(f.name)]]")
            }
            fieldsMap[f.name] = config(for: f)
        }

        return ["layout": layoutLines.joined(separator: "\n"), "fields": fieldsMap]
    }

    private static func config(for f: FormFieldSpec) -> [String: Any] {
        var c: [String: Any] = [:]
        switch f.kind {
        case .text: break
        case .multiline: c["multiline"] = true
        case .choice: c["type"] = "choice"; c["values"] = f.values
        case .list: c["type"] = "list"; c["values"] = f.values
        }
        if !f.defaultValue.isEmpty { c["default"] = f.defaultValue }
        return c
    }

    // MARK: - Layout tokenising (mirrors espanso's parser)

    /// Ordered (name, label) pairs from a layout string. Label = trimmed text
    /// immediately preceding the `[[field]]` (inline or on a prior line).
    private static func layoutFields(_ layout: String) -> [(name: String, label: String)] {
        let regex = try! NSRegularExpression(pattern: #"\{\{(.*?)\}\}|\[\[(.*?)\]\]"#)
        var out: [(String, String)] = []
        var pending = ""

        for rawLine in layout.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let ns = line as NSString
            var cursor = 0
            for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > cursor {
                    let text = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { pending = text }
                }
                var name = ""
                if m.range(at: 1).location != NSNotFound { name = ns.substring(with: m.range(at: 1)) }
                else if m.range(at: 2).location != NSNotFound { name = ns.substring(with: m.range(at: 2)) }
                out.append((name, cleanLabel(pending, fallback: name)))
                pending = ""
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length {
                let text = ns.substring(from: cursor).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { pending = text }
            }
        }
        return out
    }

    private static func cleanLabel(_ text: String, fallback: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        while let last = s.last, last == ":" || last == "," { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? prettify(fallback) : s
    }

    private static func prettify(_ name: String) -> String {
        let spaced = name.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
