import SwiftUI

/// Popover content: a status card, link health, mode, footer.
struct MenuView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var helperProxy: HelperClient
    init(helper: HelperClient) { helperProxy = helper }

    var body: some View {
        VStack(spacing: 8) {
            statusCard
            if state.helper.status != .enabled { helperCard }
            linkCard
            modeCard
            footer
        }
        .padding(10)
        .frame(width: 300)
    }

    // MARK: Status

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: statusSymbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var accent: Color {
        switch state.headline {
        case .helperMissing: .orange
        case .protecting: .green
        case .protectingStalling: .orange
        case .manualOff: .green
        case .manualOn: .secondary
        case .standby, .ethernet, .restoring: .secondary
        }
    }
    private var statusSymbol: String {
        switch state.headline {
        case .helperMissing: "lock.open"
        case .standby: "video"
        case .ethernet: "cable.connector"
        case .protecting: "checkmark"
        case .protectingStalling: "exclamationmark"
        case .restoring: "arrow.counterclockwise"
        case .manualOff: "hand.raised.fill"
        case .manualOn: "hand.raised"
        }
    }
    private var title: String {
        switch state.headline {
        case .helperMissing: "Setup needed"
        case .standby: "Standing by"
        case .ethernet: "On Ethernet"
        case .protecting: "Protecting your call"
        case .protectingStalling: "Call protected, link stalling"
        case .restoring: "Call ended"
        case .manualOff: "AWDL off"
        case .manualOn: "AWDL on"
        }
    }
    private var subtitle: String {
        switch state.headline {
        case .helperMissing: "Install the helper once to let AWDLess manage AWDL."
        case .standby: state.prefs.triggerCamera ? "AWDL on. Starts protecting when a camera turns on." : "Camera detection is off."
        case .ethernet: "\(state.subject). AWDL cannot hurt a wired link."
        case .protecting: "\(state.subject). AirDrop and Handoff paused."
        case .protectingStalling: "\(state.subject). The link stalls even with AWDL off; something else is interfering."
        case .restoring: "AWDL comes back in \(Int(state.prefs.gracePeriod)) s."
        case .manualOff: "Held off by you. AirDrop and Handoff paused."
        case .manualOn: "Held on by you. Meetings are not protected."
        }
    }

    // MARK: Helper

    private var helperCard: some View {
        HStack {
            Text(state.helper.status == .requiresApproval ? "Approve AWDLess in Login Items." : "Needs a small root helper, installed by macOS.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(state.helper.status == .requiresApproval ? "Open Settings" : "Install") {
                if state.helper.status == .requiresApproval { state.helper.openLoginItems() } else { state.helper.register() }
            }.controlSize(.small).buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
    }

    // MARK: Link health

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Wi-Fi link").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if state.health.samples.isEmpty {
                    Text(state.prefs.linkHealthMode == .never ? "off" : "idle").font(.caption).foregroundStyle(.tertiary)
                } else if let ms = state.health.latest {
                    Text("\(Int(ms)) ms").font(.caption.monospacedDigit().weight(.medium))
                } else {
                    Text("timeout").font(.caption.weight(.medium)).foregroundStyle(.red)
                }
            }
            if !state.health.samples.isEmpty {
                Sparkline(health: state.health).frame(height: 30)
                HStack {
                    let stalls = state.health.stallsInWindow
                    Text(stalls == 0 ? "No stalls in the last minute" : "\(stalls) stall\(stalls == 1 ? "" : "s") in the last minute")
                        .foregroundStyle(stalls == 0 ? Color.secondary : Color.orange)
                    Spacer()
                    if let m = state.health.median { Text("median \(Int(m)) ms").foregroundStyle(.tertiary) }
                }.font(.caption2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    // MARK: Mode

    private var modeCard: some View {
        VStack(spacing: 6) {
            Picker("", selection: Binding(get: { pickerValue }, set: { apply($0) })) {
                Text("Auto").tag(0)
                Text("Keep off").tag(1)
                Text("Keep on").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            if case .automatic = state.override {} else {
                HStack(spacing: 6) {
                    Text(untilText).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    ForEach([("1 h", 3600.0), ("4 h", 14400.0), ("∞", -1.0)], id: \.0) { label, secs in
                        Button(label) { setTimed(secs < 0 ? nil : secs) }.controlSize(.mini)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
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
        guard let until else { return "Until you switch back to Auto" }
        return "Until \(until.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            SettingsLink { Label("Settings", systemImage: "gearshape") }.keyboardShortcut(",")
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }.keyboardShortcut("q")
        }
        .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
