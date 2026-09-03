import Foundation

/// One espanso match (a "snippet"). Only the fields we display/edit are modelled
/// explicitly; the full original mapping is kept in `raw` so writing a file back
/// never drops fields we don't yet understand.
struct Snippet: Identifiable, Hashable {
    let id = UUID()

    var label: String?
    var triggers: [String]      // from `trigger` (single) or `triggers` (list)
    var regex: String?
    var replace: String?        // plain-text replacement (the common case)
    var kind: EffectKind

    /// The original YAML mapping for this match, for lossless round-tripping.
    var raw: [String: Any]

    enum EffectKind: String {
        case replace, markdown, html, form, image, other
    }

    /// Primary text shown in the list — a trigger if present, else the label.
    var primaryText: String {
        if let first = triggers.first, !first.isEmpty { return first }
        if let regex, !regex.isEmpty { return regex }
        return label ?? "(untitled)"
    }

    /// Secondary/preview text shown under the primary.
    var previewText: String {
        if let label, !label.isEmpty, !triggers.isEmpty { return label }
        let body = replace ?? (raw["markdown"] as? String) ?? (raw["html"] as? String)
            ?? (raw["form"] as? String) ?? ""
        return body.replacingOccurrences(of: "\n", with: " ")
    }

    static func == (lhs: Snippet, rhs: Snippet) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One match file (`match/<name>.yml`) — maps to a category in the sidebar.
struct SnippetCategory: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var snippets: [Snippet]

    /// The file's other top-level keys (`imports`, `global_vars`) preserved for
    /// round-tripping.
    var rawTop: [String: Any]

    /// Display name = file name without extension.
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    static func == (lhs: SnippetCategory, rhs: SnippetCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
