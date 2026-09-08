import Foundation
import SwiftUI
import AppKit

/// The working copy of the snippet being edited. Lives above `SnippetEditor` so
/// the parent can tell whether there are unsaved changes (`isDirty`), build the
/// edited snippet to save, and guard navigation away.
///
/// The body has two modes. **Plain** edits `replace:` as text. **Rich** edits an
/// attributed string with basic formatting and saves it as `markdown:` (see
/// `MarkdownRichText`). Switching modes changes which key the file gets on save.
@MainActor
final class EditorModel: ObservableObject {
    enum BodyMode: String { case plain, rich }

    @Published var label = ""
    @Published var triggersText = ""
    @Published var replace = ""                        // plain body
    @Published var richBody = NSAttributedString()     // rich body, rendered from Markdown
    @Published var bodyMode: BodyMode = .plain
    @Published var vars: [SnippetVar] = []
    @Published var formFields: [FormFieldSpec] = []
    @Published var formVarName = "form1"
    @Published private(set) var snippet: Snippet?
    /// An `html:` snippet was opened: its tags were stripped to plain text.
    @Published private(set) var convertedFromHTML = false
    /// A `markdown:` snippet uses syntax the rich editor can't round-trip.
    @Published private(set) var hasUnsupportedMarkdown = false

    private var baseline = ""

    /// Whether the body is editable at all (form and image bodies are preserved
    /// untouched). Plain, rich (Markdown) and HTML snippets all are.
    var replaceEditable: Bool {
        guard let kind = snippet?.kind else { return true }
        switch kind {
        case .replace, .other, .markdown, .html: return true
        default: return false
        }
    }

    var isDirty: Bool { snippet != nil && signature() != baseline }

    /// Whether switching to plain text would drop formatting.
    var richHasFormatting: Bool { MarkdownRichText.hasFormatting(richBody) }

    /// Load a snippet into the editor and reset the dirty baseline.
    func load(_ snippet: Snippet) {
        self.snippet = snippet
        label = snippet.label ?? ""
        triggersText = snippet.triggers.joined(separator: "\n")
        convertedFromHTML = false
        hasUnsupportedMarkdown = false
        switch snippet.kind {
        case .markdown:
            let md = snippet.markdown ?? ""
            bodyMode = .rich
            richBody = MarkdownRichText.attributedString(fromMarkdown: md)
            replace = ""
            hasUnsupportedMarkdown = MarkdownRichText.hasUnsupportedSyntax(md)
        case .html:
            // We don't edit HTML: show it as plain text with the formatting removed.
            // Nothing is written unless the user saves.
            bodyMode = .plain
            replace = MarkdownRichText.plainText(fromHTML: (snippet.raw["html"] as? String) ?? "")
            richBody = NSAttributedString()
            convertedFromHTML = true
        default:
            bodyMode = .plain
            replace = snippet.replace ?? ""
            richBody = NSAttributedString()
        }
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

    /// Plain → rich: lossless — the text becomes an unformatted rich body.
    func switchToRich() {
        guard bodyMode == .plain else { return }
        richBody = NSAttributedString(string: replace, attributes: MarkdownRichText.bodyAttributes)
        bodyMode = .rich
    }

    /// Rich → plain: keeps the text, drops the formatting. Callers confirm with the
    /// user first when `richHasFormatting`.
    func switchToPlain() {
        guard bodyMode == .rich else { return }
        replace = MarkdownRichText.plainText(from: richBody)
        bodyMode = .plain
    }

    /// Overlay the edited fields onto the loaded snippet.
    func buildSnippet() -> Snippet? {
        guard var updated = snippet else { return nil }
        updated.label = label.isEmpty ? nil : label
        updated.triggers = triggersText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if replaceEditable {
            switch bodyMode {
            case .plain:
                updated.replace = replace
                updated.markdown = nil
                // HTML converted to text, or rich switched to plain, becomes `replace:`.
                if updated.kind != .other { updated.kind = .replace }
            case .rich:
                updated.markdown = MarkdownRichText.markdown(from: richBody)
                updated.replace = nil
                updated.kind = .markdown
            }
        }

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
    /// the *rebuilt* snippet against the rebuilt baseline, so normalising a form
    /// layout or Markdown on load doesn't count as a change.
    private func signature() -> String {
        guard let s = buildSnippet() else { return "" }
        let obj: [String: Any] = [
            "label": s.label ?? "",
            "triggers": s.triggers,
            "kind": s.kind.rawValue,
            "replace": s.replace ?? "",
            "markdown": s.markdown ?? "",
            "vars": s.vars.map(SnippetStore.varToDict),
        ]
        if JSONSerialization.isValidJSONObject(obj),
           let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return "\(obj)"
    }
}
