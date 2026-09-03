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

        return Snippet(
            label: m["label"] as? String,
            triggers: triggers,
            regex: m["regex"] as? String,
            replace: m["replace"] as? String,
            kind: kind,
            raw: m
        )
    }
}
