import Foundation
import AppKit

/// Checks GitHub Releases once a day for a newer version. No third-party updater, no telemetry:
/// one anonymous GET to the public releases API.
@MainActor
final class UpdateChecker: ObservableObject {
    static let releasesURL = URL(string: "https://api.github.com/repos/elsifi/AWDLess/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/elsifi/AWDLess/releases/latest")!

    @Published private(set) var availableVersion: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func startDailyChecks() {
        check()
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.check() } }
    }

    func check() {
        guard !checking else { return }
        checking = true
        var req = URLRequest(url: Self.releasesURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AWDLess/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let tag = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["tag_name"] as? String
            Task { @MainActor in
                self.checking = false
                self.lastChecked = Date()
                if let tag {
                    let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    self.availableVersion = Self.isNewer(v, than: self.currentVersion) ? v : nil
                }
            }
        }.resume()
    }

    func openReleasePage() { NSWorkspace.shared.open(Self.releasesPage) }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
