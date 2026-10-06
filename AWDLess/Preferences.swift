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
            switch self { case .duringCalls: "While AWDL is off"; case .always: "Always"; case .never: "Never" }
        }
    }

    @AppStorage("triggerCamera") var triggerCamera = true
    @AppStorage("triggerMicrophone") var triggerMicrophone = false
    @AppStorage("triggerApps") var triggerApps = false
    @AppStorage("wifiOnly") var wifiOnly = true
    @AppStorage("gracePeriod") var gracePeriod: Double = 20          // seconds AWDL stays off after the last trigger ends
    @AppStorage("notifications") var notifications = true
    @AppStorage("linkHealthMode") var linkHealthMode: LinkHealthMode = .duringCalls
    @AppStorage("stallThresholdMs") var stallThresholdMs: Double = 500
    @AppStorage("watchedAppsData") private var watchedAppsData: Data = Data()

    var watchedApps: [WatchedApp] {
        get { (try? JSONDecoder().decode([WatchedApp].self, from: watchedAppsData)) ?? [] }
        set { watchedAppsData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }
}
