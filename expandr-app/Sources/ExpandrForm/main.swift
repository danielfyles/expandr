import AppKit
import SwiftUI

// Read the form spec from stdin (espanso pipes JSON and closes the pipe).
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard let spec = try? JSONDecoder().decode(FormSpec.self, from: inputData) else {
    FileHandle.standardError.write(Data("expandr-form: could not decode form spec from stdin\n".utf8))
    exit(1)
}

/// Write the result as JSON to stdout. An empty object means "cancelled", which
/// espanso maps to `None` (no expansion).
func emit(_ dict: [String: String]) {
    if let data = try? JSONSerialization.data(withJSONObject: dict) {
        FileHandle.standardOutput.write(data)
    }
}

/// A borderless window that can still take keyboard focus (borderless windows
/// refuse key/main status by default, which would break text entry).
final class FormWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FormWindowController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let spec: FormSpec
    private var window: NSWindow!
    private var finished = false

    init(spec: FormSpec) { self.spec = spec }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = FormView(
            spec: spec,
            onSubmit: { [weak self] values in self?.finish(values) },
            onCancel: { [weak self] in self?.finish([:]) })

        let hosting = NSHostingView(rootView: root)
        // Borderless so there is no title bar at all — the form draws its own
        // rounded cream panel (see FormView) and we keep the window shadow.
        let window = FormWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)  // size to the SwiftUI content
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Emit exactly once, then quit.
    private func finish(_ values: [String: String]) {
        guard !finished else { return }
        finished = true
        emit(values)
        NSApp.terminate(nil)
    }

    // Closing the window (red button) counts as cancel.
    func windowWillClose(_ notification: Notification) {
        finish([:])
    }
}

let app = NSApplication.shared
// Runs as an LSUIElement agent (see ExpandrForm.app's Info.plist), so it takes
// key focus for typing without ever showing a Dock icon. (A *bare* accessory
// executable has its window force-closed by the system — a real bundle doesn't.)
app.setActivationPolicy(.accessory)
let controller = FormWindowController(spec: spec)
app.delegate = controller
app.run()
