import SwiftUI

/// Renders an espanso form as a clean, full-width stack: each field gets a label
/// derived from the surrounding layout text, placed neatly above a full-width
/// control. Brand palette from expandr.app.
struct FormView: View {
    let spec: FormSpec
    private let fields: [FieldEntry]
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    @StateObject private var store: ValuesStore
    @FocusState private var focusedField: String?
    @StateObject private var focus = FocusController()

    /// One field to render: its name plus a display label from the layout.
    private struct FieldEntry: Identifiable {
        let name: String
        let label: String
        var id: String { name }
    }

    init(spec: FormSpec,
         onSubmit: @escaping ([String: String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.spec = spec
        self.fields = Self.orderedFields(from: parseLayout(spec.layout))
        self.onSubmit = onSubmit
        self.onCancel = onCancel

        var initial: [String: String] = [:]
        for entry in self.fields {
            let f = spec.fields[entry.name]
            if let def = f?.default, !def.isEmpty {
                initial[entry.name] = def
            } else if f?.kind == .choice || f?.kind == .list {
                initial[entry.name] = f?.values?.first ?? ""
            } else {
                initial[entry.name] = ""
            }
        }
        _store = StateObject(wrappedValue: ValuesStore(initial))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldsScroll
            buttonRow
        }
        .padding(24)
        .frame(width: 460)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.brandAccent.opacity(0.15)))
        .tint(.brandAccent)
        // Mirror focus, but ONLY for text fields. Routing a picker through
        // @FocusState on macOS 13 makes SwiftUI bounce focus back to the first
        // field (it can't focus the picker), which broke Tab-to-radio and arrows.
        // Pickers are driven entirely by the controller (ring + arrow keys).
        .onChange(of: focus.current) { newValue in
            let target = isTextField(newValue) ? newValue : nil
            if focusedField != target { focusedField = target }
        }
        .onChange(of: focusedField) { newValue in
            if let v = newValue, focus.current != v { focus.current = v }
        }
        .onAppear {
            focus.order = fields.map(\.name)
            focus.values = store
            for entry in fields {
                focus.kinds[entry.name] = spec.fields[entry.name]?.kind ?? .text
                if let opts = spec.fields[entry.name]?.values { focus.options[entry.name] = opts }
            }
            if focus.current == nil { focus.current = fields.first?.name }
            focus.start()
        }
        .onDisappear { focus.stop() }
    }

    /// Only text fields are driven through `@FocusState`; pickers are not.
    private func isTextField(_ name: String?) -> Bool {
        guard let name else { return false }
        return (spec.fields[name]?.kind ?? .text) == .text
    }

    private var fieldsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(fields) { entry in
                    fieldBlock(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxHeight: CGFloat(spec.maxFormHeight ?? 520))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button("Submit") { onSubmit(store.map) }
                .keyboardShortcut(.defaultAction)   // Enter always submits
                .buttonStyle(.borderedProminent)
        }
    }

    /// A radio group (used for `list` fields and short `choice` fields).
    @ViewBuilder private func radioControl(_ name: String, values: [String], binding: Binding<String>) -> some View {
        Picker("", selection: binding) {
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.radioGroup)
        .fixedSize()
        .padding(6)
        .overlay(focusRing(name, radius: 8))
    }

    /// The uniform brand focus ring, shown around whichever field is current.
    @ViewBuilder private func focusRing(_ name: String, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.brandAccent, lineWidth: 2)
            .opacity(focus.current == name ? 1 : 0)
    }

    private var background: some View {
        ZStack {
            Color.brandBG
            RadialGradient(
                colors: [Color.brandAccent.opacity(0.16), .clear],
                center: .top, startRadius: 0, endRadius: 340)
        }
    }

    @ViewBuilder private func fieldBlock(_ entry: FieldEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.label)
                .font(.system(size: 12.5, weight: .semibold, design: .serif))
                .foregroundStyle(Color.brandAccentDeep)
            control(entry.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func control(_ name: String) -> some View {
        let field = spec.fields[name]
        let binding = Binding(
            get: { store.map[name] ?? "" },
            set: { store.map[name] = $0 })

        switch field?.kind ?? .text {
        case .text:
            // Plain style (no AppKit blue ring); base border always, brand focus
            // ring when current.
            TextField("", text: binding)
                .textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.brandCard))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.brandAccent.opacity(0.28)))
                .overlay(focusRing(name, radius: 7))
                .focused($focusedField, equals: name)

        case .multiline:
            SubmittingTextEditor(
                text: binding,
                isFocused: focus.current == name,
                onSubmit: { onSubmit(store.map) },
                onFocus: { if focus.current != name { focus.current = name } })
                .frame(minHeight: 96)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.brandCard))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.brandAccent.opacity(0.35)))
                .overlay(focusRing(name, radius: 6))

        case .choice:
            // A short choice reads better as radios than a dropdown; only fall
            // back to a menu when there are many options.
            if (field?.values?.count ?? 0) <= 4 {
                radioControl(name, values: field?.values ?? [], binding: binding)
            } else {
                Picker("", selection: binding) {
                    ForEach(field?.values ?? [], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .overlay(focusRing(name, radius: 6))
            }

        case .list:
            radioControl(name, values: field?.values ?? [], binding: binding)
        }
    }

    // MARK: - Layout → ordered labelled fields

    /// Walk the parsed layout in order; each field's label is the nearest
    /// preceding text (inline or on a prior line), trimmed of trailing `:`/`,`.
    /// Fields with no preceding text fall back to a prettified name.
    private static func orderedFields(from rows: [[LayoutToken]]) -> [FieldEntry] {
        var entries: [FieldEntry] = []
        var seen = Set<String>()
        var pendingText = ""

        for row in rows {
            for token in row {
                switch token {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { pendingText = trimmed }
                case .field(let name):
                    if !seen.contains(name) {
                        seen.insert(name)
                        entries.append(FieldEntry(name: name, label: label(from: pendingText, fallback: name)))
                    }
                    pendingText = ""
                }
            }
        }
        return entries
    }

    private static func label(from text: String, fallback: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        while let last = s.last, last == ":" || last == "," { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        // Prettify the field name: underscores → spaces, capitalise first letter.
        let pretty = fallback.replacingOccurrences(of: "_", with: " ")
        return pretty.prefix(1).uppercased() + pretty.dropFirst()
    }
}
