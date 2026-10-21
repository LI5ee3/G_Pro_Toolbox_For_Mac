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
package enum AudioOutputMonitor {
    package static func shouldHandleVolumeKeys(enabled: Bool, adbConnected: Bool,
                                       gateEnabled: Bool, configuredOutputName: String,
                                       outputName: String?) -> Bool {
        guard enabled, adbConnected else { return false }
        return !gateEnabled || matches(configuredName: configuredOutputName, outputName: outputName)
    }
    /// 默认输出设备名是否匹配配置的关键字。抽成纯函数方便单测。
    ///
    /// - 配置为空：视为「不过滤」，返回 true。
    /// - 读不到设备名：返回 false（宁可放行给系统，也不要吞掉按键却没反应）。
    package static func matches(configuredName: String, outputName: String?) -> Bool {
        let keyword = configuredName.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return true }
        guard let outputName, !outputName.isEmpty else { return false }
        return outputName.localizedCaseInsensitiveContains(keyword)
    }

}
