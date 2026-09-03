import Foundation
import Yams

/// Loads espanso match files into categories/snippets. (Phase 0: read-only.)
@MainActor
final class SnippetStore: ObservableObject {
    @Published var categories: [SnippetCategory] = []
    @Published var loadError: String?

    let matchDir: URL?

    init() {
        self.matchDir = EspansoPaths.matchDir()
        load()
    }

    func load() {
        guard let matchDir else {
            loadError = "Could not locate espanso's config directory."
            return
        }
        let fm = FileManager.default
        guard let files = try? matchFiles(in: matchDir, fm: fm) else {
            loadError = "No match files found in \(matchDir.path)."
            categories = []
            return
        }

        var loaded: [SnippetCategory] = []
        for url in files {
            if let category = Self.parseFile(url) {
                loaded.append(category)
            }
        }
        categories = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loadError = loaded.isEmpty ? "No snippet files yet in \(matchDir.path)." : nil
    }

    /// Top-level `.yml`/`.yaml` files under `match/`, excluding the `packages`
    /// dir (packages are managed separately) for now.
    private func matchFiles(in dir: URL, fm: FileManager) throws -> [URL] {
        let entries = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return entries.filter {
            ["yml", "yaml"].contains($0.pathExtension.lowercased())
        }
    }

    /// Parse one match file into a SnippetCategory. Returns nil on unreadable files.
    static func parseFile(_ url: URL) -> SnippetCategory? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Empty file → empty category.
        guard let top = (try? Yams.load(yaml: text)) as? [String: Any] else {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SnippetCategory(url: url, snippets: [], rawTop: [:])
            }
            return nil
        }

        let rawMatches = (top["matches"] as? [Any]) ?? []
        let snippets = rawMatches.compactMap { $0 as? [String: Any] }.map(parseMatch)

        var rawTop = top
        rawTop["matches"] = nil  // matches are modelled separately
        return SnippetCategory(url: url, snippets: snippets, rawTop: rawTop)
    }

    // MARK: - Writing

    /// Replace a snippet in its category and write the file back to disk.
    func save(_ snippet: Snippet, inCategory categoryID: SnippetCategory.ID) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        if let si = categories[ci].snippets.firstIndex(where: { $0.id == snippet.id }) {
            categories[ci].snippets[si] = snippet
        }
        writeFile(categories[ci])
    }

    /// Remove a snippet and write the file back.
    func deleteSnippet(_ snippetID: Snippet.ID, inCategory categoryID: SnippetCategory.ID) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[ci].snippets.removeAll { $0.id == snippetID }
        writeFile(categories[ci])
    }

    private func writeFile(_ category: SnippetCategory) {
        var top = category.rawTop
        top["matches"] = category.snippets.map(Self.snippetToDict)
        do {
            // Emit block scalars for multi-line strings so replacements read well.
            let yaml = try Yams.dump(object: top, width: -1)
            try yaml.write(to: category.url, atomically: true, encoding: .utf8)
            loadError = nil
        } catch {
            loadError = "Couldn't save \(category.name): \(error.localizedDescription)"
        }
    }

    /// Overlay the edited fields onto the match's original mapping, so fields we
    /// don't model (vars, word, force_mode, …) are preserved.
    static func snippetToDict(_ s: Snippet) -> [String: Any] {
        var d = s.raw
        d.removeValue(forKey: "trigger")
        d.removeValue(forKey: "triggers")
        if s.triggers.count == 1 {
            d["trigger"] = s.triggers[0]
        } else if s.triggers.count > 1 {
            d["triggers"] = s.triggers
        }
        if let label = s.label, !label.isEmpty { d["label"] = label } else { d.removeValue(forKey: "label") }
        if let regex = s.regex, !regex.isEmpty { d["regex"] = regex }
        if let replace = s.replace { d["replace"] = replace }
        d.removeValue(forKey: "vars")
        if !s.vars.isEmpty { d["vars"] = s.vars.map(varToDict) }
        return d
    }

    static func parseMatch(_ m: [String: Any]) -> Snippet {
        var triggers: [String] = []
        if let t = m["trigger"] as? String { triggers = [t] }
        if let ts = m["triggers"] as? [Any] { triggers = ts.compactMap { $0 as? String } }

        let kind: Snippet.EffectKind
        if m["replace"] != nil { kind = .replace }
        else if m["markdown"] != nil { kind = .markdown }
        else if m["html"] != nil { kind = .html }
        else if m["form"] != nil { kind = .form }
        else if m["image_path"] != nil { kind = .image }
        else { kind = .other }

        let vars = (m["vars"] as? [Any])?
            .compactMap { $0 as? [String: Any] }
            .map(parseVar) ?? []

        return Snippet(
            label: m["label"] as? String,
            triggers: triggers,
            regex: m["regex"] as? String,
            replace: m["replace"] as? String,
            kind: kind,
            vars: vars,
            raw: m
        )
    }

    static func parseVar(_ v: [String: Any]) -> SnippetVar {
        SnippetVar(
            name: v["name"] as? String ?? "",
            type: v["type"] as? String ?? "echo",
            params: (v["params"] as? [String: Any]) ?? [:],
            raw: v
        )
    }

    static func varToDict(_ v: SnippetVar) -> [String: Any] {
        var d = v.raw
        d["name"] = v.name
        d["type"] = v.type
        if v.params.isEmpty { d.removeValue(forKey: "params") } else { d["params"] = v.params }
        return d
    }
}
