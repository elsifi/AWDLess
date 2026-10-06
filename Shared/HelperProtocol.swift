import Foundation

/// Identifiers shared by the app and the privileged helper.
public enum AWDLessIDs {
    public static let app = "com.elsifi.AWDLess"
    public static let helperLabel = "com.elsifi.AWDLess.Helper"
    public static let helperPlist = "com.elsifi.AWDLess.Helper.plist"
    public static let machService = "com.elsifi.AWDLess.Helper"
    public static let helperVersion = "1"
}

/// XPC interface exposed by the root helper (a LaunchDaemon managed through SMAppService).
@objc public protocol AWDLessHelperProtocol {
    /// Keep awdl0 down (true) or let macOS manage it (false). The helper re-applies "down"
    /// immediately whenever another system component brings the interface back up.
    func setSuppressed(_ suppressed: Bool, reply: @escaping (Bool) -> Void)
    /// Current helper state: suppression flag, whether awdl0 is currently UP, helper version.
    func status(reply: @escaping (Bool, Bool, String) -> Void)
}
