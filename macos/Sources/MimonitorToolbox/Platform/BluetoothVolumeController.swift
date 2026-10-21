import CoreAudio
import Foundation

struct BluetoothVolumeDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let channels: [UInt32]
}

struct BluetoothVolumeState: Equatable {
    let volume: Int
    let muted: Bool
}

protocol BluetoothVolumeAccess {
    func devices() throws -> [BluetoothVolumeDevice]
    func read(_ device: BluetoothVolumeDevice, channel: UInt32) throws -> Float32
    func write(_ device: BluetoothVolumeDevice, channel: UInt32, scalar: Float32) throws
}

/// Only CoreAudio Bluetooth devices with writable volume controls are eligible.
/// It never changes the default output and never sends ADB commands.
final class BluetoothVolumeController {
    private let access: BluetoothVolumeAccess
    private var restoreVolumes: [String: Int] = [:]
    private var explicitlyMuted: Set<String> = []

    init(access: BluetoothVolumeAccess = CoreAudioBluetoothVolumeAccess()) { self.access = access }

    func device(named name: String) -> BluetoothVolumeDevice? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let devices = try? access.devices() else { return nil }
        let matches = devices.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame && !$0.channels.isEmpty }
        // Never choose an arbitrary speaker when names are ambiguous.
        return matches.count == 1 ? matches[0] : nil
    }

    // State/mutations below are serialized by AppState's dedicated Bluetooth queue.
    func state(_ device: BluetoothVolumeDevice) throws -> BluetoothVolumeState {
        guard let channel = device.channels.first else { throw Failure.unavailable }
        let scalar = try access.read(device, channel: channel)
        guard scalar.isFinite, (0...1).contains(scalar) else { throw Failure.invalidVolume }
        let value = BluetoothVolumeScale.volume(forScalar: scalar)
        if value > 0 {
            restoreVolumes[device.uid] = value
            explicitlyMuted.remove(device.uid)
        }
        let displayed = value == 0 && explicitlyMuted.contains(device.uid) ? restoreVolumes[device.uid] ?? 0 : value
        return BluetoothVolumeState(volume: displayed, muted: value == 0)
    }

    @discardableResult
    func setVolume(_ value: Int, on device: BluetoothVolumeDevice) throws -> BluetoothVolumeState {
        let value = min(max(value, 0), 100)
        try writeScalar(BluetoothVolumeScale.scalar(forVolume: value), device: device)
        explicitlyMuted.remove(device.uid)
        if value > 0 { restoreVolumes[device.uid] = value }
        return try state(device)
    }

    func adjust(increase: Bool, nativeSteps: Bool, step: Int, on device: BluetoothVolumeDevice) throws -> BluetoothVolumeState {
        let current = try state(device)
        let value: Int
        if nativeSteps {
            let position = Int((Double(current.volume) / 100 * 16).rounded())
            let target = min(max(position + (increase ? 1 : -1), 0), 16)
            value = Int((Double(target) / 16 * 100).rounded())
        } else {
            value = min(max(AppState.alignToStep(current.volume, step: max(1, step), increasing: increase), 0), 100)
        }
        return try setVolume(value, on: device)
    }

    func toggleMute(on device: BluetoothVolumeDevice) throws -> BluetoothVolumeState {
        let current = try state(device)
        if current.muted {
            return try setVolume(restoreVolumes[device.uid] ?? 6, on: device)
        }
        try writeScalar(0, device: device)
        restoreVolumes[device.uid] = current.volume
        explicitlyMuted.insert(device.uid)
        return BluetoothVolumeState(volume: current.volume, muted: true)
    }

    private func writeScalar(_ scalar: Float32, device: BluetoothVolumeDevice) throws {
        guard !device.channels.isEmpty else { throw Failure.unavailable }
        // Keep stereo channels together; restore earlier channels on a partial failure.
        let original = try device.channels.map { try access.read(device, channel: $0) }
        var written = 0
        do {
            for channel in device.channels {
                try access.write(device, channel: channel, scalar: scalar)
                written += 1
            }
        } catch {
            for index in (0..<written).reversed() {
                try? access.write(device, channel: device.channels[index], scalar: original[index])
            }
            throw error
        }
    }

    enum Failure: LocalizedError {
        case unavailable, invalidVolume
        var errorDescription: String? {
            switch self {
            case .unavailable: return "蓝牙音量设备不可用"
            case .invalidVolume: return "蓝牙设备返回了无效音量"
            }
        }
    }
}

struct CoreAudioBluetoothVolumeAccess: BluetoothVolumeAccess {
    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    private func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0)
        })
        return value?.takeRetainedValue() as String? ?? ""
    }
    private func uint(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var property = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value))
        return value
    }
    func devices() throws -> [BluetoothVolumeDevice] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size))
        guard size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        try check(ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!)
        })
        return ids.compactMap { id in
            guard let transport = try? uint(id, kAudioDevicePropertyTransportType),
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  (try? uint(id, kAudioDevicePropertyDeviceIsAlive)) == 1,
                  let name = try? string(id, kAudioObjectPropertyName),
                  let uid = try? string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let channels = [UInt32(0), 1, 2].filter { channel in
                var volume = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel)
                var settable: DarwinBoolean = false
                return AudioObjectHasProperty(id, &volume)
                    && AudioObjectIsPropertySettable(id, &volume, &settable) == noErr && settable.boolValue
            }
            guard !channels.isEmpty else { return nil }
            return BluetoothVolumeDevice(id: id, uid: uid, name: name, channels: channels.contains(0) ? [0] : channels)
        }
    }
    func read(_ device: BluetoothVolumeDevice, channel: UInt32) throws -> Float32 {
        var property = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try check(AudioObjectGetPropertyData(device.id, &property, 0, nil, &size, &value))
        return value
    }
    func write(_ device: BluetoothVolumeDevice, channel: UInt32, scalar: Float32) throws {
        // Check UID again so a recycled CoreAudio ID cannot target a different speaker.
        guard try string(device.id, kAudioDevicePropertyDeviceUID) == device.uid else { throw BluetoothVolumeController.Failure.unavailable }
        var property = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel)
        var value = scalar
        try check(AudioObjectSetPropertyData(device.id, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value))
    }
}
