import Foundation
import Darwin

/// Minimal ICMP echo pinger using an unprivileged ICMP datagram socket (no root needed on macOS).
/// One sample per `interval`; result is the round-trip time in ms, or nil on timeout.
final class Pinger {
    var onSample: ((Double?) -> Void)?
    private(set) var host: String
    private let interval: TimeInterval
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.elsifi.AWDLess.pinger")
    private var running = false
    private var seq: UInt16 = 0
    private var fd: Int32 = -1

    init(host: String, interval: TimeInterval = 1.0, timeout: TimeInterval = 1.0) {
        self.host = host; self.interval = interval; self.timeout = timeout
    }

    func setHost(_ h: String) { queue.async { self.host = h } }

    func start() {
        queue.async {
            guard !self.running else { return }
            self.fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard self.fd >= 0 else { return }
            self.running = true
            self.loop()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
    }

    private func loop() {
        guard running else { return }
        let rtt = pingOnce()
        DispatchQueue.main.async { self.onSample?(rtt) }
        let wait = max(0, interval - (rtt ?? timeout * 1000) / 1000)
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.loop() }
    }

    private func pingOnce() -> Double? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }

        seq &+= 1
        let ident = UInt16(truncatingIfNeeded: getpid())
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 8 // echo request
        packet[4] = UInt8(ident >> 8); packet[5] = UInt8(ident & 0xff)
        packet[6] = UInt8(seq >> 8); packet[7] = UInt8(seq & 0xff)
        let sent = DispatchTime.now().uptimeNanoseconds
        withUnsafeBytes(of: sent) { packet.replaceSubrange(8..<16, with: $0) }
        let sum = Self.checksum(packet)
        packet[2] = UInt8(sum >> 8); packet[3] = UInt8(sum & 0xff)

        let sentOK = packet.withUnsafeBytes { buf -> Bool in
            withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == buf.count
                }
            }
        }
        guard sentOK else { return nil }

        let deadline = sent + UInt64(timeout * 1_000_000_000)
        var reply = [UInt8](repeating: 0, count: 1024)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ms = Int32((deadline - now) / 1_000_000)
            guard poll(&pfd, 1, max(ms, 1)) > 0 else { return nil }
            let n = recv(fd, &reply, reply.count, 0)
            guard n > 0 else { continue }
            // macOS returns the IP header too on ICMP datagram sockets.
            var offset = 0
            if n >= 20, reply[0] >> 4 == 4 { offset = Int(reply[0] & 0x0f) * 4 }
            guard n >= offset + 8, reply[offset] == 0 else { continue } // echo reply
            let rseq = UInt16(reply[offset + 6]) << 8 | UInt16(reply[offset + 7])
            guard rseq == seq else { continue }
            return Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000
        }
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}
