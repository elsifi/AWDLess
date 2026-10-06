import Foundation
import Network
import SystemConfiguration

/// Tracks whether the primary route is Wi-Fi and what the default gateway is.
final class NetworkMonitor {
    var onChange: (() -> Void)?
    private(set) var isOnWiFi = false
    private(set) var isOnEthernet = false
    private(set) var routerAddress: String?
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isOnWiFi = path.usesInterfaceType(.wifi)
                self.isOnEthernet = path.usesInterfaceType(.wiredEthernet)
                self.routerAddress = Self.defaultRouter()
                self.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.elsifi.AWDLess.path"))
    }

    static func defaultRouter() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "AWDLess" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return global["Router"] as? String
    }
}
