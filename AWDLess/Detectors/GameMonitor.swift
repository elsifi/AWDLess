import AppKit

/// Reports when the frontmost app is a game (LSApplicationCategoryType games, or LSSupportsGameMode),
/// the same heuristic AWDLControl uses. Cheap secondary trigger; meetings remain the primary case.
final class GameMonitor {
    var onChange: ((NSRunningApplication?) -> Void)?
    private(set) var activeGame: NSRunningApplication? { didSet { if activeGame?.processIdentifier != oldValue?.processIdentifier { onChange?(activeGame) } } }
    private var cache: [String: Bool] = [:]

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard let app = NSWorkspace.shared.frontmostApplication, let url = app.bundleURL else { activeGame = nil; return }
        activeGame = isGame(url) ? app : nil
    }

    private func isGame(_ url: URL) -> Bool {
        if let cached = cache[url.path] { return cached }
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        let isGame = (info["LSApplicationCategoryType"] as? String) == "public.app-category.games"
            || (info["LSSupportsGameMode"] as? Bool) == true
        cache[url.path] = isGame
        return isGame
    }
}
