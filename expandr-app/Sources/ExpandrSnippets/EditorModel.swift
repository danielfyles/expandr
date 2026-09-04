import Foundation
import SwiftUI

/// The working copy of the snippet being edited. Lives above `SnippetEditor` so
/// the parent can tell whether there are unsaved changes (`isDirty`), build the
/// edited snippet to save, and guard navigation away.
@MainActor
final class EditorModel: ObservableObject {
    @Published var label = ""
    @Published var triggersText = ""
    @Published var replace = ""
    @Published var vars: [SnippetVar] = []
    @Published var formFields: [FormFieldSpec] = []
    @Published var formVarName = "form1"
    @Published private(set) var snippet: Snippet?

    private var baseline = ""

    /// Whether the plain replacement body is editable (form/markdown/etc. bodies
    /// are preserved untouched).
    var replaceEditable: Bool {
        guard let kind = snippet?.kind else { return true }
        return kind == .replace || kind == .other
    }

    var isDirty: Bool { snippet != nil && signature() != baseline }

    /// Load a snippet into the editor and reset the dirty baseline.
    func load(_ snippet: Snippet) {
        self.snippet = snippet
        label = snippet.label ?? ""
        triggersText = snippet.triggers.joined(separator: "\n")
        replace = snippet.replace ?? ""
        vars = snippet.vars
        if let formVar = FormBuilder.formVar(in: snippet) {
            formFields = FormBuilder.parse(formVar)
            formVarName = formVar.name.isEmpty ? "form1" : formVar.name
        } else {
            formFields = []
            formVarName = "form1"
        }
        baseline = signature()
    }

    func clear() { snippet = nil }

    /// Overlay the edited fields onto the loaded snippet.
    func buildSnippet() -> Snippet? {
        guard var updated = snippet else { return nil }
        updated.label = label.isEmpty ? nil : label
        updated.triggers = triggersText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if replaceEditable { updated.replace = replace }

        var newVars = vars.filter { $0.type != "form" }
        if !formFields.isEmpty {
            var formVar = FormBuilder.formVar(in: updated)
                ?? SnippetVar(name: formVarName, type: "form", params: [:], raw: [:])
            formVar.name = formVarName
            formVar.type = "form"
            formVar.params = FormBuilder.params(from: formFields)
            newVars.insert(formVar, at: 0)
        }
        updated.vars = newVars
        return updated
    }

    /// A stable string of the comparable fields, for dirty detection. Compares
    /// the *rebuilt* snippet against the rebuilt baseline, so regenerating a
    /// form's layout on load doesn't count as a change.
    private func signature() -> String {
        guard let s = buildSnippet() else { return "" }
        let obj: [String: Any] = [
            "label": s.label ?? "",
            "triggers": s.triggers,
            "replace": s.replace ?? "",
            "vars": s.vars.map(SnippetStore.varToDict),
        ]
        if JSONSerialization.isValidJSONObject(obj),
           let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return "\(obj)"
    }
}
