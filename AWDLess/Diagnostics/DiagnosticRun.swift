import Foundation
import SwiftUI

/// Guided "Test your meeting" flow. Two timed phases on a live call: Continuity on, then Continuity off.
/// Compares router stalls and gives an honest verdict, including "you don't need this app".
@MainActor
final class DiagnosticRun: ObservableObject {
    enum Phase: Equatable { case idle, waitingForCall, phaseOn, phaseOff, done }
    struct PhaseResult { var samples = 0; var stalls = 0; var timeouts = 0; var maxMs = 0.0; var medianMs = 0.0 }
    enum Verdict { case continuityCausesIt, stallsRemain, noStalls, inconclusive }

    static let phaseLength: TimeInterval = 120
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var secondsLeft = 0
    @Published private(set) var onResult = PhaseResult()
    @Published private(set) var offResult = PhaseResult()
    @Published private(set) var verdict: Verdict?
    @Published private(set) var liveStalls = 0

    private let state: AppState
    private var pinger: Pinger?
    private var samples: [Double?] = []
    private var timer: Timer?
    private var savedOverride: AppState.Override = .automatic

    init(state: AppState) { self.state = state }

    var cameraActive: Bool { state.activeTriggers.contains { $0.kind == .camera } }

    func start() {
        savedOverride = state.override
        phase = .waitingForCall
        verdict = nil
        onResult = .init(); offResult = .init()
    }

    func beginPhases() {
        guard let router = state.routerAddress else { phase = .done; verdict = .inconclusive; return }
        runPhase(.phaseOn, override: .forceOn(until: nil), router: router)
    }

    private func runPhase(_ p: Phase, override: AppState.Override, router: String) {
        phase = p
        state.setOverride(override)
        samples = []; liveStalls = 0
        secondsLeft = Int(Self.phaseLength)
        pinger?.stop()
        let pg = Pinger(host: router)
        pg.onSample = { [weak self] rtt in
            guard let self else { return }
            self.samples.append(rtt)
            if rtt == nil || rtt! >= self.state.prefs.stallThresholdMs { self.liveStalls += 1 }
        }
        pg.start(); pinger = pg
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.secondsLeft -= 1
                if self.secondsLeft <= 0 { self.finishPhase() }
            }
        }
    }

    private func finishPhase() {
        timer?.invalidate(); timer = nil
        pinger?.stop(); pinger = nil
        let result = summarize(samples)
        switch phase {
        case .phaseOn:
            onResult = result
            if let router = state.routerAddress { runPhase(.phaseOff, override: .forceOff(until: nil), router: router) }
        case .phaseOff:
            offResult = result
            state.setOverride(savedOverride)
            verdict = Self.judge(on: onResult, off: offResult)
            phase = .done
        default: break
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        pinger?.stop(); pinger = nil
        if phase == .phaseOn || phase == .phaseOff { state.setOverride(savedOverride) }
        phase = .idle
    }

    private func summarize(_ s: [Double?]) -> PhaseResult {
        var r = PhaseResult()
        r.samples = s.count
        r.timeouts = s.filter { $0 == nil }.count
        let v = s.compactMap { $0 }.sorted()
        r.stalls = r.timeouts + v.filter { $0 >= state.prefs.stallThresholdMs }.count
        r.maxMs = v.last ?? 0
        r.medianMs = v.isEmpty ? 0 : v[v.count / 2]
        return r
    }

    static func judge(on: PhaseResult, off: PhaseResult) -> Verdict {
        guard on.samples > 30, off.samples > 30 else { return .inconclusive }
        if on.stalls == 0 && off.stalls == 0 { return .noStalls }
        if on.stalls >= 3 && off.stalls <= on.stalls / 4 { return .continuityCausesIt }
        if off.stalls >= 3 { return .stallsRemain }
        return .inconclusive
    }
}
