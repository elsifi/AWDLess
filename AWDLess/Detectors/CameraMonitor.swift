import Foundation
import CoreMediaIO

/// Reports which cameras are currently streaming to any process, using CoreMediaIO's
/// "DeviceIsRunningSomewhere" property. Reading it needs no camera permission.
final class CameraMonitor {
    struct Device: Hashable { let id: CMIOObjectID; let name: String }

    var onChange: (([Device]) -> Void)?
    private(set) var activeDevices: [Device] = [] { didSet { if activeDevices != oldValue { onChange?(activeDevices) } } }
    private var knownDevices: [CMIOObjectID: Device] = [:]
    private let queue = DispatchQueue.main
    private var pollTimer: Timer?

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    init() {
        var devicesAddr = Self.address(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddr, queue) { [weak self] _, _ in self?.refresh() }
        refresh()
        // Belt and braces: property listeners occasionally miss a transition on virtual cameras.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let ids = Self.deviceIDs()
        for id in ids where knownDevices[id] == nil {
            let dev = Device(id: id, name: Self.name(of: id))
            knownDevices[id] = dev
            var runningAddr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(id, &runningAddr, queue) { [weak self] _, _ in self?.refresh() }
        }
        for id in knownDevices.keys where !ids.contains(id) { knownDevices[id] = nil }
        activeDevices = ids.compactMap { id in Self.isRunning(id) ? knownDevices[id] : nil }
    }

    // MARK: - CMIO plumbing

    private static func deviceIDs() -> [CMIOObjectID] {
        var addr = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return ids
    }

    private static func isRunning(_ id: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, &value) == 0 else { return false }
        return value != 0
    }

    private static func name(of id: CMIOObjectID) -> String {
        var addr = address(kCMIOObjectPropertyName)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, $0) }
        guard status == 0, let s = value?.takeRetainedValue() else { return "Camera \(id)" }
        return s as String
    }
}
