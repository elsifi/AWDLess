import SwiftUI

@main
struct AWDLessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared
    @State private var iconInserted = true

    var body: some Scene {
        // AWDLControl issue #1: removing the icon must not leave an invisible app holding AWDL off.
        MenuBarExtra(isInserted: Binding(get: { iconInserted }, set: { v in
            iconInserted = v
            if !v { NSApp.terminate(nil) }
        })) {
            MenuView(helper: state.helper).environmentObject(state)
                .onAppear { state.helper.refreshStatus(); state.helper.fetchStatus() }
        } label: {
            Image(nsImage: MenuBarIcon.image(for: iconState, style: state.prefs.iconStyle))
        }
        .menuBarExtraStyle(.window)
    }

    private var iconState: MenuBarIcon.State {
        switch state.headline {
        case .helperMissing: .helperMissing
        case .manualOn: .manualOn
        case .protecting, .manualOff: .protecting
        case .protectingStalling: .protectingStalling
        case .ethernet: .ethernet
        case .standby, .restoring: .standby
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    /// awdless://settings  awdless://test  awdless://mode/auto|off|on
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch (url.host, url.pathComponents.dropFirst().first) {
            case ("settings", _): SettingsWindow.shared.show()
            case ("test", _): DiagnosticsWindow.shared.show()
            case ("mode", "auto"): AppState.shared.setOverride(.automatic)
            case ("mode", "off"): AppState.shared.setOverride(.forceOff(until: Date().addingTimeInterval(3600)))
            case ("mode", "on"): AppState.shared.setOverride(.forceOn(until: Date().addingTimeInterval(3600)))
            default: break
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Our own Quit button already confirmed; anything else (Cmd-Q from a window, Activity Monitor) asks once.
        if QuitConfirmation.confirmed || !AppState.shared.suppressed { return .terminateNow }
        QuitConfirmation.run()
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        // Helper restores awdl0 when our XPC connection goes away; nothing else to do.
    }
}

extension AppState {
    static let shared = AppState()
}
