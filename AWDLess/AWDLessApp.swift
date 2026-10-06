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

        Settings {
            SettingsView().environmentObject(state)
        }
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
    func applicationWillTerminate(_ notification: Notification) {
        // Helper restores awdl0 when our XPC connection goes away; nothing else to do.
    }
}

extension AppState {
    static let shared = AppState()
}
