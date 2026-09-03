import SwiftUI

struct ContentView: View {
    @StateObject private var store = SnippetStore()
    @State private var selectedCategoryID: SnippetCategory.ID?
    @State private var selectedSnippetIDs: Set<Snippet.ID> = []
    @State private var dropTargetID: SnippetCategory.ID?

    // New-category / rename / delete dialogs
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var renamingCategoryID: SnippetCategory.ID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var deletingCategoryID: SnippetCategory.ID?
    @State private var lastCategoryClickAt: Date?

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

    private func beginRename(_ category: SnippetCategory) {
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
            selectedCategoryID = category.id
            lastCategoryClickAt = now
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

    var body: some View {
        NavigationSplitView {
            // ---- Left: categories (files) ----
            List(selection: $selectedCategoryID) {
                Section("Categories") {
                    ForEach(store.categories) { category in
                        Group {
                            if renamingCategoryID == category.id {
                                // Opaque field background so the row's selection
                                // highlight doesn't bleed through and wash out the text.
                                TextField("Name", text: $renameText)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(nsColor: .textBackgroundColor)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Color.accentColor, lineWidth: 1.5))
                                    .focused($renameFieldFocused)
                                    .onAppear { DispatchQueue.main.async { renameFieldFocused = true } }
                                    .onSubmit(commitRename)
                                    .onExitCommand { renamingCategoryID = nil }
                            } else {
                                // One count-1 tap fires instantly (no double-click
                                // disambiguation lag): it selects, and a second click
                                // on the already-selected row renames — Finder-style.
                                Label(category.name, systemImage: "folder")
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
                                if moved { selectedSnippetIDs = [] }
                                return moved
                            } isTargeted: { targeted in
                                if targeted { dropTargetID = category.id }
                                else if dropTargetID == category.id { dropTargetID = nil }
                            }
                            .listRowBackground(
                                dropTargetID == category.id
                                    ? Color.accentColor.opacity(0.25) : Color.clear)
                            .contextMenu {
                                Button("Rename…") { beginRename(category) }
                                Button("Delete…", role: .destructive) {
                                    deletingCategoryID = category.id
                                }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 4) {
                    Button {
                        newCategoryName = ""
                        showNewCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New category")
                    Spacer()
                    // Placeholder for the ⚙︎ Preferences control (Phase 5).
                    Image(systemName: "gearshape").foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        } content: {
            // ---- Middle: snippets in the selected category ----
            if let category = selectedCategory {
                List(selection: $selectedSnippetIDs) {
                    ForEach(category.snippets) { snippet in
                        SnippetRow(primary: snippet.primaryText, preview: snippet.previewText)
                            .tag(snippet.id)
                            .draggable(dragPayload(for: snippet.id, in: category))
                    }
                }
                .navigationTitle(category.name)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button {
                            if let id = store.addSnippet(toCategory: category.id) {
                                selectedSnippetIDs = [id]
                            }
                        } label: {
                            Label("New Snippet", systemImage: "plus")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            } else {
                ContentUnavailableCompat("Select a category", systemImage: "folder")
            }
        } detail: {
            // ---- Right: snippet editor ----
            if let snippet = selectedSnippet, let categoryID = selectedCategoryID {
                SnippetEditor(
                    snippet: snippet,
                    onSave: { store.save($0, inCategory: categoryID) },
                    onDelete: {
                        store.deleteSnippet(snippet.id, inCategory: categoryID)
                        selectedSnippetIDs = []
                    }
                )
                .id(snippet.id)  // reset editor state when the selection changes
            } else if selectedSnippetIDs.count > 1 {
                ContentUnavailableCompat(
                    "\(selectedSnippetIDs.count) snippets selected",
                    systemImage: "square.stack.3d.up",
                    message: "Drag them onto a category in the sidebar to move them.")
            } else {
                ContentUnavailableCompat("Select a snippet", systemImage: "text.cursor")
            }
        }
        .onChange(of: selectedCategoryID) { _ in selectedSnippetIDs = [] }
        .alert("New Category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                if let id = store.addCategory(named: newCategoryName) {
                    selectedCategoryID = id
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a new match file in your espanso config.")
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
                    if selectedCategoryID == id { selectedCategoryID = nil }
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
            Text(primary).font(.body)
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SnippetEditor: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    let onDelete: () -> Void

    @State private var label: String
    @State private var triggersText: String
    @State private var replace: String
    @State private var vars: [SnippetVar]

    /// Only plain `replace` snippets are body-editable for now; markdown / html /
    /// form / image bodies are preserved untouched.
    private var replaceEditable: Bool {
        snippet.kind == .replace || snippet.kind == .other
    }

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onDelete: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onDelete = onDelete
        _label = State(initialValue: snippet.label ?? "")
        _triggersText = State(initialValue: snippet.triggers.joined(separator: "\n"))
        _replace = State(initialValue: snippet.replace ?? "")
        _vars = State(initialValue: snippet.vars)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Label") {
                    TextField("Optional description", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                section("Triggers") {
                    Text("One per line").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $triggersText)
                        .font(.body.monospaced())
                        .frame(minHeight: 54)
                        .editorChrome()
                }
                if replaceEditable {
                    section("Replacement") {
                        TextEditor(text: $replace)
                            .font(.body.monospaced())
                            .frame(minHeight: 160)
                            .editorChrome()
                    }
                } else {
                    section("Replacement (\(snippet.kind.rawValue))") {
                        Text("Editing \(snippet.kind.rawValue) snippets isn't supported yet — it's preserved as-is.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                section("Variables") {
                    Text("Reference these in the body as {{name}}.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($vars) { $variable in
                        VariableRow(
                            variable: $variable,
                            onInsert: { replace += "{{\(variable.name)}}" },
                            onDelete: { vars.removeAll { $0.id == variable.id } }
                        )
                    }
                    Button {
                        vars.append(SnippetVar(name: "var\(vars.count + 1)", type: "echo",
                                               params: [:], raw: [:]))
                    } label: {
                        Label("Add variable", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(snippet.primaryText)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                Button(action: save) {
                    Label("Save", systemImage: "checkmark")
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func save() {
        var updated = snippet
        updated.label = label.isEmpty ? nil : label
        updated.triggers = triggersText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if replaceEditable { updated.replace = replace }
        updated.vars = vars
        onSave(updated)
    }

    @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// One variable: name + type picker + type-aware parameter fields.
struct VariableRow: View {
    @Binding var variable: SnippetVar
    let onInsert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("name", text: $variable.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Picker("", selection: $variable.type) {
                    ForEach(SnippetVar.knownTypes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
                Button(action: onInsert) { Image(systemName: "arrow.up.left.square") }
                    .buttonStyle(.borderless)
                    .help("Insert {{\(variable.name)}} into the body")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            paramFields
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var paramFields: some View {
        switch variable.type {
        case "date":
            labeled("Format") { TextField("%Y-%m-%d", text: strParam("format")).textFieldStyle(.roundedBorder) }
            labeled("Timezone (optional)") { TextField("e.g. Europe/London", text: strParam("tz")).textFieldStyle(.roundedBorder) }
        case "echo":
            labeled("Text") { TextField("text to insert", text: strParam("echo")).textFieldStyle(.roundedBorder) }
        case "shell":
            labeled("Command") { TextField("echo \"hello\"", text: strParam("cmd")).textFieldStyle(.roundedBorder) }
        case "clipboard":
            Text("Inserts the current clipboard contents.").font(.caption).foregroundStyle(.secondary)
        case "random":
            labeled("Choices (one per line)") {
                TextEditor(text: listParam("choices")).font(.body.monospaced()).frame(height: 60).editorChrome()
            }
        case "script":
            labeled("Args (one per line)") {
                TextEditor(text: listParam("args")).font(.body.monospaced()).frame(height: 60).editorChrome()
            }
        default:
            Text("Editing \(variable.type) parameters isn't supported yet — preserved as-is.")
                .font(.caption).foregroundStyle(.secondary)
        }
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
                let items = $0.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                variable.params[key] = items.isEmpty ? nil : items
            }
        )
    }

    @ViewBuilder private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

private extension View {
    func editorChrome() -> some View {
        padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

/// Minimal fallback for ContentUnavailableView (macOS 14+) so we run on macOS 13.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let message: String?
    init(_ title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
