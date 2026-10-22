import ToolboxDomain
import ToolboxApplication
import CoreAudio
import Foundation

enum CoreAudioOutputReader {
    /// 默认输出设备的名称。查不到（无输出设备 / CoreAudio 异常）时返回 nil。
    static func snapshot() -> AudioOutputSnapshot? {
        guard let before = defaultDevice(),
              let name = stringProperty(kAudioObjectPropertyName, device: before),
              let uid = stringProperty(kAudioDevicePropertyDeviceUID, device: before),
              !uid.isEmpty, !name.isEmpty, defaultDevice() == before else { return nil }
        return AudioOutputSnapshot(uid: uid, name: name)
    }
    private static func defaultDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }
    private static func stringProperty(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
