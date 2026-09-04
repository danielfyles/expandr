import Foundation

/// Launches the real `ExpandrForm` renderer to preview a form design, using the
/// same JSON contract espanso uses at expansion time.
enum FormPreview {
    enum PreviewError: LocalizedError {
        case rendererNotFound
        var errorDescription: String? {
            "Couldn't find the ExpandrForm renderer to preview with."
        }
    }

    /// Show a preview of `fields` (fire-and-forget; the user closes the window).
    static func show(title: String, fields: [FormFieldSpec]) throws {
        guard let bin = rendererBinary() else { throw PreviewError.rendererNotFound }

        var spec = FormBuilder.params(from: fields)
        spec["title"] = title.isEmpty ? "espanso" : title
        spec["max_form_width"] = 700
        spec["max_form_height"] = 500
        let data = try JSONSerialization.data(withJSONObject: spec)

        let process = Process()
        process.executableURL = bin
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()   // preview only; discard the result
        try process.run()
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.closeFile()
    }

    /// Locate the renderer: `$EXPANDR_FORM_BIN`, then the helper bundle next to
    /// this app, then the dev build product.
    private static func rendererBinary() -> URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["EXPANDR_FORM_BIN"],
           fm.isExecutableFile(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        // Sibling of this .app: build/ExpandrForm.app/Contents/MacOS/ExpandrForm
        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ExpandrForm.app/Contents/MacOS/ExpandrForm")
        if fm.isExecutableFile(atPath: sibling.path) { return sibling }
        return nil
    }
}
