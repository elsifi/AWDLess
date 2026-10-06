import AppIntents

/// Shortcuts / automation support: "Set AWDLess mode to Keep off for 1 hour". Answers AWDLControl issue #5
/// (web-app games, custom automations) without adding app-specific configuration.
enum AWDLessMode: String, AppEnum {
    case auto, offNow, alwaysOn
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Continuity Mode")
    static var caseDisplayRepresentations: [AWDLessMode: DisplayRepresentation] = [
        .auto: "Auto (off during meetings)", .offNow: "Continuity off now", .alwaysOn: "Continuity always on",
    ]
}

struct SetModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set AWDLess Mode"
    static var description = IntentDescription("Continuity (Universal Control, AirDrop, Handoff): off during meetings, off now, or always on.")
    static var openAppWhenRun = false

    @Parameter(title: "Mode") var mode: AWDLessMode
    @Parameter(title: "Duration (minutes, 0 = until changed)", default: 60) var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let until: Date? = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        switch mode {
        case .auto: AppState.shared.setOverride(.automatic)
        case .offNow: AppState.shared.setOverride(.forceOff(until: until))
        case .alwaysOn: AppState.shared.setOverride(.forceOn(until: until))
        }
        return .result(dialog: "AWDLess: \(AppState.shared.statusLine)")
    }
}

struct GetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get AWDLess Status"
    static var openAppWhenRun = false
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: AppState.shared.statusLine)
    }
}

struct AWDLessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetModeIntent(), phrases: ["Set \(.applicationName) mode"], shortTitle: "Set Mode", systemImageName: "video")
        AppShortcut(intent: GetStatusIntent(), phrases: ["\(.applicationName) status"], shortTitle: "Status", systemImageName: "info.circle")
    }
}
