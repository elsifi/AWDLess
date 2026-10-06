import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gear") }
            TriggersTab().tabItem { Label("Detection", systemImage: "video") }
            LinkHealthTab().tabItem { Label("Link Health", systemImage: "waveform.path.ecg") }
            HelperTab().tabItem { Label("Helper", systemImage: "lock.shield") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 420)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs: Preferences
    init() { prefs = AppState.shared.prefs }
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            Toggle("Only protect when on Wi-Fi", isOn: $prefs.wifiOnly)
            Text("On Ethernet the AirDrop radio cannot hurt the connection, so nothing is changed.").settingsHint()
            VStack(alignment: .leading) {
                Slider(value: $prefs.gracePeriod, in: 0...120, step: 5) {
                    Text("Keep protecting for \(Int(prefs.gracePeriod)) s after a call ends")
                }
                Text("Avoids AirDrop flapping when a camera is toggled briefly.").settingsHint()
            }
            Toggle("Notify when protection starts and ends", isOn: $prefs.notifications)
            Picker("Menu bar icon", selection: $prefs.iconStyle) {
                ForEach(MenuBarIcon.Style.allCases) { style in
                    HStack { Image(nsImage: MenuBarIcon.image(for: .protecting, style: style)); Text(style.label) }.tag(style)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TriggersTab: View {
    @ObservedObject private var prefs: Preferences
    init() { prefs = AppState.shared.prefs }
    var body: some View {
        Form {
            Section {
                Toggle("A camera is in use", isOn: $prefs.triggerCamera)
                Text("Any app streaming any camera: built-in, USB or Continuity Camera. This is the measured cause of call freezes.").settingsHint()
                Toggle("A meeting app is using the microphone", isOn: $prefs.triggerMeetingMic)
                Text("Audio-only calls in Zoom, Teams, FaceTime, Slack, Webex, Discord, Meet and others.").settingsHint()
                Toggle("Any app is using the microphone", isOn: $prefs.triggerAnyMic)
                Text("Broad: also Siri, dictation and voice memos.").settingsHint()
            } header: { Text("Meetings") }
            Section {
                Toggle("A game is in front", isOn: $prefs.triggerGames)
                Text("Apps that declare the Games category or Game Mode support. Same idea as AWDLControl.").settingsHint()
                Toggle("Chosen apps are running", isOn: $prefs.triggerApps)
                ForEach(prefs.watchedApps) { app in
                    HStack {
                        Image(nsImage: icon(for: app.bundleID)).resizable().frame(width: 18, height: 18)
                        Text(app.name)
                        Spacer()
                        Button(role: .destructive) { prefs.watchedApps.removeAll { $0 == app } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { addApp() }.disabled(!prefs.triggerApps)
            } header: { Text("Also protect") }
        }
        .formStyle(.grouped)
    }
    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            if !prefs.watchedApps.contains(where: { $0.bundleID == id }) { prefs.watchedApps.append(.init(bundleID: id, name: name)) }
        }
    }
}

private struct LinkHealthTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs: Preferences
    init() { prefs = AppState.shared.prefs }
    var body: some View {
        Form {
            Picker("Ping the router", selection: $prefs.linkHealthMode) {
                ForEach(Preferences.LinkHealthMode.allCases) { Text($0.label).tag($0) }
            }
            Text("One ICMP echo per second to \(state.routerAddress ?? "the default gateway"). Shows whether the Wi-Fi link itself is stalling, independent of the internet.").settingsHint()
            Slider(value: $prefs.stallThresholdMs, in: 100...2000, step: 50) {
                Text("Count as a stall above \(Int(prefs.stallThresholdMs)) ms")
            }
            Text("A video call freezes visibly from roughly 500 ms.").settingsHint()
        }
        .formStyle(.grouped)
    }
}

private struct HelperTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var helper: HelperClient
    init() { helper = AppState.shared.helper }
    var body: some View {
        Form {
            LabeledContent("Status") { Text(statusText).foregroundStyle(helper.status == .enabled ? .green : .orange) }
            LabeledContent("awdl0") {
                Text(helper.interfaceUp.map { $0 ? "up" : "down" } ?? "unknown")
            }
            Text("AWDLess needs a small root helper to switch the awdl0 interface. macOS installs it through System Settings › Login Items and asks for your approval once. It only accepts commands from this app, signed by the same developer, and it restores AWDL whenever the app quits or crashes.").settingsHint()
            HStack {
                Button(helper.status == .enabled ? "Reinstall Helper" : "Install Helper…") { helper.register() }
                Button("Open Login Items") { helper.openLoginItems() }
                if helper.status == .enabled { Button("Remove Helper", role: .destructive) { helper.unregister() } }
            }
            if let e = helper.lastError { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }
    private var statusText: String {
        switch helper.status {
        case .enabled: "Installed and enabled"
        case .requiresApproval: "Waiting for approval in Login Items"
        case .notRegistered: "Not installed"
        case .notFound: "Helper missing from app bundle"
        case .unknown: "Unknown"
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 42)).foregroundStyle(Color.accentColor)
            Text("AWDLess").font(.title2.bold())
            Text("Steady Call").font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")").font(.caption).foregroundStyle(.secondary)
            Text("Apple Wireless Direct Link (AirDrop, Handoff, Continuity) makes the Wi-Fi radio hop channels on a shared schedule. During a video call that shows up as freezes of one to three seconds, for every Mac nearby. AWDLess keeps AWDL off exactly while a camera is in use.")
                .font(.callout).multilineTextAlignment(.center).padding(.horizontal)
            Text("Mechanism inspired by AWDLControl by James Howard. MIT License.")
                .font(.caption).foregroundStyle(.secondary)
            Link("github.com/elsifi/AWDLess", destination: URL(string: "https://github.com/elsifi/AWDLess")!).font(.caption)
        }
        .padding()
    }
}

private extension Text {
    func settingsHint() -> some View { self.font(.caption).foregroundStyle(.secondary) }
}
