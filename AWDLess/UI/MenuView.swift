import SwiftUI

/// Content of the menu bar popover.
struct MenuView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var helperProxy: HelperClient
    init(helper: HelperClient) { helperProxy = helper }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if state.helper.status != .enabled { helperBanner; Divider() }
            triggersSection
            Divider()
            linkHealthSection
            Divider()
            overrideSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.suppressed ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(state.suppressed ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("AWDLess").font(.headline)
                Text(state.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Circle().fill(dotColor).frame(width: 10, height: 10)
                .help(state.suppressed ? "AWDL is off" : "AWDL is on")
        }
    }
    private var dotColor: Color {
        if state.helper.status != .enabled { return .gray }
        if state.health.hasRecentStall { return .orange }
        return state.suppressed ? .green : .secondary.opacity(0.4)
    }

    private var helperBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(helperText, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            HStack {
                Button(state.helper.status == .requiresApproval ? "Open Login Items…" : "Install Helper…") {
                    if state.helper.status == .requiresApproval { state.helper.openLoginItems() } else { state.helper.register() }
                }.controlSize(.small)
                if let e = state.helper.lastError { Text(e).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
    private var helperText: String {
        switch state.helper.status {
        case .requiresApproval: "Helper needs approval in System Settings › Login Items."
        case .notFound: "Helper binary missing from the app bundle."
        default: "The privileged helper that controls awdl0 is not installed."
        }
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Triggers").font(.caption).foregroundStyle(.secondary)
            if state.triggers.isEmpty {
                Text(state.prefs.triggerCamera ? "No camera in use" : "Camera trigger is off").font(.callout)
            } else {
                ForEach(state.triggers) { t in
                    Label(t.name, systemImage: icon(for: t.kind)).font(.callout)
                }
            }
            if state.prefs.wifiOnly && !state.onWiFi {
                Label("Not on Wi-Fi, nothing to do", systemImage: "cable.connector").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func icon(for kind: AppState.Trigger.Kind) -> String {
        switch kind { case .camera: "video.fill"; case .microphone: "mic.fill"; case .app: "app.fill" }
    }

    private var linkHealthSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Link to router").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let ms = state.health.latest { Text("\(Int(ms)) ms").font(.caption.monospacedDigit()) }
                else if state.health.currentLevel == .stalled { Text("timeout").font(.caption).foregroundStyle(.red) }
            }
            if state.health.samples.isEmpty {
                Text(state.prefs.linkHealthMode == .never ? "Monitoring off" : "Starts when AWDL goes off")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Sparkline(health: state.health).frame(height: 36)
                HStack {
                    if let m = state.health.median { Text("median \(Int(m)) ms") }
                    if let mx = state.health.maximum { Text("max \(Int(mx)) ms") }
                    Spacer()
                    let stalls = state.health.stallsInWindow
                    Text(stalls == 0 ? "no stalls" : "\(stalls) stall\(stalls == 1 ? "" : "s") / 60 s")
                        .foregroundStyle(stalls == 0 ? .secondary : .orange)
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var overrideSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { pickerValue }, set: { apply($0) })) {
                Text("Auto").tag(0)
                Text("AWDL off").tag(1)
                Text("AWDL on").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            if case .automatic = state.override {} else {
                HStack {
                    Text(untilText).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Menu("For…") {
                        Button("1 hour") { setTimed(3600) }
                        Button("4 hours") { setTimed(4 * 3600) }
                        Button("Until I change it") { setTimed(nil) }
                    }.menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                }
            }
        }
    }
    private var pickerValue: Int {
        switch state.override { case .automatic: 0; case .forceOff: 1; case .forceOn: 2 }
    }
    private func apply(_ v: Int) {
        switch v {
        case 1: state.setOverride(.forceOff(until: Date().addingTimeInterval(3600)))
        case 2: state.setOverride(.forceOn(until: Date().addingTimeInterval(3600)))
        default: state.setOverride(.automatic)
        }
    }
    private func setTimed(_ seconds: TimeInterval?) {
        let until = seconds.map { Date().addingTimeInterval($0) }
        switch state.override {
        case .forceOff: state.setOverride(.forceOff(until: until))
        case .forceOn: state.setOverride(.forceOn(until: until))
        case .automatic: break
        }
    }
    private var untilText: String {
        let until: Date?
        switch state.override { case .forceOff(let u), .forceOn(let u): until = u; case .automatic: until = nil }
        guard let until else { return "until you switch back to Auto" }
        return "until \(until.formatted(date: .omitted, time: .shortened))"
    }

    private var footer: some View {
        HStack {
            SettingsLink { Text("Settings…") }.keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.controlSize(.small)
    }
}
