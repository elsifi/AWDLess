import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import os

/// The policy engine: combines triggers, overrides and network state into one decision
/// ("should AWDL be suppressed right now?") and drives the helper, notifications and link health.
@MainActor
final class AppState: ObservableObject {
    enum Override: Equatable {
        case automatic
        case forceOff(until: Date?)     // AWDL off
        case forceOn(until: Date?)      // AWDL on, triggers ignored
    }
    struct Trigger: Identifiable, Equatable {
        enum Kind { case camera, microphone, app, game }
        let kind: Kind
        let name: String          // device, app or game name
        var app: String? = nil    // meeting app that is likely using it, if known
        var id: String { "\(kind)-\(name)" }
    }

    // Inputs
    let prefs = Preferences()
    let helper = HelperClient()
    let updates = UpdateChecker()
    private let camera = CameraMonitor()
    private let microphone = MicrophoneMonitor()
    private let apps = AppMonitor()
    private let games = GameMonitor()
    private let network = NetworkMonitor()
    private var pinger: Pinger?
    private let traffic = AWDLTraffic()
    private let log = Logger(subsystem: AWDLessIDs.app, category: "state")

    // Outputs
    @Published private(set) var triggers: [Trigger] = []
    @Published private(set) var suppressed = false
    @Published private(set) var inGrace = false
    @Published var override: Override = .automatic { didSet { reevaluate(allowGrace: false) } }
    @Published private(set) var onWiFi = false
    @Published private(set) var routerAddress: String?
    @Published private(set) var health = LinkHealth()
    @Published private(set) var continuityBytesPerSec: Double = 0
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var graceTimer: Timer?
    private var overrideTimer: Timer?

