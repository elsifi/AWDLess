import Foundation
import os

/// Owns the awdl0 interface state. Mechanism (inspired by James Howard's AWDLControl):
/// flip IFF_UP with an ioctl, and watch the kernel routing socket (PF_ROUTE) for RTM_IFINFO
/// messages about awdl0 so that when macOS brings the interface back up on its own, it is
/// taken down again within milliseconds. No polling.
final class AWDLMonitor {
    private let log = Logger(subsystem: AWDLessIDs.helperLabel, category: "monitor")
    private let queue = DispatchQueue(label: "com.elsifi.AWDLess.monitor")
    private let interfaceName = "awdl0"
    private let ioctlFD: Int32
    private let routeFD: Int32
    private var routeSource: DispatchSourceRead?
    private(set) var suppressed = false

    // ioctl request numbers (_IOWR('i', 17, struct ifreq) / _IOW('i', 16, struct ifreq)); the C macros are not importable in Swift.
    private let SIOCGIFFLAGS: UInt = 0xC020_6911
    private let SIOCSIFFLAGS: UInt = 0x8020_6910
    private let RTM_IFINFO_TYPE: UInt8 = 0x0e

    init?() {
        routeFD = socket(AF_ROUTE, SOCK_RAW, 0)
        ioctlFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard routeFD >= 0, ioctlFD >= 0 else {
            log.error("socket() failed: errno \(errno)")
            return nil
        }
        _ = fcntl(routeFD, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: routeFD, queue: queue)
        source.setEventHandler { [weak self] in self?.drainRouteSocket() }
        source.resume()
        routeSource = source
    }

    deinit {
        routeSource?.cancel()
        close(routeFD)
        close(ioctlFD)
    }

    func setSuppressed(_ value: Bool) {
        queue.async {
            self.suppressed = value
            self.log.info("suppressed = \(value)")
            self.apply(up: !value)
        }
    }

    func isInterfaceUp() -> Bool {
        queue.sync { (currentFlags() ?? 0) & Int16(IFF_UP) != 0 }
    }

    // MARK: - ioctl

    private func makeIfreq() -> ifreq {
        var ifr = ifreq()
        withUnsafeMutablePointer(to: &ifr.ifr_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(IFNAMSIZ)) { _ = strlcpy($0, interfaceName, Int(IFNAMSIZ)) }
        }
        return ifr
    }

    private func currentFlags() -> Int16? {
        var ifr = makeIfreq()
        guard ioctl(ioctlFD, SIOCGIFFLAGS, &ifr) == 0 else {
            log.error("SIOCGIFFLAGS failed: errno \(errno)")
            return nil
        }
        return ifr.ifr_ifru.ifru_flags
    }

    private func apply(up: Bool) {
        guard let flags = currentFlags() else { return }
        let isUp = flags & Int16(IFF_UP) != 0
        guard isUp != up else { return }
        var ifr = makeIfreq()
        ifr.ifr_ifru.ifru_flags = up ? (flags | Int16(IFF_UP)) : (flags & ~Int16(IFF_UP))
        if ioctl(ioctlFD, SIOCSIFFLAGS, &ifr) != 0 {
            log.error("SIOCSIFFLAGS(up=\(up)) failed: errno \(errno)")
        } else {
            log.info("awdl0 \(up ? "UP" : "DOWN")")
        }
    }

    // MARK: - routing socket

    private func drainRouteSocket() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let targetIndex = if_nametoindex(interfaceName)
        var cameUp = false
        while true {
            let n = read(routeFD, &buffer, buffer.count)
            if n <= 0 { break }
            // struct if_msghdr: u_short ifm_msglen; u_char ifm_version; u_char ifm_type; int ifm_addrs; int ifm_flags; u_short ifm_index; ...
            guard n >= 14, buffer[3] == RTM_IFINFO_TYPE else { continue }
            let flags = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int32.self) }
            let index = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt16.self) }
            if UInt32(index) == targetIndex, flags & Int32(IFF_UP) != 0 { cameUp = true }
        }
        if cameUp && suppressed {
            log.info("awdl0 was brought up by the system; taking it down again")
            apply(up: false)
        }
    }
}
