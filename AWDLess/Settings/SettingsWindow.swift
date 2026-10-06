import AppKit
import SwiftUI

/// Owns the Settings window. SwiftUI's `Settings` scene does not open reliably from a MenuBarExtra popover
/// in an accessory app, so we host the view in our own window and activate the app explicitly.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(AppState.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "AWDLess Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("AWDLessSettings")
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum QuitConfirmation {
    @MainActor static var confirmed = false
    @MainActor static func run() {
        let state = AppState.shared
        let alert = NSAlert()
        alert.messageText = "Quit AWDLess?"
        alert.informativeText = state.suppressed
            ? "Continuity will be switched back on and your current call is no longer protected from freezes."
            : "Meetings will no longer be protected until you open AWDLess again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { confirmed = true; NSApp.terminate(nil) }
    }
}
