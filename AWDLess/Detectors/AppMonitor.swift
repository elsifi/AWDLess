import AppKit

/// Watches for user-chosen apps (by bundle identifier) being launched or quit.
final class AppMonitor {
    var onChange: (([NSRunningApplication]) -> Void)?
    var watchedBundleIDs: Set<String> = [] { didSet { refresh() } }
    private(set) var running: [NSRunningApplication] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        let now = NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return watchedBundleIDs.contains(id)
        }
        let changed = Set(now.map(\.processIdentifier)) != Set(running.map(\.processIdentifier))
        running = now
        if changed { onChange?(now) }
    }
}
