import CoreAudio
import Foundation

/// 当前默认音频输出设备的查询（CoreAudio）。
///
/// 音量键接管的前提是「声音真的从显示器出来」：只有默认输出设备名匹配时
/// 才拦截，否则原样交回系统（去调内置扬声器 / AirPods 的音量）。
///
/// 注意 Mac 上显示器音频可能以两种名字出现：
///   - DisplayPort/HDMI 直连：`Mi Monitor`
///   - 经过 eqMac 等虚拟声卡转发：`Mi Monitor (eqMac)`
/// 所以匹配用「包含」而不是全等，默认关键字 `Mi Monitor` 两种都能命中。
enum AudioOutputMonitor {
    static func shouldHandleVolumeKeys(enabled: Bool, bluetoothAvailable: Bool, adbConnected: Bool,
                                       gateEnabled: Bool, configuredOutputName: String,
                                       bluetoothOutputName: String?, outputName: String?) -> Bool {
        guard enabled, bluetoothAvailable || adbConnected else { return false }
        guard gateEnabled else { return true }
        return matches(configuredName: configuredOutputName, outputName: outputName)
            || (bluetoothOutputName != nil && outputName?.caseInsensitiveCompare(bluetoothOutputName!) == .orderedSame)
    }
    /// 默认输出设备的名称。查不到（无输出设备 / CoreAudio 异常）时返回 nil。
    static func defaultOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &deviceAddress, 0, nil,
                                                &deviceSize, &deviceID)
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }

        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    /// 默认输出设备名是否匹配配置的关键字。抽成纯函数方便单测。
    ///
    /// - 配置为空：视为「不过滤」，返回 true。
    /// - 读不到设备名：返回 false（宁可放行给系统，也不要吞掉按键却没反应）。
    static func matches(configuredName: String, outputName: String?) -> Bool {
        let keyword = configuredName.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return true }
        guard let outputName, !outputName.isEmpty else { return false }
        return outputName.localizedCaseInsensitiveContains(keyword)
    }

    /// 便捷入口：直接按当前默认输出设备判断。
    static func defaultOutputMatches(configuredName: String) -> Bool {
        matches(configuredName: configuredName, outputName: defaultOutputDeviceName())
    }
}
