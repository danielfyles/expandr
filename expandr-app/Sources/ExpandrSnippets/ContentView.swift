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

    /// One sidebar category row: either an in-place rename field or the folder
    /// label, plus drop target / selection / context-menu behaviour. Extracted
    /// from `body` so the type-checker isn't handed one giant expression.
    @ViewBuilder private func categoryRow(_ category: SnippetCategory) -> some View {
        Group {
            if renamingCategoryID == category.id {
                renameField
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
            if moved { selectedSnippetIDs = [] }
            return moved
        } isTargeted: { targeted in
            if targeted { dropTargetID = category.id }
            else if dropTargetID == category.id { dropTargetID = nil }
        }
        .listRowBackground(
            dropTargetID == category.id ? Color.accentColor.opacity(0.25) : Color.clear)
        .contextMenu {
            Button("Rename…") { beginRename(category) }
            Button("Delete…", role: .destructive) { deletingCategoryID = category.id }
        }
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
            List(selection: $selectedCategoryID) {
                Section("Categories") {
                    ForEach(store.categories) { category in
                        categoryRow(category)
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
                        SnippetRow(primary: snippet.listTitle, preview: snippet.listSubtitle)
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
            Text(primary).font(BrandFont.body(15, weight: 500)).lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .font(BrandFont.body(12))
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
    @State private var formFields: [FormFieldSpec]
    @State private var formVarName: String
    @State private var previewError: String?

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

        if let formVar = FormBuilder.formVar(in: snippet) {
            _formFields = State(initialValue: FormBuilder.parse(formVar))
            _formVarName = State(initialValue: formVar.name.isEmpty ? "form1" : formVar.name)
        } else {
            _formFields = State(initialValue: [])
            _formVarName = State(initialValue: "form1")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Label") {
                    TextField("Optional description", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                section("Triggers") {
                    Text("One per line").font(BrandFont.body(11)).foregroundStyle(.secondary)
                    TextEditor(text: $triggersText)
                        .font(.body.monospaced())
                        .frame(minHeight: 54)
                        .editorChrome()
                }
                section("Form") {
                    if !formFields.isEmpty {
                        FormEditor(
                            fields: $formFields,
                            varName: formVarName,
                            onInsertReference: { replace += $0 },
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

                section("Variables") {
                    // Form vars are managed by the Form designer above.
                    if vars.contains(where: { $0.type != "form" }) {
                        variablesSurface
                    } else {
                        variablePlaceholder
                    }
                }

                // Replacement comes last: it stitches together the trigger, form
                // fields and variables into the final output.
                if replaceEditable {
                    section("Replacement") {
                        TextEditor(text: $replace)
                            .font(.body.monospaced())
                            .frame(minHeight: 160)
                            .padding(6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.brandSage, lineWidth: 2.5))
                    }
                } else {
                    section("Replacement (\(snippet.kind.rawValue))") {
                        Text("Editing \(snippet.kind.rawValue) snippets isn't supported yet — it's preserved as-is.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
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
        .alert("Preview", isPresented: Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewError ?? "")
        }
    }

    /// Variable rows on the slate-blue surface, with the add button.
    private var variablesSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference these in the body as {{name}}.")
                .font(BrandFont.body(11)).foregroundStyle(Color.brandSlate.opacity(0.8))
            ForEach($vars) { $variable in
                if variable.type != "form" {
                    VariableRow(
                        variable: $variable,
                        onInsert: { replace += "{{\(variable.name)}}" },
                        onDelete: { vars.removeAll { $0.id == variable.id } })
                }
            }
            Button(action: addVariable) { Label("Add variable", systemImage: "plus") }
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
        vars.append(SnippetVar(name: "var\(vars.count + 1)", type: "echo", params: [:], raw: [:]))
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
        if formFields.isEmpty {
            formFields = [FormFieldSpec(
                label: "Name", name: "name", kind: .text, defaultValue: "", values: [])]
        }
    }

    private func runPreview() {
        do {
            try FormPreview.show(title: snippet.primaryText, fields: formFields)
        } catch {
            previewError = error.localizedDescription
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

        // Rebuild vars: keep non-form vars, re-serialise the form from the designer.
        var newVars = vars.filter { $0.type != "form" }
        if !formFields.isEmpty {
            var formVar = FormBuilder.formVar(in: snippet)
                ?? SnippetVar(name: formVarName, type: "form", params: [:], raw: [:])
            formVar.name = formVarName
            formVar.type = "form"
            formVar.params = FormBuilder.params(from: formFields)
            newVars.insert(formVar, at: 0)
        }
        updated.vars = newVars
        onSave(updated)
    }

    @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BrandFont.heading(15, weight: 600))
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
        .background(Color.brandCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.brandSlate.opacity(0.15)))
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
            Text(title).font(BrandFont.body(11)).foregroundStyle(.secondary)
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
