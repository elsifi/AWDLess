import SwiftUI

@main
struct AWDLessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(helper: state.helper).environmentObject(state)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: iconState))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(state)
        }
    }

    private var iconState: MenuBarIcon.State {
        if state.helper.status != .enabled { return .helperMissing }
        if case .forceOn = state.override { return .manualOn }
        if state.suppressed { return state.health.hasRecentStall ? .activeStalling : .active }
        return .idle
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
