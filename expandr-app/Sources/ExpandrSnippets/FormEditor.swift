import SwiftUI

/// The visual form designer: an ordered list of fields, plus add / preview.
struct FormEditor: View {
    @Binding var fields: [FormFieldSpec]
    let varName: String
    let onInsertReference: (String) -> Void
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These appear as a form when the trigger is typed.")
                .font(.system(size: 11)).foregroundStyle(Color.brandMuted)

            ForEach($fields) { $field in
                FormFieldRow(
                    field: $field,
                    onInsert: { onInsertReference("{{\(varName).\(field.name)}}") },
                    onDelete: { fields.removeAll { $0.id == field.id } })
            }

            HStack(spacing: 12) {
                Button {
                    let n = fields.count + 1
                    fields.append(FormFieldSpec(
                        label: "Field \(n)", name: "field\(n)", kind: .text,
                        defaultValue: "", values: []))
                } label: {
                    Label("Add field", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(.borderless)
                .disabled(fields.isEmpty)
            }
        }
    }
}

/// One row in the designer for a single form field.
struct FormFieldRow: View {
    @Binding var field: FormFieldSpec
    let onInsert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                labeled("Label", width: 150) {
                    TextField("Label", text: $field.label).textFieldStyle(.roundedBorder)
                }
                labeled("Name", width: 130) {
                    TextField("name", text: $field.name).textFieldStyle(.roundedBorder)
                }
                labeled("Type", width: 120) {
                    Picker("", selection: $field.kind) {
                        ForEach(FormFieldSpec.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                Spacer()
                Button(action: onInsert) { Image(systemName: "arrow.up.left.square") }
                    .buttonStyle(.borderless)
                    .help("Insert {{…\(field.name)}} into the body")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            if field.kind == .choice || field.kind == .list {
                labeledBlock("Options (one per line)") {
                    TextEditor(text: valuesBinding)
                        .font(.body.monospaced()).frame(height: 64).editorChrome()
                }
            }
            labeledBlock("Default (optional)") {
                TextField("", text: $field.defaultValue).textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(Color.brandCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.brandAccent.opacity(0.15)))
    }

    private var valuesBinding: Binding<String> {
        Binding(
            get: { field.values.joined(separator: "\n") },
            set: {
                field.values = $0.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            })
    }

    @ViewBuilder private func labeled(_ title: String, width: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            content()
        }
        .frame(width: width)
    }

    @ViewBuilder private func labeledBlock(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            content()
        }
    }
}