    init() {
        camera.onChange = { [weak self] _ in self?.reevaluate() }
        microphone.onChange = { [weak self] _ in self?.reevaluate() }
        apps.onChange = { [weak self] _ in self?.reevaluate() }
        games.onChange = { [weak self] _ in self?.reevaluate() }
        network.onChange = { [weak self] in self?.networkChanged() }
        apps.watchedBundleIDs = Set(prefs.watchedApps.map(\.bundleID))
        prefs.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.preferencesChanged() }
        }.store(in: &cancellables)
        networkChanged()
        helper.refreshStatus()
        helper.fetchStatus()
        // AWDLControl issue #8: frequent SMAppService status checks spam Background Task Management.
        // Status is re-read on user action and when the menu opens; the XPC ping here is cheap.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.helper.fetchStatus() }
        }
        traffic.onSample = { [weak self] bps in self?.continuityBytesPerSec = bps }
        traffic.start()
        restoreOverride()
        firstLaunchNotice()
        updates.startDailyChecks()
    }

    // MARK: - Persistence (AWDLControl issue #2: mode must survive a restart)

    private func restoreOverride() {
        let d = UserDefaults.standard
        let until = d.object(forKey: "overrideUntil") as? Date
        if let until, until < Date() { d.removeObject(forKey: "overrideKind"); return }
        switch d.string(forKey: "overrideKind") {
        case "off": setOverride(.forceOff(until: until))
        case "on": setOverride(.forceOn(until: until))
        default: break
        }
    }
    private func persistOverride(_ o: Override) {
        let d = UserDefaults.standard
        switch o {
        case .automatic: d.removeObject(forKey: "overrideKind"); d.removeObject(forKey: "overrideUntil")
        case .forceOff(let u): d.set("off", forKey: "overrideKind"); d.set(u, forKey: "overrideUntil")
        case .forceOn(let u): d.set("on", forKey: "overrideKind"); d.set(u, forKey: "overrideUntil")
        }
    }

    /// AWDLControl issue #9: people look for the app in the Dock. Say where it lives, once.
    private func firstLaunchNotice() {
        let key = "didShowFirstLaunchNotice"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = "AWDLess lives in the menu bar"
            c.body = "Click the camera icon at the top right to install the helper and see what is protected."
            center.add(UNNotificationRequest(identifier: "first-launch", content: c, trigger: nil))
        }
    }

    /// SMAppService needs a stable bundle path; warn if we are running from Downloads or a disk image.
    var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") || path.contains("/DerivedData/")
    }
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Policy

    /// Known meeting apps currently running, by display name.
    var runningMeetingApps: [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            return MeetingApps.known[id]
        }
    }

    var activeTriggers: [Trigger] {
        var t: [Trigger] = []
        let meetingApp = runningMeetingApps.first
        if prefs.triggerCamera {
            t += camera.activeDevices.map { Trigger(kind: .camera, name: $0.name, app: meetingApp) }
        }
        if prefs.triggerAnyMic || (prefs.triggerMeetingMic && meetingApp != nil) {
            t += microphone.activeDevices.map { Trigger(kind: .microphone, name: $0.name, app: meetingApp) }
        }
        if prefs.triggerApps { t += apps.running.map { Trigger(kind: .app, name: $0.localizedName ?? $0.bundleIdentifier ?? "app") } }
        if prefs.triggerGames, let g = games.activeGame { t.append(Trigger(kind: .game, name: g.localizedName ?? "Game")) }
        return t
    }

    enum Headline { case helperMissing, standby, ethernet, protecting, protectingStalling, restoring, manualOff, manualOn }
    var headline: Headline {
        if helper.status != .enabled { return .helperMissing }
        switch override {
        case .forceOff: return .manualOff
        case .forceOn: return .manualOn
        case .automatic: break
        }
        if prefs.wifiOnly && !onWiFi && !triggers.isEmpty { return .ethernet }
        if suppressed && inGrace && triggers.isEmpty { return .restoring }
        if suppressed { return health.hasRecentStall ? .protectingStalling : .protecting }
        return .standby
    }

    /// What is being protected, for the subtitle: "Zoom · FaceTime HD Camera".
    var subject: String {
        guard let first = triggers.first else { return "" }
        var parts: [String] = []
        if let app = first.app { parts.append(app) }
        parts.append(first.name)
        if triggers.count > 1 { parts.append("+\(triggers.count - 1)") }
        return parts.joined(separator: " · ")
    }

    /// One-line status, used by notifications and accessibility.
    var statusLine: String {
        switch headline {
        case .helperMissing: return "Helper not enabled"
        case .standby: return "Standing by, Continuity on"
        case .ethernet: return "On Ethernet, Continuity on"
        case .protecting: return "Meeting (\(subject)), Continuity off"
        case .protectingStalling: return "Meeting (\(subject)), Continuity off, link stalling"
        case .restoring: return "Meeting ended, Continuity back on shortly"
        case .manualOff: return "Continuity off (manual)"
        case .manualOn: return "Continuity always on"
        }
    }

    func reevaluate(allowGrace: Bool = true) {
        let newTriggers = activeTriggers
        if newTriggers != triggers { triggers = newTriggers }

        let wifiOK = !prefs.wifiOnly || onWiFi
        var desired: Bool
        switch override {
        case .forceOff: desired = true
        case .forceOn: desired = false
        case .automatic: desired = !triggers.isEmpty && wifiOK
        }

        if allowGrace, case .automatic = override, !desired, suppressed, prefs.gracePeriod > 0 {
            // Keep Continuity off for the grace period, so a brief camera toggle does not flap AirDrop.
            // When the timer fires we re-evaluate WITHOUT grace, otherwise the grace would repeat forever.
            if graceTimer == nil {
                inGrace = true
                graceTimer = Timer.scheduledTimer(withTimeInterval: prefs.gracePeriod, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.graceTimer = nil; self?.inGrace = false; self?.reevaluate(allowGrace: false)
                    }
                }
            }
            return
        }
        graceTimer?.invalidate(); graceTimer = nil; inGrace = false
        apply(desired)
    }

    private func apply(_ desired: Bool) {
        guard desired != suppressed else { updateLinkHealthRunning(); return }
        suppressed = desired
        log.notice("suppressed -> \(desired); triggers: \(self.triggers.map(\.name).joined(separator: ", "), privacy: .public)")
        helper.setSuppressed(desired) { [weak self] ok in
            guard let self else { return }
            if !ok { self.log.error("helper call failed") }
        }
        notifyStateChange()
        updateLinkHealthRunning()
    }

    private func preferencesChanged() {
        apps.watchedBundleIDs = Set(prefs.watchedApps.map(\.bundleID))
        health.stallThresholdMs = prefs.stallThresholdMs
        reevaluate()
        updateLinkHealthRunning()
    }

    private func networkChanged() {
        onWiFi = network.isOnWiFi && !network.isOnEthernet
        routerAddress = network.routerAddress
        if let r = routerAddress { pinger?.setHost(r) }
        reevaluate()
    }

    // MARK: - Overrides

    func setOverride(_ o: Override) {
        overrideTimer?.invalidate(); overrideTimer = nil
        override = o
        persistOverride(o)
        let until: Date?
        switch o { case .forceOff(let u), .forceOn(let u): until = u; case .automatic: until = nil }
        if let until {
            overrideTimer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.override = .automatic }
            }
            RunLoop.main.add(overrideTimer!, forMode: .common)
        }
    }

    // MARK: - Link health

    private func updateLinkHealthRunning() {
        let shouldRun: Bool
        switch prefs.linkHealthMode {
        case .always: shouldRun = true
        case .never: shouldRun = false
        case .duringCalls: shouldRun = suppressed || !triggers.isEmpty
        }
        if shouldRun, pinger == nil, let router = routerAddress {
            let p = Pinger(host: router)
            p.onSample = { [weak self] rtt in self?.health.add(rtt) }
            p.start()
            pinger = p
        } else if !shouldRun, let p = pinger {
            p.stop(); pinger = nil; health.clear()
        }
    }

    // MARK: - Login item & notifications

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { log.error("login item: \(error.localizedDescription, privacy: .public)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func notifyStateChange() {
        guard prefs.notifications else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            Task { @MainActor in
                content.title = self.suppressed ? "Meeting detected, Continuity off" : "Meeting ended, Continuity on"
                content.body = self.suppressed
                    ? "\(self.subject.isEmpty ? "A call" : self.subject) started. Universal Control, AirDrop and Handoff are off until it ends."
                    : "Universal Control, AirDrop and Handoff are available again."
                center.add(UNNotificationRequest(identifier: "awdl-\(self.suppressed)", content: content, trigger: nil))
            }
        }
    }
}

import Combine
