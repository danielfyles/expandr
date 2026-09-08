import Foundation
import Yams

/// Loads espanso match files from the built-in match dir plus any additional
/// (user-added) source folders, into categories/snippets grouped by source.
@MainActor
final class SnippetStore: ObservableObject {
    @Published var categories: [SnippetCategory] = []
    @Published var sources: [SnippetSource] = []
    @Published private(set) var additionalSources: [SnippetSource] = []
    @Published var loadError: String?

    let matchDir: URL?
    private let defaultsKey = "additionalSources"

    init() {
        self.matchDir = EspansoPaths.matchDir()
        additionalSources = Self.loadAdditionalSources()
        // Reconcile the config's managed include block with the stored sources,
        // in case it was lost (config regenerated) or is stale. The write is
        // idempotent — nothing is touched when it already matches, so this
        // doesn't needlessly trigger an espanso reload on every launch.
        updateEspansoIncludes()
        load()
    }

    // MARK: - Sources

    private static func loadAdditionalSources() -> [SnippetSource] {
        guard let data = UserDefaults.standard.data(forKey: "additionalSources"),
              let decoded = try? JSONDecoder().decode([SnippetSource].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistSources() {
        if let data = try? JSONEncoder().encode(additionalSources) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        updateEspansoIncludes()
    }

    /// The built-in source = espanso's own match dir.
    private var builtInSource: SnippetSource? {
        matchDir.map {
            SnippetSource(id: SnippetSource.builtInID, path: $0.path, isReadOnly: false, isBuiltIn: true)
        }
    }

    /// Add a folder as a source. If it already holds YAML files, just use them;
    /// otherwise seed one default file named after the folder. Returns it.
    @discardableResult
    func addSource(_ url: URL, readOnly: Bool = false) -> SnippetSource? {
        let standardized = url.standardizedFileURL
        guard !additionalSources.contains(where: { $0.url.standardizedFileURL == standardized }),
              standardized.standardizedFileURL != matchDir?.standardizedFileURL
        else { return nil }

        let fm = FileManager.default
        let existing = (try? matchFiles(in: url, fm: fm)) ?? []
        if existing.isEmpty {
            let seed = url.appendingPathComponent("\(url.lastPathComponent).yml")
            try? "matches: []\n".write(to: seed, atomically: true, encoding: .utf8)
        }
        let source = SnippetSource(id: UUID(), path: url.path, isReadOnly: readOnly, isBuiltIn: false)
        additionalSources.append(source)
        persistSources()
        load()
        return source
    }

    func removeSource(_ id: UUID) {
        additionalSources.removeAll { $0.id == id }
        persistSources()
        load()
    }

    func setSourceReadOnly(_ id: UUID, _ readOnly: Bool) {
        guard let i = additionalSources.firstIndex(where: { $0.id == id }) else { return }
        additionalSources[i].isReadOnly = readOnly
        persistSources()
        load()
    }

    // Markers delimiting the block we manage in `config/default.yml`, so we can
    // rewrite our settings without disturbing the user's comments/other settings.
    private static let includeMarkerStart = "# >>> Expandr managed sources — do not edit >>>"
    private static let includeMarkerEnd = "# <<< Expandr managed sources <<<"

    /// Reconcile our managed block in espanso's config. It holds the settings
    /// Expandr owns — silencing espanso's reload notifications (Expandr writes the
    /// files espanso watches often, so its default per-reload toast is just noise)
    /// — plus the additional-source include globs when there are any. Only our own
    /// delimited block is touched; everything else in the file is preserved.
    /// espanso auto-reloads config changes by default, so no explicit restart is
    /// needed for these to take effect.
    private func updateEspansoIncludes() {
        guard let configDir = EspansoPaths.configDir() else { return }
        let defaultYml = configDir.appendingPathComponent("config/default.yml")
        var text = (try? String(contentsOf: defaultYml, encoding: .utf8)) ?? ""

        // Strip any previously managed block (markers inclusive).
        if let range = managedBlockRange(in: text) {
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }

        // The block is always present once Expandr has run: it silences the
        // reload notifications, and carries the include globs when sources exist.
        var block = "\n\(Self.includeMarkerStart)\n"
        block += "show_notifications: false\n"
        let globs = additionalSources.map { "\($0.url.path)/*.yml" }
        if !globs.isEmpty {
            block += "extra_includes:\n"
            for glob in globs { block += "  - \(yamlQuoted(glob))\n" }
        }
        block += "\(Self.includeMarkerEnd)\n"
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += block

        // Idempotent: only write when the file would actually change, so a
        // launch-time reconcile doesn't churn the config (and espanso's watcher).
        let current = (try? String(contentsOf: defaultYml, encoding: .utf8))
        if current != text {
            try? text.write(to: defaultYml, atomically: true, encoding: .utf8)
        }
    }

    /// The character range of our managed block (start marker through end marker,
    /// inclusive of trailing newline), or nil if absent.
    private func managedBlockRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: Self.includeMarkerStart),
              let end = text.range(of: Self.includeMarkerEnd, range: start.upperBound..<text.endIndex)
        else { return nil }
        // Extend the end to swallow the rest of the marker's line.
        let lineEnd = text[end.upperBound...].firstIndex(where: \.isNewline)
        let upper = lineEnd.map { text.index(after: $0) } ?? text.endIndex
        return start.lowerBound..<upper
    }

