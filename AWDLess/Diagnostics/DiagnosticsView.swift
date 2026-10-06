import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @ObservedObject var run: DiagnosticRun
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Test your meeting").font(.title2.bold())
            Text("Four minutes on a live video call. AWDLess measures your Wi-Fi link with Continuity on, then off, and tells you whether Continuity is what freezes your calls. If it is not, you will be told so plainly.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            content
            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 400)
    }

    @ViewBuilder private var content: some View {
        switch run.phase {
        case .idle:
            steps
            Button("Start") { run.start() }.buttonStyle(.borderedProminent)
        case .waitingForCall:
            Label(run.cameraActive ? "Camera detected. Ready." : "Start a video call with your camera on…", systemImage: run.cameraActive ? "checkmark.circle.fill" : "video")
                .foregroundStyle(run.cameraActive ? .green : .secondary)
            Text("Use the Mac that usually freezes. Keep Universal Control, AirDrop and anything else you normally use running.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Begin measurement") { run.beginPhases() }.buttonStyle(.borderedProminent)
                Button("Cancel") { run.cancel() }
            }
        case .phaseOn, .phaseOff:
            let on = run.phase == .phaseOn
            Label(on ? "Phase 1 of 2: Continuity on" : "Phase 2 of 2: Continuity off", systemImage: on ? "1.circle.fill" : "2.circle.fill").font(.headline)
            ProgressView(value: Double(Int(DiagnosticRun.phaseLength) - run.secondsLeft), total: DiagnosticRun.phaseLength)
            HStack {
                Text("\(run.secondsLeft) s left").monospacedDigit()
                Spacer()
                Text("\(run.liveStalls) stalls so far").foregroundStyle(run.liveStalls > 0 ? .orange : .secondary).monospacedDigit()
            }.font(.caption)
            Text("Keep talking, keep the camera on. Do not change anything else.").font(.caption).foregroundStyle(.secondary)
            Button("Cancel") { run.cancel() }
        case .done:
            resultView
            Button("Done") { run.cancel() }.buttonStyle(.borderedProminent)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Join a video call on this Mac, camera on", systemImage: "1.circle")
            Label("2 minutes with Continuity on", systemImage: "2.circle")
            Label("2 minutes with Continuity off", systemImage: "3.circle")
            Label("Verdict", systemImage: "4.circle")
        }.foregroundStyle(.secondary)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow { Text(""); Text("Continuity on").bold(); Text("Continuity off").bold() }
                GridRow { Text("Stalls"); Text("\(run.onResult.stalls)"); Text("\(run.offResult.stalls)") }
                GridRow { Text("Worst delay"); Text("\(Int(run.onResult.maxMs)) ms"); Text("\(Int(run.offResult.maxMs)) ms") }
                GridRow { Text("Typical delay"); Text("\(Int(run.onResult.medianMs)) ms"); Text("\(Int(run.offResult.medianMs)) ms") }
            }.font(.callout.monospacedDigit())
            Divider()
            Label(verdictTitle, systemImage: verdictSymbol).font(.headline).foregroundStyle(verdictColor)
            Text(verdictBody).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var verdictTitle: String {
        switch run.verdict {
        case .continuityCausesIt: "Continuity is freezing your calls"
        case .noStalls: "Your link is clean. You don't need AWDLess"
        case .stallsRemain: "Something else is stalling your Wi-Fi"
        default: "Inconclusive"
        }
    }
    private var verdictBody: String {
        switch run.verdict {
        case .continuityCausesIt: "Stalls dropped from \(run.onResult.stalls) to \(run.offResult.stalls) with Continuity off. Leave AWDLess on Auto and your meetings stay steady."
        case .noStalls: "No stalls in either phase. Whatever freezes you see is not this Mac's Wi-Fi radio. Look at the other participant, the meeting app, or your internet line."
        case .stallsRemain: "Stalls continued with Continuity off. Check router channel settings, interference, or try Ethernet. AWDLess will not fix this."
        default: "Not enough samples, or no clear difference. Try again on a call that usually freezes."
        }
    }
    private var verdictSymbol: String {
        switch run.verdict { case .continuityCausesIt: "checkmark.seal.fill"; case .noStalls: "hand.thumbsup.fill"; case .stallsRemain: "wifi.exclamationmark"; default: "questionmark.circle" }
    }
    private var verdictColor: Color {
        switch run.verdict { case .continuityCausesIt: .green; case .noStalls: .blue; case .stallsRemain: .orange; default: .secondary }
    }
}

@MainActor
final class DiagnosticsWindow {
    static let shared = DiagnosticsWindow()
    private var window: NSWindow?
    private var run: DiagnosticRun?
    func show() {
        if window == nil {
            let r = DiagnosticRun(state: AppState.shared); run = r
            let w = NSWindow(contentViewController: NSHostingController(rootView: DiagnosticsView(run: r).environmentObject(AppState.shared)))
            w.title = "Test your meeting"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false; w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
