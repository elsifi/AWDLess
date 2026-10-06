import Foundation

/// Rolling window of router round-trip samples and a simple health classification.
struct LinkHealth {
    enum Level { case good, degraded, stalled, unknown }

    static let windowSize = 60
    var samples: [Double?] = []          // ms, nil = timeout; newest last
    var stallThresholdMs: Double = 500
    var degradedThresholdMs: Double = 100

    mutating func add(_ rtt: Double?) {
        samples.append(rtt)
        if samples.count > Self.windowSize { samples.removeFirst(samples.count - Self.windowSize) }
    }
    mutating func clear() { samples.removeAll() }

    var latest: Double? { samples.last ?? nil }
    func level(of rtt: Double?) -> Level {
        guard let rtt else { return .stalled }
        if rtt >= stallThresholdMs { return .stalled }
        if rtt >= degradedThresholdMs { return .degraded }
        return .good
    }
    var currentLevel: Level { samples.isEmpty ? .unknown : level(of: latest) }
    /// Stalls (timeouts or above threshold) in the last `seconds` samples.
    func stalls(last seconds: Int) -> Int { samples.suffix(seconds).filter { level(of: $0) == .stalled }.count }
    var stallsInWindow: Int { stalls(last: Self.windowSize) }
    var hasRecentStall: Bool { stalls(last: 10) > 0 }
    var median: Double? {
        let v = samples.compactMap { $0 }.sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }
    var maximum: Double? { samples.compactMap { $0 }.max() }
}