    /// Double-quote a YAML scalar, escaping backslashes and quotes.
    private func yamlQuoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Loading

    func load() {
        var loadedSources: [SnippetSource] = []
        var allCategories: [SnippetCategory] = []
        let fm = FileManager.default

        if let builtIn = builtInSource {
            loadedSources.append(builtIn)
            allCategories += categories(in: builtIn.url, source: builtIn, fm: fm)
        }
        for source in additionalSources {
            loadedSources.append(source)
            allCategories += categories(in: source.url, source: source, fm: fm)
        }

        sources = loadedSources
        categories = allCategories
        loadError = (matchDir == nil)
            ? NSLocalizedString("Could not locate Expandr's snippets folder.", comment: "load error")
            : nil
    }

    /// Re-check availability and reload if it changed — e.g. the user just made a
    /// cloud folder "Available offline" (an online-only category can now be read),
    /// or a downloaded file got evicted. Called when the app regains focus /
    /// Settings opens, so warnings clear (and snippets load) without a relaunch.
    func revalidateAvailability() {
        let shouldReload = categories.contains { category in
            // Retry any online-only category (it may now be readable), and catch
            // a previously-loaded file that has since been evicted.
            category.isOnlineOnly || Self.isFileDataless(category.url)
        }
        if shouldReload { load() }
    }

    private func categories(in dir: URL, source: SnippetSource, fm: FileManager) -> [SnippetCategory] {
        guard let files = try? matchFiles(in: dir, fm: fm) else { return [] }
        return files.compactMap { url -> SnippetCategory? in
            // Load on access: reading faults in a pinned/available cloud file (or
            // downloads an online-only one while online). If the read fails —
            // we're offline and it was never downloaded — flag it online-only.
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                guard !source.isBuiltIn else { return nil }
                var category = SnippetCategory(url: url, snippets: [], rawTop: [:])
                category.sourceID = source.id
                category.isReadOnly = true
                category.isOnlineOnly = true
                return category
            }
            guard var category = Self.parseFile(text: text, url: url) else { return nil }
            category.sourceID = source.id
            category.isReadOnly = source.isReadOnly
            return category
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True if `url` is an online-only File Provider placeholder that hasn't been
    /// read/faulted in. Uses `lstat` metadata only (no download). Used to notice a
    /// previously-loaded file that Drive has since evicted.
    static func isFileDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        let sfDataless: UInt32 = 0x4000_0000  // SF_DATALESS
        if (info.st_flags & sfDataless) != 0 { return true }
        return info.st_size > 0 && info.st_blocks == 0
    }

