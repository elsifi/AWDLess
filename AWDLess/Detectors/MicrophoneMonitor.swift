import Foundation
import CoreAudio

/// Reports which audio input devices are currently running for any process (CoreAudio
/// kAudioDevicePropertyDeviceIsRunningSomewhere). No microphone permission needed.
final class MicrophoneMonitor {
    struct Device: Hashable { let id: AudioObjectID; let name: String }

    var onChange: (([Device]) -> Void)?
    private(set) var activeDevices: [Device] = [] { didSet { if activeDevices != oldValue { onChange?(activeDevices) } } }
    private var listened: Set<AudioObjectID> = []
    private var pollTimer: Timer?

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    init() {
        var devicesAddr = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, .main) { [weak self] _, _ in self?.refresh() }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let inputs = Self.deviceIDs().filter(Self.hasInput)
        for id in inputs where !listened.contains(id) {
            listened.insert(id)
            var runningAddr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(id, &runningAddr, .main) { [weak self] _, _ in self?.refresh() }
        }
        activeDevices = inputs.filter(Self.isRunning).map { Device(id: $0, name: Self.name(of: $0)) }
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return list.pointee.mNumberBuffers > 0
    }

    private static func isRunning(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func name(of id: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
        guard status == noErr, let s = value?.takeRetainedValue() else { return "Microphone \(id)" }
        return s as String
    }
}
