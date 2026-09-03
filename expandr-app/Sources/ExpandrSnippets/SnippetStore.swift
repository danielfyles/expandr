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

    // MARK: - Creating & deleting

    /// Append a fresh snippet to a category and write the file. Returns its id so
    /// the UI can select it for editing.
    @discardableResult
    func addSnippet(toCategory categoryID: SnippetCategory.ID) -> Snippet.ID? {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }) else { return nil }
        let snippet = Snippet(
            label: nil, triggers: [":new"], regex: nil, replace: "",
            kind: .replace, vars: [], raw: [:])
        categories[ci].snippets.append(snippet)
        writeFile(categories[ci])
        return snippet.id
    }

    /// Create a new match file (category). Returns its id, or nil on failure.
    @discardableResult
    func addCategory(named rawName: String) -> SnippetCategory.ID? {
        guard let matchDir else { loadError = "No config directory."; return nil }
        let url = uniqueURL(for: sanitizedFileName(rawName), ext: "yml", in: matchDir)
        do {
            try "matches: []\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            loadError = "Couldn't create category: \(error.localizedDescription)"
            return nil
        }
        let category = SnippetCategory(url: url, snippets: [], rawTop: [:])
        categories.append(category)
        sortCategories()
        return category.id
    }

    /// Rename a category by moving its file. No-op if the name is unchanged.
    func renameCategory(_ categoryID: SnippetCategory.ID, to newName: String) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              let matchDir else { return }
        let ext = categories[ci].url.pathExtension.isEmpty ? "yml" : categories[ci].url.pathExtension
        let base = sanitizedFileName(newName)
        if base == categories[ci].url.deletingPathExtension().lastPathComponent { return }
        let url = uniqueURL(for: base, ext: ext, in: matchDir)
        do {
            try FileManager.default.moveItem(at: categories[ci].url, to: url)
        } catch {
            loadError = "Couldn't rename category: \(error.localizedDescription)"
            return
        }
        categories[ci].url = url
        sortCategories()
    }

    /// Delete a category by moving its file to the Trash (recoverable).
    func deleteCategory(_ categoryID: SnippetCategory.ID) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        do {
            try FileManager.default.trashItem(at: categories[ci].url, resultingItemURL: nil)
        } catch {
            loadError = "Couldn't delete \(categories[ci].name): \(error.localizedDescription)"
            return
        }
        categories.remove(at: ci)
    }

    // MARK: - Helpers

    private func sanitizedFileName(_ s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// A URL for `base.ext` in `dir`, suffixing `-2`, `-3`, … to avoid clobbering.
    private func uniqueURL(for base: String, ext: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return url
    }

    private func sortCategories() {
        categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// Move a snippet to another category, rewriting both files. The source
    /// category is found by id so a drag needs only the snippet's id. No-op if
    /// the snippet is already in the target. Returns true if it moved.
    @discardableResult
    func moveSnippet(_ snippetID: Snippet.ID, toCategory targetID: SnippetCategory.ID) -> Bool {
        guard let targetCI = categories.firstIndex(where: { $0.id == targetID }),
              let srcCI = categories.firstIndex(where: {
                  $0.snippets.contains { $0.id == snippetID }
              }),
              srcCI != targetCI,
              let si = categories[srcCI].snippets.firstIndex(where: { $0.id == snippetID })
        else { return false }

        let snippet = categories[srcCI].snippets.remove(at: si)
        categories[targetCI].snippets.append(snippet)
        writeFile(categories[srcCI])
        writeFile(categories[targetCI])
        return true
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
