import Foundation
import Darwin

/// Samples bytes moving over awdl0 once a second. Universal Control, AirDrop and Sidecar show up here,
/// so the user can see when Continuity is actually busy.
final class AWDLTraffic {
    var onSample: ((Double) -> Void)?       // bytes per second (in + out)
    private var timer: Timer?
    private var last: (UInt64, Date)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() { timer?.invalidate(); timer = nil; last = nil }

    private func tick() {
        guard let bytes = Self.bytes(interface: "awdl0") else { return }
        let now = Date()
        if let (prev, t) = last {
            let dt = now.timeIntervalSince(t)
            if dt > 0 { onSample?(Double(bytes &- prev) / dt) }
        }
        last = (bytes, now)
    }

    private static func bytes(interface: String) -> UInt64? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            if String(cString: cur.pointee.ifa_name) == interface, cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
            }
            p = cur.pointee.ifa_next
        }
        return nil
    }
}
