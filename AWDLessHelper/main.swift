import Foundation
import Security
import os

let log = Logger(subsystem: AWDLessIDs.helperLabel, category: "xpc")

/// Root helper. Accepts XPC connections only from the AWDLess app signed by the same team,
/// and restores awdl0 whenever the last client goes away so a crash can never leave AWDL off.
final class HelperService: NSObject, AWDLessHelperProtocol, NSXPCListenerDelegate {
    let monitor: AWDLMonitor
    private var clients = 0

    init(monitor: AWDLMonitor) { self.monitor = monitor }

    func setSuppressed(_ suppressed: Bool, reply: @escaping (Bool) -> Void) {
        monitor.setSuppressed(suppressed)
        reply(true)
    }

    func status(reply: @escaping (Bool, Bool, String) -> Void) {
        reply(monitor.suppressed, monitor.isInterfaceUp(), AWDLessIDs.helperVersion)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        clients += 1
        log.notice("client connected (pid \(connection.processIdentifier)), clients=\(self.clients)")
        connection.exportedInterface = NSXPCInterface(with: AWDLessHelperProtocol.self)
        connection.exportedObject = self
        let onGone: () -> Void = { [weak self] in
            guard let self else { return }
            self.clients = max(0, self.clients - 1)
            log.notice("client gone, clients=\(self.clients)")
            if self.clients == 0 { self.monitor.setSuppressed(false) }
        }
        connection.invalidationHandler = onGone
        connection.interruptionHandler = onGone
        connection.resume()
        return true
    }
}

/// Team identifier of this helper's own signature, used to pin the allowed client.
func ownTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return dict[kSecCodeInfoTeamIdentifier as String] as? String
}

guard let monitor = AWDLMonitor() else {
    log.error("could not create AWDLMonitor; exiting")
    exit(1)
}
let service = HelperService(monitor: monitor)
let listener = NSXPCListener(machServiceName: AWDLessIDs.machService)
var requirement = "identifier \"\(AWDLessIDs.app)\""
if let team = ownTeamIdentifier() {
    requirement = "anchor apple generic and identifier \"\(AWDLessIDs.app)\" and certificate leaf[subject.OU] = \"\(team)\""
} else {
    log.warning("helper is not team-signed; accepting any client with the app identifier (development only)")
}
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = service
listener.resume()
log.notice("AWDLessHelper \(AWDLessIDs.helperVersion) listening; requirement: \(requirement, privacy: .public)")
dispatchMain()
