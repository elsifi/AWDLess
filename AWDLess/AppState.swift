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
        enum Kind { case camera, microphone, app }
        let kind: Kind
        let name: String
        var id: String { "\(kind)-\(name)" }
    }

    // Inputs
    let prefs = Preferences()
    let helper = HelperClient()
    private let camera = CameraMonitor()
    private let microphone = MicrophoneMonitor()
    private let apps = AppMonitor()
    private let network = NetworkMonitor()
    private var pinger: Pinger?
    private let log = Logger(subsystem: AWDLessIDs.app, category: "state")

    // Outputs
    @Published private(set) var triggers: [Trigger] = []
    @Published private(set) var suppressed = false
    @Published private(set) var inGrace = false
    @Published var override: Override = .automatic { didSet { reevaluate() } }
    @Published private(set) var onWiFi = false
    @Published private(set) var routerAddress: String?
    @Published private(set) var health = LinkHealth()
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var graceTimer: Timer?
    private var overrideTimer: Timer?

    init() {
        camera.onChange = { [weak self] _ in self?.reevaluate() }
        microphone.onChange = { [weak self] _ in self?.reevaluate() }
        apps.onChange = { [weak self] _ in self?.reevaluate() }
        network.onChange = { [weak self] in self?.networkChanged() }
        apps.watchedBundleIDs = Set(prefs.watchedApps.map(\.bundleID))
        prefs.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.preferencesChanged() }
        }.store(in: &cancellables)
        networkChanged()
        helper.refreshStatus()
        helper.fetchStatus()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.helper.refreshStatus(); self?.helper.fetchStatus() }
        }
    }
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Policy

    var activeTriggers: [Trigger] {
        var t: [Trigger] = []
        if prefs.triggerCamera { t += camera.activeDevices.map { Trigger(kind: .camera, name: $0.name) } }
        if prefs.triggerMicrophone { t += microphone.activeDevices.map { Trigger(kind: .microphone, name: $0.name) } }
        if prefs.triggerApps { t += apps.running.map { Trigger(kind: .app, name: $0.localizedName ?? $0.bundleIdentifier ?? "app") } }
        return t
    }

    /// Human-readable reason for the current state, for the menu and notifications.
    var statusLine: String {
        if helper.status != .enabled { return "Helper not enabled" }
        switch override {
        case .forceOff: return "AWDL off (manual)"
        case .forceOn: return "AWDL on (manual)"
        case .automatic: break
        }
        if prefs.wifiOnly && !onWiFi && !triggers.isEmpty { return "On Ethernet, AWDL left alone" }
        if suppressed, let first = triggers.first {
            let extra = triggers.count > 1 ? " +\(triggers.count - 1)" : ""
            return "AWDL off while \(first.name)\(extra) is in use"
        }
        if suppressed && inGrace { return "AWDL off, restoring in a moment" }
        return "Idle, AWDL on"
    }

    func reevaluate() {
        let newTriggers = activeTriggers
        if newTriggers != triggers { triggers = newTriggers }

        let wifiOK = !prefs.wifiOnly || onWiFi
        var desired: Bool
        switch override {
        case .forceOff: desired = true
        case .forceOn: desired = false
        case .automatic: desired = !triggers.isEmpty && wifiOK
        }

        if case .automatic = override, !desired, suppressed, prefs.gracePeriod > 0 {
            // Keep AWDL off for the grace period, so a brief camera toggle does not flap AirDrop.
            if graceTimer == nil {
                inGrace = true
                graceTimer = Timer.scheduledTimer(withTimeInterval: prefs.gracePeriod, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.graceTimer = nil; self?.inGrace = false; self?.reevaluate()
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
        log.info("suppressed -> \(desired); triggers: \(self.triggers.map(\.name).joined(separator: ", "), privacy: .public)")
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
                content.title = self.suppressed ? "AWDL off" : "AWDL back on"
                content.body = self.suppressed
                    ? "\(self.triggers.first?.name ?? "A call") is using the camera. AirDrop and Handoff pause until it stops."
                    : "AirDrop, Handoff and Continuity are available again."
                center.add(UNNotificationRequest(identifier: "awdl-\(self.suppressed)", content: content, trigger: nil))
            }
        }
    }
}

import Combine
