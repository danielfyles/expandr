import SwiftUI

struct ContentView: View {
    @StateObject private var store = SnippetStore()
    @State private var selectedCategoryID: SnippetCategory.ID?
    @State private var selectedSnippetID: Snippet.ID?

    private var selectedCategory: SnippetCategory? {
        store.categories.first { $0.id == selectedCategoryID }
    }
    private var selectedSnippet: Snippet? {
        selectedCategory?.snippets.first { $0.id == selectedSnippetID }
    }

    var body: some View {
        NavigationSplitView {
            // ---- Left: categories (files) ----
            List(selection: $selectedCategoryID) {
                Section("Categories") {
                    ForEach(store.categories) { category in
                        Label(category.name, systemImage: "folder")
                            .badge(category.snippets.count)
                            .tag(category.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                // Placeholder for the ⚙︎ Preferences control (Phase 5).
                HStack {
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                    Text("Preferences").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
            }
        } content: {
            // ---- Middle: snippets in the selected category ----
            if let category = selectedCategory {
                List(selection: $selectedSnippetID) {
                    ForEach(category.snippets) { snippet in
                        SnippetRow(primary: snippet.primaryText, preview: snippet.previewText)
                            .tag(snippet.id)
                    }
                }
                .navigationTitle(category.name)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
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
                        selectedSnippetID = nil
                    }
                )
                .id(snippet.id)  // reset editor state when the selection changes
            } else {
                ContentUnavailableCompat("Select a snippet", systemImage: "text.cursor")
            }
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
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
