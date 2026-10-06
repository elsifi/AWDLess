import SwiftUI

@main
struct AWDLessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(helper: state.helper).environmentObject(state)
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
