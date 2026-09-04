import SwiftUI

/// The visual form designer: an ordered list of fields (drag the ≡ handle to
/// reorder — the dragged row follows the cursor while the others slide open a
/// gap), plus add / preview.
///
/// Reorder strategy: the `fields` array is NOT mutated during a drag (that was
/// the old flicker/stutter cause — mutating + reading back animating frames
/// every tick). Instead the drag only moves render offsets; the array is
/// reordered once, on drop.
struct FormEditor: View {
    @Binding var fields: [FormFieldSpec]
    let varName: String
    let onInsertReference: (String) -> Void
    let onPreview: () -> Void

    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragTargetIndex: Int?
    @State private var heights: [UUID: CGFloat] = [:]
    @State private var frozenHeights: [UUID: CGFloat] = [:]  // snapshot for the drag

    private let spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("These appear as a form when the trigger is typed.")
                .font(.system(size: 11)).foregroundStyle(Color.brandMuted)

            ForEach($fields) { $field in
                let id = field.id
                let index = fields.firstIndex { $0.id == id } ?? 0
                FormFieldRow(
                    field: $field,
                    isDragging: draggingID == id,
                    onInsert: { onInsertReference("{{\(varName).\(field.name)}}") },
                    onDelete: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        fields.removeAll { $0.id == id } } },
                    onDragChanged: { handleDrag(id, translation: $0) },
                    onDragEnded: endDrag)
                    .equatable()  // don't re-render the row's body during a drag
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: RowHeightKey.self, value: [id: geo.size.height])
                    })
                    .offset(y: rowOffset(id: id, index: index))
                    .zIndex(draggingID == id ? 1 : 0)
                    // Animate ONLY the non-dragged rows, and only on target
                    // changes — the dragged row must track the cursor un-animated.
                    .animation(draggingID == id ? nil
                               : .spring(response: 0.3, dampingFraction: 0.78),
                               value: dragTargetIndex)
            }

            HStack(spacing: 12) {
                Button {
                    let n = fields.count + 1
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        fields.append(FormFieldSpec(
                            label: "Field \(n)", name: "field\(n)", kind: .text,
                            defaultValue: "", values: []))
                    }
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
        // Don't churn heights mid-drag (the dragged row scales, which would keep
        // re-firing this and re-rendering during the gesture).
        .onPreferenceChange(RowHeightKey.self) { if draggingID == nil { heights = $0 } }
    }

    /// Render offset for a row: the dragged row tracks the cursor; the rows
    /// between its origin and the target slot shift to open a gap.
    private func rowOffset(id: UUID, index: Int) -> CGFloat {
        if draggingID == id { return dragTranslation }
        guard let draggingID,
              let from = fields.firstIndex(where: { $0.id == draggingID }),
              let to = dragTargetIndex, from != to else { return 0 }
        let gap = (frozenHeights[draggingID] ?? 44) + spacing
        if to > from, index > from, index <= to { return -gap }   // rows slide up
        if to < from, index >= to, index < from { return gap }    // rows slide down
        return 0
    }

    private func handleDrag(_ id: UUID, translation: CGFloat) {
        if draggingID != id {
            draggingID = id
            frozenHeights = heights  // snapshot; never re-measured mid-drag
        }
        // Set both directly (no withAnimation): the row-level `.animation(value:)`
        // scopes the spring to `dragTargetIndex` only, so the cursor-follow offset
        // is never swept into an animation transaction.
        dragTranslation = translation
        dragTargetIndex = targetIndex(for: id, translation: translation)
    }

    /// The slot the dragged row would land in, from the drag distance and the
    /// (fixed, snapshot) heights of the rows it passes. No array mutation, so no
    /// feedback/flicker.
    private func targetIndex(for id: UUID, translation: CGFloat) -> Int {
        guard let from = fields.firstIndex(where: { $0.id == id }) else { return 0 }
        var target = from
        if translation > 0 {
            var travelled: CGFloat = 0
            var i = from + 1
            while i < fields.count {
                let step = (frozenHeights[fields[i].id] ?? 44) + spacing
                travelled += step
                if translation > travelled - step / 2 { target = i } else { break }
                i += 1
            }
        } else if translation < 0 {
            var travelled: CGFloat = 0
            var i = from - 1
            while i >= 0 {
                let step = (frozenHeights[fields[i].id] ?? 44) + spacing
                travelled += step
                if -translation > travelled - step / 2 { target = i } else { break }
                i -= 1
            }
        }
        return target
    }

    private func endDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            if let draggingID,
               let from = fields.firstIndex(where: { $0.id == draggingID }),
               let to = dragTargetIndex, from != to {
                let item = fields.remove(at: from)
                fields.insert(item, at: to)
            }
            draggingID = nil
            dragTranslation = 0
            dragTargetIndex = nil
        }
        frozenHeights = [:]
    }
}

/// Collects each row's height for the drag maths.
private struct RowHeightKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// One row in the designer for a single form field.
///
/// `Equatable` (used via `.equatable()`) so SwiftUI skips re-rendering the row's
/// (expensive: text fields, pickers, AppKit editors) body while the drag only
/// changes offsets. Only the field's data and drag state matter; the closures
/// are ignored.
struct FormFieldRow: View, Equatable {
    @Binding var field: FormFieldSpec
    var isDragging: Bool = false
    let onInsert: () -> Void
    let onDelete: () -> Void
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    static func == (lhs: FormFieldRow, rhs: FormFieldRow) -> Bool {
        lhs.field == rhs.field && lhs.isDragging == rhs.isDragging
    }

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
                Button(action: onInsert) { Image(systemName: "arrow.down.square") }
                    .buttonStyle(.borderless)
                    .help("Insert {{…\(field.name)}} into the body")
                dragHandle
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            if field.kind == .choice || field.kind == .list {
                labeledBlock("Options (one per line)") {
                    GrowingTextEditor(text: valuesBinding, minHeight: 64).editorChrome()
                }
            }
            labeledBlock("Default (optional)") {
                TextField("", text: $field.defaultValue).textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(Color.brandCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.brandAccent.opacity(isDragging ? 0.55 : 0.15),
                          lineWidth: isDragging ? 2 : 1))
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 6, y: 3)
    }

    /// The ≡ reorder handle. High-priority, low min-distance so it grabs
    /// immediately and beats the surrounding ScrollView.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(isDragging ? Color.brandAccent : .secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .onHover { inside in
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            // GLOBAL coordinate space is essential: the gesture lives on the
            // handle inside the row we offset, so a .local translation would be
            // measured in a frame that the offset itself moves — a feedback loop
            // that makes the row vibrate and lag the cursor. Global is fixed.
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { _ in onDragEnded() })
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
