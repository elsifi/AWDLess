import Foundation
import ServiceManagement
import os

/// Registers the privileged helper with SMAppService and talks to it over XPC.
@MainActor
final class HelperClient: ObservableObject {
    enum Status: Equatable { case notRegistered, requiresApproval, enabled, notFound, unknown }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var reachable = false
    @Published private(set) var interfaceUp: Bool?
    @Published var lastError: String?

    private let service = SMAppService.daemon(plistName: AWDLessIDs.helperPlist)
    private var connection: NSXPCConnection?
    private let log = Logger(subsystem: AWDLessIDs.app, category: "helper")

    init() { refreshStatus() }

    func refreshStatus() {
        switch service.status {
        case .notRegistered: status = .notRegistered
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notFound: status = .notFound
        @unknown default: status = .unknown
        }
    }

    func register() {
        do {
            try service.register()
            lastError = nil
        } catch {
            // SMAppService reports an error when the user still needs to approve in System Settings.
            lastError = error.localizedDescription
            log.error("register failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func unregister() {
        connection?.invalidate(); connection = nil
        do { try service.unregister() } catch { lastError = error.localizedDescription }
        refreshStatus()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    private func proxy() -> AWDLessHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: AWDLessIDs.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: AWDLessHelperProtocol.self)
            c.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil; self?.reachable = false }
            }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.reachable = false
                self?.lastError = error.localizedDescription
                self?.log.error("xpc error: \(error.localizedDescription, privacy: .public)")
            }
        } as? AWDLessHelperProtocol
    }

    func setSuppressed(_ suppressed: Bool, completion: ((Bool) -> Void)? = nil) {
        guard status == .enabled, let p = proxy() else { completion?(false); return }
        p.setSuppressed(suppressed) { ok in
            Task { @MainActor in
                self.reachable = ok
                self.interfaceUp = ok ? !suppressed : nil
                completion?(ok)
            }
        }
    }

    func fetchStatus() {
        guard status == .enabled, let p = proxy() else { return }
        p.status { _, up, _ in
            Task { @MainActor in self.reachable = true; self.interfaceUp = up }
        }
    }
}
