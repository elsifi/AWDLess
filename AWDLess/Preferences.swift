import Foundation
import SwiftUI

/// User settings, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    struct WatchedApp: Codable, Hashable, Identifiable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
    }
    enum LinkHealthMode: String, CaseIterable, Identifiable {
        case duringCalls, always, never
        var id: String { rawValue }
        var label: String {
            switch self { case .duringCalls: "While protecting"; case .always: "Always"; case .never: "Never" }
        }
    }

    // Meeting detection (primary)
    @AppStorage("triggerCamera") var triggerCamera = true            // any camera streaming
    @AppStorage("triggerMeetingMic") var triggerMeetingMic = true    // mic in use while a known meeting app runs
    @AppStorage("triggerAnyMic") var triggerAnyMic = false           // any microphone use
    // Secondary
    @AppStorage("triggerGames") var triggerGames = false             // frontmost app is a game
    @AppStorage("triggerApps") var triggerApps = false               // chosen apps running
    @AppStorage("watchedAppsData") private var watchedAppsData: Data = Data()

    @AppStorage("wifiOnly") var wifiOnly = true
    @AppStorage("gracePeriod") var gracePeriod: Double = 20
    @AppStorage("notifications") var notifications = true
    @AppStorage("iconStyle") var iconStyle: MenuBarIcon.Style = .link
    @AppStorage("linkHealthMode") var linkHealthMode: LinkHealthMode = .duringCalls
    @AppStorage("stallThresholdMs") var stallThresholdMs: Double = 500

    var watchedApps: [WatchedApp] {
        get { (try? JSONDecoder().decode([WatchedApp].self, from: watchedAppsData)) ?? [] }
        set { watchedAppsData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }
}
