import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: SnippetStore
    @State private var selectedCategoryID: SnippetCategory.ID?
    @State private var selectedSnippetIDs: Set<Snippet.ID> = []
    @State private var dropTargetID: SnippetCategory.ID?

    // New-category / rename / delete dialogs
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var newCategorySourceID: UUID?
    @State private var renamingCategoryID: SnippetCategory.ID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var deletingCategoryID: SnippetCategory.ID?
    @State private var lastCategoryClickAt: Date?
    // The source whose "not downloaded" explanation modal is open (from a
    // sidebar warning ⚠️).
    @State private var offlineInfoSource: SnippetSource?

    // The lifted editor state + a pending navigation held back by unsaved changes.
    @StateObject private var editor = EditorModel()
    @State private var pendingNav: PendingNav?

    // Snippet search (matches trigger + replacement); ⌘F focuses the field.
    @State private var snippetSearch = ""
    @FocusState private var searchFocused: Bool

    // Remember the last-selected category (by name — ids are regenerated each
    // load) across launches; the snippet selection is intentionally not restored.
    @AppStorage("lastCategoryName") private var lastCategoryName = ""
    @State private var didRestoreCategory = false

    private enum PendingNav {
        case snippets(Set<Snippet.ID>)
        case category(SnippetCategory.ID?)
        case newCategoryPrompt   // open the name dialog after resolving
    }

    private var selectedCategory: SnippetCategory? {
        store.categories.first { $0.id == selectedCategoryID }
    }
    /// The editor targets a single selection; multi-select shows a summary instead.
    private var selectedSnippet: Snippet? {
        guard selectedSnippetIDs.count == 1, let id = selectedSnippetIDs.first else { return nil }
        return selectedCategory?.snippets.first { $0.id == id }
    }

    /// `isPresented` binding driven by the "which id am I acting on" state, so
    /// dismissing the dialog clears the id.
    private var deletingBinding: Binding<Bool> {
        Binding(get: { deletingCategoryID != nil },
                set: { if !$0 { deletingCategoryID = nil } })
    }

    /// Snap any window back onto a visible screen. A remembered window position
    /// can point at a monitor that's since been disconnected or rearranged, which
    /// would open the window off-screen where it looks like nothing happened.
    private func ensureWindowsOnScreen() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible {
                let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
                if !onScreen { window.center() }
            }
        }
    }

    /// Open the Preferences (Settings) window by selecting the same menu item the
    /// SwiftUI `Settings` scene installs — `performActionForItem` dispatches it
    /// exactly as a real menu pick, which is more reliable than sending the
    /// private selector down the responder chain ourselves.
    private func openSettings() {
        guard let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else { return }
        let index = appMenu.items.firstIndex { menuItem in
            if let action = menuItem.action {
                let name = NSStringFromSelector(action)
                if name.contains("showSettings") || name.contains("showPreferences") { return true }
            }
            return menuItem.title.hasPrefix("Settings") || menuItem.title.hasPrefix("Preferences")
        }
        if let index { appMenu.performActionForItem(at: index) }
    }

    private func beginRename(_ category: SnippetCategory) {
        guard !category.isReadOnly else { return }
        renameText = category.name
        renamingCategoryID = category.id
    }

    /// Instant single-click selection; a second click on the already-selected
    /// category (within ~½s) starts an in-place rename.
    private func handleCategoryClick(_ category: SnippetCategory) {
        let now = Date()
        if selectedCategoryID == category.id,
           let last = lastCategoryClickAt, now.timeIntervalSince(last) < 0.5 {
            beginRename(category)
            lastCategoryClickAt = nil
        } else {
            requestCategory(category.id)
            lastCategoryClickAt = now
        }
    }

    // MARK: - Navigation guarded by unsaved changes

    private var pendingNavBinding: Binding<Bool> {
        Binding(get: { pendingNav != nil }, set: { if !$0 { pendingNav = nil } })
    }

    /// Request a new snippet selection; hold it back behind a prompt if dirty.
    private func requestSnippets(_ new: Set<Snippet.ID>) {
        if editor.isDirty && new != selectedSnippetIDs {
            pendingNav = .snippets(new)
        } else {
            applySnippets(new)
        }
    }

    private func applySnippets(_ new: Set<Snippet.ID>) {
        selectedSnippetIDs = new
        // Resolve across all categories so a global search result loads from —
        // and saves back to — its own folder.
        if new.count == 1, let id = new.first,
           let category = store.categories.first(where: { $0.snippets.contains { $0.id == id } }),
           let snippet = category.snippets.first(where: { $0.id == id }) {
            selectedCategoryID = category.id
            editor.load(snippet)
        } else {
            editor.clear()
        }
    }

    private func requestCategory(_ id: SnippetCategory.ID?) {
        if editor.isDirty && id != selectedCategoryID {
            pendingNav = .category(id)
        } else {
            applyCategory(id)
        }
    }

    private func applyCategory(_ id: SnippetCategory.ID?) {
        selectedCategoryID = id
        selectedSnippetIDs = []
        snippetSearch = ""
        editor.clear()
        if let category = store.categories.first(where: { $0.id == id }) {
            lastCategoryName = category.name
        }
    }

    /// Restore the last-selected category on launch (by name); fall back to the
    /// first if it's gone. Runs once.
    private func restoreCategorySelection() {
        guard !didRestoreCategory else { return }
        didRestoreCategory = true
        guard selectedCategoryID == nil else { return }
        let match = store.categories.first { $0.name == lastCategoryName }
            ?? store.categories.first
        if let match { applyCategory(match.id) }
    }

    /// Resolve the unsaved-changes prompt: optionally save, then navigate.
    private func resolvePending(save: Bool) {
        if save, let categoryID = selectedCategoryID {
            saveCurrent(categoryID: categoryID)
        }
        switch pendingNav {
        case .snippets(let new): applySnippets(new)
        case .category(let id): applyCategory(id)
        case .newCategoryPrompt:
            // Open the name dialog on the next runloop so it doesn't collide with
            // the confirmation dialog that's dismissing.
            DispatchQueue.main.async { newCategoryName = ""; showNewCategory = true }
        case .none: break
        }
        pendingNav = nil
    }

    private func startNewCategory(for sourceID: UUID) {
        newCategorySourceID = sourceID
        if editor.isDirty {
            pendingNav = .newCategoryPrompt
        } else {
            newCategoryName = ""
            showNewCategory = true
        }
    }

    private func saveCurrent(categoryID: SnippetCategory.ID) {
        guard let updated = editor.buildSnippet() else { return }
        store.save(updated, inCategory: categoryID)
        editor.load(updated)  // reset the dirty baseline
    }

    private func deleteCurrent(categoryID: SnippetCategory.ID) {
        guard let snippet = editor.snippet else { return }
        store.deleteSnippet(snippet.id, inCategory: categoryID)
        editor.clear()
        selectedSnippetIDs = []
    }

    /// The dashed "New Snippet" placeholder pinned above the snippet list.
    private func newSnippetPlaceholder(_ category: SnippetCategory) -> some View {
        Button {
            if let id = store.addSnippet(toCategory: category.id) {
                requestSnippets([id])
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .foregroundStyle(Color.accentColor)
                Text("New Snippet")
                    .foregroundStyle(.primary)  // match the snippet-row text colour
                    .offset(y: 1.5)  // optical nudge: the serif text reads high vs the +
            }
            .font(BrandFont.body(15, weight: 500))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            // The content's own top gap sets the row height, so the dashed border
            // (drawn as the row background, matching selection width) lines up with
            // the content vertically.
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
    }

    /// Delete a snippet from a swipe/context action, keeping selection + editor
    /// consistent if it happened to be the open one.
    private func deleteSnippetRow(_ snippet: Snippet, in category: SnippetCategory) {
        store.deleteSnippet(snippet.id, inCategory: category.id)
        selectedSnippetIDs.remove(snippet.id)
        if editor.snippet?.id == snippet.id {
            editor.clear()
        }
    }

    /// Commit an in-place category rename (Enter or focus loss). Esc cancels by
    /// clearing `renamingCategoryID` before this runs, so the guard no-ops.
    private func commitRename() {
        if let id = renamingCategoryID { store.renameCategory(id, to: renameText) }
        renamingCategoryID = nil
    }

    /// Payload for dragging `id`: if it's part of a multi-selection, drag every
    /// selected snippet (in list order), one id per line; otherwise just this one.
    private func dragPayload(for id: Snippet.ID, in category: SnippetCategory) -> String {
        if selectedSnippetIDs.contains(id) && selectedSnippetIDs.count > 1 {
            return category.snippets
                .filter { selectedSnippetIDs.contains($0.id) }
                .map { $0.id.uuidString }
                .joined(separator: "\n")
        }
        return id.uuidString
    }

    /// One sidebar category row: either an in-place rename field or the folder
    /// label, plus drop target / selection / context-menu behaviour. Extracted
    /// from `body` so the type-checker isn't handed one giant expression.
    @ViewBuilder private func categoryRow(_ category: SnippetCategory) -> some View {
        Group {
            if renamingCategoryID == category.id {
                renameField
            } else if category.isOnlineOnly {
                // Online-only cloud file: a red warning in place of the count.
                HStack(spacing: 4) {
                    Label {
                        Text(category.name).font(BrandFont.heading(14, weight: 540))
                    } icon: {
                        Image(systemName: "folder")
                    }
                    Spacer()
                    Button {
                        offlineInfoSource = store.sources.first { $0.id == category.sourceID }
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Not downloaded — click to learn more")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleCategoryClick(category) }
            } else {
                // One count-1 tap fires instantly (no double-click disambiguation
                // lag): it selects, and a second click on the already-selected row
                // renames — Finder-style.
                Label {
                    Text(category.name).font(BrandFont.heading(14, weight: 540))
                } icon: {
                    Image(systemName: "folder")
                }
                .badge(category.snippets.count)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleCategoryClick(category) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(category.id)
        .dropDestination(for: String.self) { items, _ in
            var moved = false
            for item in items {
                for line in item.split(whereSeparator: \.isNewline) {
                    guard let sid = UUID(uuidString: String(line)) else { continue }
                    if store.moveSnippet(sid, toCategory: category.id) { moved = true }
                }
            }
            if moved { selectedSnippetIDs = []; editor.clear() }
            return moved
        } isTargeted: { targeted in
            if targeted { dropTargetID = category.id }
            else if dropTargetID == category.id { dropTargetID = nil }
        }
        .listRowBackground(
            dropTargetID == category.id ? Color.accentColor.opacity(0.25) : Color.clear)
        .contextMenu {
            if category.isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
            } else {
                Button("Rename…") { beginRename(category) }
                Button("Delete…", role: .destructive) { deletingCategoryID = category.id }
            }
        }
    }

    /// The categories belonging to one source, in the order the store holds them.
    private func categoryRows(for source: SnippetSource) -> [SnippetCategory] {
        store.categories.filter { $0.sourceID == source.id }
    }

    /// A sidebar section header: the source's name, a lock if read-only, and a
    /// "+" to create a new category in that source (hidden when read-only).
    @ViewBuilder private func sourceHeader(_ source: SnippetSource) -> some View {
        HStack(spacing: 4) {
            Text(source.displayName)
            if source.isReadOnly {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if !source.isReadOnly {
                Button { startNewCategory(for: source.id) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New category in \(source.displayName)")
                // Align the "+" with the trailing edge of the per-row folder
                // counts (badges), which sit further in than the section header.
                .padding(.trailing, 16)
            }
        }
    }

    /// A hash of the sidebar's structure — sources and their categories (identity
    /// and name, not snippet counts, so editing snippets doesn't rebuild the
    /// sidebar). Used as the List's `.id` so add/rename/delete/source changes
    /// force a clean rebuild.
    private var sidebarSignature: Int {
        var hasher = Hasher()
        for s in store.sources {
            hasher.combine(s.id); hasher.combine(s.isReadOnly); hasher.combine(s.displayName)
        }
        for c in store.categories {
            hasher.combine(c.id); hasher.combine(c.sourceID); hasher.combine(c.name)
            hasher.combine(c.isOnlineOnly)
        }
        return hasher.finalize()
    }

    private var isSearching: Bool {
        !snippetSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Does a snippet match the query (trigger or replacement, case-insensitive)?
    private func matches(_ snippet: Snippet, _ query: String) -> Bool {
        snippet.triggers.contains { $0.lowercased().contains(query) }
            || (snippet.replace?.lowercased().contains(query) ?? false)
    }

    /// Matching snippets across ALL categories, with their owning category.
    private var globalSearchResults: [(snippet: Snippet, category: SnippetCategory)] {
        let query = snippetSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return store.categories.flatMap { category in
            category.snippets.filter { matches($0, query) }
                .map { (snippet: $0, category: category) }
        }
    }

    /// Category snippets in list order: sorted by their trigger (falling back to
    /// regex/label via `primaryText`) — the canonical identity of a snippet —
    /// 0-9 then A-Z (case-insensitive, natural number ordering), rather than the
    /// order they happen to sit in the file.
    private func sortedSnippets(_ category: SnippetCategory) -> [Snippet] {
        category.snippets.sorted {
            $0.primaryText.localizedStandardCompare($1.primaryText) == .orderedAscending
        }
    }

    /// The normal list of a category's snippets (with drag, delete, New Snippet).
    @ViewBuilder private func categorySnippetsList(_ category: SnippetCategory) -> some View {
        List(selection: Binding(get: { selectedSnippetIDs }, set: { requestSnippets($0) })) {
            ForEach(sortedSnippets(category)) { snippet in
                SnippetRow(primary: snippet.listTitle, preview: snippet.listSubtitle)
                    .tag(snippet.id)
                    .draggable(dragPayload(for: snippet.id, in: category))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !category.isReadOnly {
                            Button(role: .destructive) {
                                deleteSnippetRow(snippet, in: category)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .contextMenu {
                        if !category.isReadOnly {
                            Button("Delete", role: .destructive) {
                                deleteSnippetRow(snippet, in: category)
                            }
                        }
                    }
            }
            if !category.isReadOnly {
                newSnippetPlaceholder(category)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8).strokeBorder(
                            Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .padding(.top, 10)
                            .padding(.horizontal, 10))
            }
        }
    }

    /// Flat list of global search results; each row shows its category.
    @ViewBuilder private var searchResultsList: some View {
        let results = globalSearchResults
        if results.isEmpty {
            ContentUnavailableCompat("No matches", systemImage: "magnifyingglass",
                                     message: "No snippet's trigger or replacement contains “\(snippetSearch)”.")
        } else {
            List(selection: Binding(get: { selectedSnippetIDs }, set: { requestSnippets($0) })) {
                ForEach(results, id: \.snippet.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        SnippetRow(primary: item.snippet.listTitle, preview: item.snippet.listSubtitle)
                        Text(item.category.name).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .tag(item.snippet.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !item.category.isReadOnly {
                            Button(role: .destructive) {
                                deleteSnippetRow(item.snippet, in: item.category)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .contextMenu {
                        if !item.category.isReadOnly {
                            Button("Delete", role: .destructive) {
                                deleteSnippetRow(item.snippet, in: item.category)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The always-visible search field pinned above the snippet list.
    private var snippetSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search snippets", text: $snippetSearch)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { snippetSearch = ""; searchFocused = false }
            if !snippetSearch.isEmpty {
                Button { snippetSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// In-place rename field. Opaque background so the row's selection highlight
    /// doesn't bleed through and wash out the text.
    private var renameField: some View {
        TextField("Name", text: $renameText)
            .textFieldStyle(.plain)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .focused($renameFieldFocused)
            .onAppear { DispatchQueue.main.async { renameFieldFocused = true } }
            .onSubmit(commitRename)
            .onExitCommand { renamingCategoryID = nil }
    }

    var body: some View {
        NavigationSplitView {
            // ---- Left: categories (files) ----
            // While searching, drop the selection highlight and dim the sidebar.
            List(selection: Binding(get: { isSearching ? nil : selectedCategoryID },
                                    set: { requestCategory($0) })) {
                ForEach(store.sources) { source in
                    Section {
                        ForEach(categoryRows(for: source)) { category in
                            categoryRow(category)
                        }
                    } header: {
                        sourceHeader(source)
                    }
                }
            }
            // Rebuild the sidebar when the set of sources/categories changes.
            // SwiftUI's nested section ForEach doesn't reliably re-render a
            // section's rows when `categories` is reassigned live (e.g. after
            // adding a folder), so key the List on a content signature.
            .id(sidebarSignature)
            // Pale panda watermark at the foot of the sidebar, behind the rows.
            .background(alignment: .bottom) { SidebarWatermark() }
            .opacity(isSearching ? 0.45 : 1)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            // Preferences lives in the sidebar's toolbar, just left of the
            // system's sidebar-toggle button (which is pinned at the trailing edge).
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: openSettings) {
                        Label("Preferences", systemImage: "gearshape")
                    }
                    .help("Preferences")
                }
            }
        } content: {
            // ---- Middle: snippets (a category's, or global search results) ----
            // The search field is a stable sibling (not a safeAreaInset on the
            // switching list) so it keeps focus when the list swaps to results.
            VStack(spacing: 0) {
                snippetSearchField
                Group {
                    if isSearching {
                        searchResultsList
                    } else if let category = selectedCategory, category.isOnlineOnly {
                        ContentUnavailableCompat(
                            "Not downloaded", systemImage: "exclamationmark.triangle",
                            message: "This folder is stored in the cloud and isn't available offline yet, so its snippets aren't loaded. Make the folder available offline to use them.")
                    } else if let category = selectedCategory {
                        categorySnippetsList(category)
                    } else {
                        ContentUnavailableCompat("Select a category", systemImage: "folder")
                    }
                }
            }
            .navigationTitle(isSearching ? "" : (selectedCategory?.name ?? ""))
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            // ---- Right: snippet editor ----
            if editor.snippet != nil, let categoryID = selectedCategoryID {
                SnippetEditor(
                    editor: editor,
                    isReadOnly: selectedCategory?.isReadOnly ?? false,
                    onSave: { saveCurrent(categoryID: categoryID) },
                    onDelete: { deleteCurrent(categoryID: categoryID) })
            } else if selectedSnippetIDs.count > 1 {
                ContentUnavailableCompat(
                    "\(selectedSnippetIDs.count) snippets selected",
                    systemImage: "square.stack.3d.up",
                    message: "Drag them onto a category in the sidebar to move them.")
            } else {
                ContentUnavailableCompat("Select a snippet", systemImage: "text.cursor")
            }
        }
        .confirmationDialog(
            "You have unsaved changes", isPresented: pendingNavBinding, titleVisibility: .visible
        ) {
            Button("Save") { resolvePending(save: true) }
            Button("Discard", role: .destructive) { resolvePending(save: false) }
            Button("Cancel", role: .cancel) { pendingNav = nil }
        } message: {
            Text("Save your changes to this snippet before continuing?")
        }
        .alert("New Category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                // Unsaved changes were already resolved before this dialog opened.
                if let sid = newCategorySourceID,
                   let id = store.addCategory(named: newCategoryName, in: sid) {
                    applyCategory(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let name = store.sources.first { $0.id == newCategorySourceID }?.displayName
            Text("Creates a new folder of snippets in \(name ?? NSLocalizedString("this source", comment: "fallback source name")).")
        }
        .onChange(of: renameFieldFocused) { focused in
            // Blur commits the in-place rename (unless Esc already cancelled it).
            if !focused && renamingCategoryID != nil { commitRename() }
        }
        .confirmationDialog(
            "Delete this category?", isPresented: deletingBinding, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let id = deletingCategoryID {
                    if selectedCategoryID == id { applyCategory(nil) }
                    store.deleteCategory(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file and all its snippets will be moved to the Trash.")
        }
        .overlay(alignment: .bottom) {
            if let error = store.loadError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .onAppear {
            restoreCategorySelection()
            EngineService.ensureRunning()  // register+start the bundled engine (no-op in dev)
            ensureWindowsOnScreen()        // never open off-screen on a since-disconnected monitor
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from Finder (e.g. after making a folder available
            // offline) re-checks online-only state and reloads if it changed.
            store.revalidateAvailability()
        }
        .sheet(item: $offlineInfoSource) { source in
            OfflineWarningView(source: source) { offlineInfoSource = nil }
        }
        .background {
            // ⌘F focuses the snippet search field.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// Stores the display strings (not the whole `Snippet`) so SwiftUI's view diffing
/// re-renders when a trigger/label changes. `Snippet`'s `==` only compares `id`
/// (its `raw` dict isn't Equatable), so passing the struct would let SwiftUI
/// short-circuit and show a stale row after an edit.
struct SnippetRow: View {
    let primary: String
    let preview: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primary).font(BrandFont.body(15, weight: 500)).lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .font(BrandFont.body(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

struct SnippetEditor: View {
    @ObservedObject var editor: EditorModel
    var isReadOnly: Bool = false
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var previewError: String?
    @StateObject private var insertionTarget = TextInsertionTarget()
    @StateObject private var richController = RichTextController()
    @State private var confirmPlainSwitch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isReadOnly {
                    Label("Read-only — from a source you've marked read-only in Settings.",
                          systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
                section("Label") {
                    TextField("Optional description", text: $editor.label)
                        .textFieldStyle(.roundedBorder)
                }
                let triggerCount = editor.triggersText.split(whereSeparator: \.isNewline)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                section(triggerCount > 1 ? "Triggers" : "Trigger") {
                    Text("One per line").font(.system(size: 11)).foregroundStyle(.secondary)
                    GrowingTextEditor(text: $editor.triggersText, minHeight: 54,
                                      isEditable: !isReadOnly)
                        .editorChrome()
                }
                optionalSections

                // Replacement comes last: it stitches together the trigger, form
                // fields and variables into the final output.
                if editor.replaceEditable {
                    section("Replacement", accessory: {
                        HStack(spacing: 10) { cursorMarkerButton; bodyModePicker }
                    }) {
                        bodyNotes
                        if editor.bodyMode == .rich {
                            VStack(spacing: 6) {
                                RichFormattingBar(controller: richController)
                                RichTextEditor(text: $editor.richBody, minHeight: 120,
                                               isEditable: !isReadOnly,
                                               insertionTarget: insertionTarget,
                                               controller: richController)
                            }
                            .padding(6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.brandSage, lineWidth: 2.5))
                        } else {
                            GrowingTextEditor(text: $editor.replace, minHeight: 120,
                                              isEditable: !isReadOnly,
                                              insertionTarget: insertionTarget)
                                .padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.brandSage, lineWidth: 2.5))
                        }
                    }
                    .alert("Switch to plain text?", isPresented: $confirmPlainSwitch) {
                        Button("Switch", role: .destructive) { editor.switchToPlain() }
                        Button("Keep formatting", role: .cancel) {}
                    } message: {
                        Text("Bold, lists, links and other formatting will be removed.")
                    }
                } else {
                    let kind = editor.snippet?.kind.rawValue ?? "this"
                    section("Replacement (\(kind))") {
                        Text("Editing \(kind) snippets isn't supported yet — it's preserved as-is.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isReadOnly)
        }
        .navigationTitle(editor.snippet?.primaryText ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isReadOnly {
                    Label("Read-only", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    Button(action: onSave) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editor.isDirty)
                }
            }
        }
        .alert("Preview", isPresented: Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewError ?? "")
        }
    }

    /// The Form + Variables sections. Un-added ones are grouped under an
    /// "Optional" heading behind a single continuous left rule (heading included,
    /// content reaching the right edge); an added one is pulled out flush. Once
    /// both are added the heading and rule are gone.
    @ViewBuilder private var optionalSections: some View {
        let formAdded = !editor.formFields.isEmpty
        let varsAdded = editor.vars.contains { $0.type != "form" }
        VStack(alignment: .leading, spacing: 18) {
            if formAdded && varsAdded {
                formSection
                variablesSection
            } else if formAdded {
                formSection
                lined { optionalHeading; variablesSection }
            } else if varsAdded {
                lined { optionalHeading; formSection }
                variablesSection
            } else {
                lined { optionalHeading; formSection; variablesSection }
            }
        }
    }

    private var optionalHeading: some View {
        Text("Optional").font(BrandFont.heading(15, weight: 600)).foregroundStyle(.secondary)
    }

    private var formSection: some View {
        section("Form") {
            if !editor.formFields.isEmpty {
                FormEditor(
                    fields: $editor.formFields,
                    varName: editor.formVarName,
                    replaceText: editor.replace,
                    onInsertReference: { insertionTarget.insert($0) },
                    onPreview: runPreview)
                    .padding(14)
                    .background(FormSurfaceBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.brandAccent.opacity(0.18), lineWidth: 2.5))
            } else {
                formPlaceholder
            }
        }
    }

    private var variablesSection: some View {
        section("Variables") {
            // Form vars are managed by the Form designer above.
            if editor.vars.contains(where: { $0.type != "form" }) { variablesSurface }
            else { variablePlaceholder }
        }
    }

    /// Wrap content behind one continuous left rule + indent, reaching the right edge.
    @ViewBuilder private func lined<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 18) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Variable rows on the slate-blue surface, with the add button.
    private var variablesSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert each variable in the Replacement text using its variable name inside curly brackets like this: {{example}}")
                .font(.system(size: 11)).foregroundStyle(Color.brandSlate.opacity(0.8))
            ForEach($editor.vars) { $variable in
                if variable.type != "form" {
                    VariableRow(
                        variable: $variable,
                        isReferenced: !variable.name.isEmpty
                            && editor.replace.contains("{{\(variable.name)}}"),
                        onInsert: { insertionTarget.insert("{{\(variable.name)}}") },
                        onDelete: { editor.vars.removeAll { $0.id == variable.id } })
                }
            }
            Button(action: addVariable) { Label("Add another variable", systemImage: "plus") }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(VariableSurfaceBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brandSlate.opacity(0.18), lineWidth: 2.5))
    }

    /// The dashed slate-blue placeholder shown when there are no variables yet.
    private var variablePlaceholder: some View {
        Button(action: addVariable) {
            VStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.title2).foregroundStyle(Color.brandSlate)
                Text("Add variable")
                    .font(BrandFont.heading(15, weight: 600)).foregroundStyle(Color.brandSlate)
                Text("Insert dynamic values — dates, shell output, the clipboard and more")
                    .font(BrandFont.body(13)).foregroundStyle(Color.brandSlate.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(VariableSurfaceBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                Color.brandSlate.opacity(0.4),
                style: StrokeStyle(lineWidth: 2.5, dash: [6, 4])))
    }

    private func addVariable() {
        editor.vars.append(SnippetVar(
            name: "var\(editor.vars.count + 1)", type: "date",
            params: ["format": SnippetVar.dateFormatPresets[0]], raw: [:]))
    }

    /// The dashed cream placeholder shown when the snippet has no form yet.
    private var formPlaceholder: some View {
        Button(action: addForm) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.title2).foregroundStyle(Color.brandAccentDeep)
                Text("Add a form")
                    .font(BrandFont.heading(15, weight: 600)).foregroundStyle(Color.brandAccentDeep)
                Text("Show a fill-in form when this trigger is typed")
                    .font(BrandFont.body(13)).foregroundStyle(Color.brandMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FormSurfaceBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                Color.brandAccent.opacity(0.5),
                style: StrokeStyle(lineWidth: 2.5, dash: [6, 4])))
    }

    private func addForm() {
        if editor.formFields.isEmpty {
            editor.formFields = [FormFieldSpec(
                label: "Name", name: "name", kind: .text, defaultValue: "", values: [])]
        }
    }

    private func runPreview() {
        do {
            try FormPreview.show(title: editor.snippet?.primaryText ?? "Preview", fields: editor.formFields)
        } catch {
            previewError = error.localizedDescription
        }
    }

    /// Plain ⇄ rich. Going rich is lossless; going plain asks first when there is
    /// formatting to lose.
    private var bodyModePicker: some View {
        Picker("", selection: Binding(
            get: { editor.bodyMode },
            set: { newMode in
                if newMode == .rich { editor.switchToRich() }
                else if editor.richHasFormatting { confirmPlainSwitch = true }
                else { editor.switchToPlain() }
            })) {
            Text("Plain text").tag(EditorModel.BodyMode.plain)
            Text("Rich text").tag(EditorModel.BodyMode.rich)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()   // natural width, so its right edge sits flush with the text area
    }

    @ViewBuilder private var bodyNotes: some View {
        if editor.convertedFromHTML {
            Text("This snippet was HTML. Its formatting has been removed; saving keeps the plain text.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if editor.bodyMode == .rich && editor.hasUnsupportedMarkdown {
            Text("Some of this snippet's Markdown isn't supported by the editor; saving will simplify it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BrandFont.heading(15, weight: 600))
            content()
        }
    }

    /// A section whose heading carries a trailing accessory (e.g. a small button).
    @ViewBuilder private func section(_ title: LocalizedStringKey,
                                      @ViewBuilder accessory: () -> some View,
                                      @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(BrandFont.heading(15, weight: 600))
                Spacer()
                accessory()
            }
            content()
        }
    }

    /// Drops the cursor marker `$|$` at the insertion point, exactly like
    /// inserting a variable. After expansion the caret lands there instead of
    /// at the end of the replacement.
    private var cursorMarkerButton: some View {
        // espanso honours a single marker, so disable once one is present.
        let alreadyPlaced = editor.bodyMode == .rich
            ? editor.richBody.string.contains("$|$")
            : editor.replace.contains("$|$")
        return Button {
            insertionTarget.insert("$|$")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.square")
                    .font(.system(size: 10, weight: .semibold))
                Text("Insert cursor")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(alreadyPlaced)
        .help("Insert $|$ — where the cursor will be after the snippet expands")
    }
}

/// One variable: name + type picker + type-aware parameter fields.
struct VariableRow: View {
    @Binding var variable: SnippetVar
    var isReferenced: Bool = true   // false → the insert icon reddens as a cue
    let onInsert: () -> Void
    let onDelete: () -> Void

    /// Whether the date format is a bespoke string (dropdown on "Custom…").
    @State private var dateIsCustom = false
    private static let customDateTag = "\u{1}custom"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                labeled("Variable type") {
                Picker("", selection: Binding(
                    get: { variable.type },
                    set: { newType in
                        // Changing type starts the new type's params fresh, so a
                        // previous type's params (e.g. shell `cmd`) don't linger
                        // invisibly or get written to the file.
                        guard newType != variable.type else { return }
                        variable.type = newType
                        if newType == "date" {
                            variable.params = ["format": SnippetVar.dateFormatPresets[0]]
                            dateIsCustom = false
                        } else {
                            variable.params = [:]
                        }
                    })
                ) {
                    // Keep the current type selectable even if it's not offered
                    // (e.g. a legacy `echo` var), so it isn't silently changed.
                    let types = SnippetVar.knownTypes.contains(variable.type)
                        ? SnippetVar.knownTypes
                        : [variable.type] + SnippetVar.knownTypes
                    ForEach(types, id: \.self) { type in
                        Label(type, systemImage: SnippetVar.symbol(for: type)).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                }
                labeled("Variable name") {
                    TextField("name", text: $variable.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                Spacer()
                Button(action: onInsert) {
                    Image(systemName: "arrow.down.square")
                        .foregroundStyle(isReferenced ? Color.accentColor : Color.red)
                }
                    .buttonStyle(.borderless)
                    .help("Insert {{\(variable.name)}} into the body")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            paramFields
        }
        .padding(8)
        .background(Color.brandCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.brandSlate.opacity(0.15)))
        .onAppear {
            // A date whose format isn't one of the presets starts in Custom mode.
            if variable.type == "date" {
                let current = variable.params["format"] as? String ?? ""
                dateIsCustom = !SnippetVar.dateFormatPresets.contains(current)
            }
        }
    }

    /// Dropdown selection ↔ the stored `format` string; "Custom…" reveals a field.
    private var dateFormatSelection: Binding<String> {
        Binding(
            get: {
                if dateIsCustom { return Self.customDateTag }
                let current = variable.params["format"] as? String ?? ""
                return SnippetVar.dateFormatPresets.contains(current) ? current : Self.customDateTag
            },
            set: { newValue in
                if newValue == Self.customDateTag {
                    dateIsCustom = true
                } else {
                    dateIsCustom = false
                    variable.params["format"] = newValue
                }
            })
    }

    /// Timezone dropdown ↔ the stored `tz` param ("" = system default, unset).
    private var tzSelection: Binding<String> {
        Binding(
            get: { variable.params["tz"] as? String ?? "" },
            set: { newValue in
                if newValue.isEmpty { variable.params.removeValue(forKey: "tz") }
                else { variable.params["tz"] = newValue }
            })
    }

    @ViewBuilder private var paramFields: some View {
        switch variable.type {
        case "date":
            labeled("Format") {
                Picker("", selection: dateFormatSelection) {
                    ForEach(SnippetVar.dateFormatPresets, id: \.self) { format in
                        Text(SnippetVar.dateExample(format)).tag(format)
                    }
                    Text("Custom…").tag(Self.customDateTag)
                }
                .labelsHidden()
            }
            if dateIsCustom {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Custom date/time format (uses strftime syntax)").font(.system(size: 11)).foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://www.strfti.me/")!) {
                            HStack(spacing: 3) {
                                Text("www.strfti.me")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.system(size: 11))
                        }
                        .help("strftime format reference (strfti.me)")
                    }
                    TextField("%Y-%m-%d", text: strParam("format")).textFieldStyle(.roundedBorder)
                }
            }
            labeled("Timezone") {
                let current = variable.params["tz"] as? String ?? ""
                Picker("", selection: tzSelection) {
                    Text("System default").tag("")
                    if !current.isEmpty && !SnippetVar.timezones.contains(current) {
                        Text(current).tag(current)  // keep an unknown value selectable
                    }
                    ForEach(SnippetVar.timezones, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        case "echo":
            labeled("Text") { TextField("text to insert", text: strParam("echo")).textFieldStyle(.roundedBorder) }
        case "shell":
            labeled("Command") {
                GrowingTextEditor(
                    text: strParam("cmd"), minHeight: 54,
                    placeholder: "echo \"Look ma, no typing!\"").editorChrome()
            }
        case "clipboard":
            Text("Inserts the current clipboard contents.").font(.caption).foregroundStyle(.secondary)
        case "random":
            labeled("Choices (one per line)") {
                GrowingTextEditor(text: listParam("choices"), minHeight: 60).editorChrome()
            }
        case "script":
            labeled("Args (one per line)") {
                GrowingTextEditor(text: listParam("args"), minHeight: 60).editorChrome()
            }
        case "choice":
            if choiceHasLabelledValues {
                Text("This choice uses labelled options (label/id) — preserved as-is; edit the file directly to change them.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                labeled("Options (one per line)") {
                    GrowingTextEditor(text: listParam("values"), minHeight: 60).editorChrome()
                }
                Text("A pick-list appears when the trigger is typed; the chosen option is inserted.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        default:
            Text("Editing \(variable.type) parameters isn't supported yet — preserved as-is.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// True if a choice var's values include label/id objects (not plain
    /// strings), which the simple options editor shouldn't clobber.
    private var choiceHasLabelledValues: Bool {
        guard let values = variable.params["values"] as? [Any] else { return false }
        return values.contains { !($0 is String) }
    }

    private func strParam(_ key: String) -> Binding<String> {
        Binding(
            get: { variable.params[key] as? String ?? "" },
            set: { variable.params[key] = $0.isEmpty ? nil : $0 }
        )
    }

    private func listParam(_ key: String) -> Binding<String> {
        Binding(
            get: { (variable.params[key] as? [Any])?.compactMap { $0 as? String }.joined(separator: "\n") ?? "" },
            set: {
                // Lossless split/join so newlines (incl. trailing/blank) survive
                // while typing; empty entries are cleaned up when the file is saved.
                variable.params[key] = $0.components(separatedBy: "\n")
            }
        )
    }

    @ViewBuilder private func labeled(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            content()
        }
    }
}

extension View {
    func editorChrome() -> some View {
        padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

/// Minimal fallback for ContentUnavailableView (macOS 14+) so we run on macOS 13.
struct ContentUnavailableCompat: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey?
    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(BrandFont.heading(17)).foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(BrandFont.body(13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
