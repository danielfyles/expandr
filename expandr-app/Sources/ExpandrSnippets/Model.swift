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
    var vars: [SnippetVar]      // {{name}} variables referenced by the body

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

    /// First line in the list: the label if set, otherwise the replacement body.
    var listTitle: String {
        if let label, !label.isEmpty { return label }
        let body = replace ?? (raw["markdown"] as? String) ?? (raw["html"] as? String)
            ?? (raw["form"] as? String) ?? ""
        let oneLine = body.replacingOccurrences(of: "\n", with: " ")
        if !oneLine.isEmpty { return oneLine }
        return triggers.first ?? regex ?? "(untitled)"
    }

    /// Second line in the list: the expansion trigger(s).
    var listSubtitle: String {
        if !triggers.isEmpty { return triggers.joined(separator: ", ") }
        return regex ?? ""
    }

    // Compare the modelled fields (not just `id`) so SwiftUI's ForEach/List
    // diffing re-renders a row after its trigger/label/body is edited. `raw`
    // isn't Equatable, but the fields below cover everything the UI shows.
    static func == (lhs: Snippet, rhs: Snippet) -> Bool {
        lhs.id == rhs.id
            && lhs.label == rhs.label
            && lhs.triggers == rhs.triggers
            && lhs.regex == rhs.regex
            && lhs.replace == rhs.replace
            && lhs.kind == rhs.kind
            && lhs.vars.count == rhs.vars.count
    }
    // Hash stays id-only: equal snippets share an id (so equal hashes), and
    // unequal snippets are allowed to collide.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// An espanso variable — resolves a `{{name}}` reference in the body. `params`
/// are type-specific; `raw` preserves fields we don't model (inject_vars,
/// depends_on, unusual params) for round-tripping.
struct SnippetVar: Identifiable {
    let id = UUID()
    var name: String
    var type: String
    var params: [String: Any]
    var raw: [String: Any]

    /// Variable types offered in the picker, in a sensible order. `echo` (a
    /// static value) and `form` (managed by the dedicated Form designer, so it
    /// would just be filtered out of the Variables list) are intentionally
    /// omitted — both are still parsed/edited if an existing var uses them.
    static let knownTypes = [
        "date", "shell", "script", "clipboard", "random", "choice",
    ]

    /// Common date formats offered in the date picker (espanso uses strftime
    /// tokens). The first is the default. `Custom…` reveals a free-text field.
    static let dateFormatPresets: [String] = [
        "%a, %d %b %Y",     // Mon, 15 Jan 2024  (default)
        "%Y-%m-%d",         // 2024-01-15
        "%d/%m/%Y",         // 15/01/2024
        "%d %B %Y",         // 15 January 2024
        "%H:%M",            // 14:30
        "%Y-%m-%d %H:%M",   // 2024-01-15 14:30
    ]

    /// All IANA timezone identifiers (what espanso's date `tz` param expects).
    static let timezones: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    /// A live example of what `format` produces for the current date/time, via
    /// C `strftime` (whose tokens match the chrono ones espanso uses).
    static func dateExample(_ format: String) -> String {
        var timestamp = time_t(Date().timeIntervalSince1970)
        var parts = tm()
        localtime_r(&timestamp, &parts)
        var buffer = [Int8](repeating: 0, count: 256)
        let count = strftime(&buffer, buffer.count, format, &parts)
        return count > 0 ? String(cString: buffer) : format
    }

    /// SF Symbol for a variable type, shown in the type picker.
    static func symbol(for type: String) -> String {
        switch type {
        case "date": return "calendar"
        case "shell": return "terminal"
        case "script": return "chevron.left.forwardslash.chevron.right"
        case "clipboard": return "doc.on.clipboard"
        case "random": return "die.face.4"
        case "choice": return "list.bullet"
        case "echo": return "text.quote"
        case "form": return "rectangle.and.pencil.and.ellipsis"
        default: return "curlybraces"
        }
    }
}

/// A source of snippet files: a folder of YAML match files. The built-in source
/// is espanso's own `match/` dir; additional sources are user-added folders
/// (e.g. a shared drive) and can be marked read-only.
struct SnippetSource: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var isReadOnly: Bool
    var isBuiltIn: Bool

    /// Fixed id for the built-in (espanso match dir) source.
    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-0000000E5A50")!

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { isBuiltIn ? "My Snippets" : url.lastPathComponent }
}

/// One match file (`match/<name>.yml`) — maps to a category in the sidebar.
struct SnippetCategory: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var snippets: [Snippet]

    /// Which source this file belongs to, and whether it's read-only.
    var sourceID: UUID = SnippetSource.builtInID
    var isReadOnly: Bool = false

    /// True if the backing file is an online-only cloud placeholder (not
    /// downloaded). We deliberately don't read it — that would force a download —
    /// so its snippets aren't loaded and it's flagged for a warning instead.
    var isOnlineOnly: Bool = false

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