    /// Top-level `.yml`/`.yaml` files in a directory (packages excluded for now).
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
        return parseFile(text: text, url: url)
    }

    /// Parse already-read YAML `text` into a SnippetCategory (nil if malformed).
    static func parseFile(text: String, url: URL) -> SnippetCategory? {
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
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              !categories[ci].isReadOnly else { return nil }
        let snippet = Snippet(
            label: nil, triggers: [":new"], regex: nil, replace: "",
            kind: .replace, vars: [], raw: [:])
        categories[ci].snippets.append(snippet)
        writeFile(categories[ci])
        return snippet.id
    }

    /// Create a new match file (category) in the given source's folder. Returns
    /// its id, or nil on failure.
    @discardableResult
    func addCategory(named rawName: String, in sourceID: UUID) -> SnippetCategory.ID? {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            loadError = NSLocalizedString("Unknown source.", comment: "error"); return nil
        }
        guard !source.isReadOnly else { loadError = NSLocalizedString("That source is read-only.", comment: "error"); return nil }
        let url = uniqueURL(for: sanitizedFileName(rawName), ext: "yml", in: source.url)
        do {
            try "matches: []\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            loadError = String(format: NSLocalizedString("Couldn't create category: %@", comment: "error"), error.localizedDescription)
            return nil
        }
        // Reload from disk so the new file is picked up and tagged to the right
        // source (a manual append into one section's filtered list doesn't
        // reliably re-render). Return the reloaded category's id for selection.
        load()
        return categories.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.id
    }

    /// Rename a category by moving its file. No-op if the name is unchanged.
    func renameCategory(_ categoryID: SnippetCategory.ID, to newName: String) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              !categories[ci].isReadOnly else { return }
        let dir = categories[ci].url.deletingLastPathComponent()
        let ext = categories[ci].url.pathExtension.isEmpty ? "yml" : categories[ci].url.pathExtension
        let base = sanitizedFileName(newName)
        if base == categories[ci].url.deletingPathExtension().lastPathComponent { return }
        let url = uniqueURL(for: base, ext: ext, in: dir)
        do {
            try FileManager.default.moveItem(at: categories[ci].url, to: url)
        } catch {
            loadError = String(format: NSLocalizedString("Couldn't rename category: %@", comment: "error"), error.localizedDescription)
            return
        }
        categories[ci].url = url
        sortCategories()
    }

    /// Delete a category by moving its file to the Trash (recoverable).
    func deleteCategory(_ categoryID: SnippetCategory.ID) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              !categories[ci].isReadOnly else { return }
        do {
            try FileManager.default.trashItem(at: categories[ci].url, resultingItemURL: nil)
        } catch {
            loadError = String(format: NSLocalizedString("Couldn't delete %@: %@", comment: "error: category name, reason"), categories[ci].name, error.localizedDescription)
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
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              !categories[ci].isReadOnly else { return }
        if let si = categories[ci].snippets.firstIndex(where: { $0.id == snippet.id }) {
            categories[ci].snippets[si] = snippet
        }
        writeFile(categories[ci])
    }

    /// Remove a snippet and write the file back.
    func deleteSnippet(_ snippetID: Snippet.ID, inCategory categoryID: SnippetCategory.ID) {
        guard let ci = categories.firstIndex(where: { $0.id == categoryID }),
              !categories[ci].isReadOnly else { return }
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
              !categories[srcCI].isReadOnly, !categories[targetCI].isReadOnly,
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
            loadError = String(format: NSLocalizedString("Couldn't save %@: %@", comment: "error: category name, reason"), category.name, error.localizedDescription)
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
        // The body key follows the snippet's kind, so switching a snippet between
        // plain (`replace`) and rich (`markdown`) in the editor swaps the key on
        // save; an HTML snippet converted to plain drops its `html` key. Kinds the
        // editor doesn't touch (form, image, other) keep whatever they had.
        switch s.kind {
        case .replace:
            if let replace = s.replace { d["replace"] = replace }
            d.removeValue(forKey: "markdown")
            d.removeValue(forKey: "html")
        case .markdown:
            if let markdown = s.markdown { d["markdown"] = markdown }
            d.removeValue(forKey: "replace")
            d.removeValue(forKey: "html")
        default:
            if let replace = s.replace { d["replace"] = replace }
        }
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
            markdown: m["markdown"] as? String,
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

        // Drop blank entries from string-array params (e.g. trailing/blank lines
        // left while editing script args or random choices). Nested dicts (a
        // form's `fields`) are left untouched.
        var params = v.params
        for (key, value) in params {
            guard let array = value as? [Any] else { continue }
            let strings = array.compactMap { $0 as? String }
            guard strings.count == array.count else { continue }  // only pure string arrays
            let cleaned = strings.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if cleaned.isEmpty { params.removeValue(forKey: key) } else { params[key] = cleaned }
        }

        if params.isEmpty { d.removeValue(forKey: "params") } else { d["params"] = params }
        return d
    }
}
