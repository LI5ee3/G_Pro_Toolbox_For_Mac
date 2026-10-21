import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

// Internal action shorthand. These properties forward to one owner; no observable copies or notifications.
extension AppCoordinator {
    package var connectionIntent: ConnectionIntent {
        get { connection.intent }
        set { connection.intent = newValue }
    }
    package var presetConfiguration: PresetConfiguration {
        get { presets.presetConfiguration }
        set { presets.presetConfiguration = newValue }
    }
    package var isPresetBusy: Bool {
        get { presets.isPresetBusy }
        set { presets.isPresetBusy = newValue }
    }
    package var isPresetOperationInFlight: Bool {
        get { presets.isPresetOperationInFlight }
        set { presets.isPresetOperationInFlight = newValue }
    }
    package var presetOperationText: String {
        get { presets.presetOperationText }
        set { presets.presetOperationText = newValue }
    }
    package var presetError: String? {
        get { presets.presetError }
        set { presets.presetError = newValue }
    }
    package var automaticTaskStatus: String {
        get { presets.automaticTaskStatus }
        set { presets.automaticTaskStatus = newValue }
    }
    package var requestedPage: Page? {
        get { navigation.requestedPage }
        set { navigation.requestedPage = newValue }
    }
    package var connectionStatus: ConnectionStatus {
        get { connection.connectionStatus }
        set { connection.connectionStatus = newValue }
    }
    package var currentValues: [String: String] {
        get { picture.currentValues }
        set { picture.currentValues = newValue }
    }
    package var scannedDevices: [String] {
        get { connection.scannedDevices }
        set { connection.scannedDevices = newValue }
    }
    package var scannedDeviceModels: [String: String] {
        get { connection.scannedDeviceModels }
        set { connection.scannedDeviceModels = newValue }
    }
    package var selectedDevice: String {
        get { connection.selectedDevice }
        set { connection.selectedDevice = newValue }
    }
    package var activeSource: String {
        get { picture.activeSource }
        set { picture.activeSource = newValue }
    }
    package var loadedPages: Set<String> {
        get { picture.loadedPages }
        set { picture.loadedPages = newValue }
    }
    package var isBusy: Bool {
        get { picture.isBusy }
        set { picture.isBusy = newValue }
    }
    /// 正在刷新的页面，用于显示 loading 遮罩
    package var loadingPages: Set<String> {
        get { picture.loadingPages }
        set { picture.loadingPages = newValue }
    }

    package var ipInput: String {
        get { connection.ipInput }
        set { connection.ipInput = newValue }
    }

    // 工具页状态
    package var guardianStatus: String {
        get { tools.guardianStatus }
        set { tools.guardianStatus = newValue }
    }
    package var hdrMemoryEnabled: Bool {
        get { tools.hdrMemoryEnabled }
        set { tools.hdrMemoryEnabled = newValue }
    }
    /// 显示器当前是否处于 4K UI 模式（由 check4KState 检测得到）
    package var is4KUI: Bool {
        get { tools.is4KUI }
        set { tools.is4KUI = newValue }
    }
    package var freesyncMemoryEnabled: Bool {
        get { tools.freesyncMemoryEnabled }
        set { tools.freesyncMemoryEnabled = newValue }
    }
    package var hdrMemoryStatusText: String {
        get { tools.hdrMemoryStatusText }
        set { tools.hdrMemoryStatusText = newValue }
    }
    package var freesyncMemoryStatusText: String {
        get { tools.freesyncMemoryStatusText }
        set { tools.freesyncMemoryStatusText = newValue }
    }
    /// 准星是否只在游戏模式下生效。默认值 true 在 App.init() 里用
    /// register(defaults:) 注册，所以这里可以直接用 bool(forKey:)。
    package var crosshairGameModeOnly: Bool {
        get { tools.crosshairGameModeOnly }
        set { tools.crosshairGameModeOnly = newValue }
    }
    package var crosshairModeStatusText: String {
        get { tools.crosshairModeStatusText }
        set { tools.crosshairModeStatusText = newValue }
    }
    /// 准星联动写入进行中，挡住重入的 reconcile
    package var accessibilityTrusted: Bool {
        get { keyboard.accessibilityTrusted }
        set { keyboard.accessibilityTrusted = newValue }
    }

    /// 快捷键诊断日志。默认关闭：正常打字时每按一个不匹配的键都会记一行，很快把日志刷满。
    package var hotkeyDebugEnabled: Bool {
        get { keyboard.hotkeyDebugEnabled }
        set { keyboard.hotkeyDebugEnabled = newValue; guard !isConfiguring else { return }; preferences.set(hotkeyDebugEnabled, forKey: "hotkey_debug") }
    }
    package var hotkeys: [String: HotkeyConfig] {
        get { keyboard.hotkeys }
        set { keyboard.hotkeys = newValue }
    }
    package var adjustHotkeys: [AdjustHotkeyConfig] {
        get { keyboard.adjustHotkeys }
        set { keyboard.adjustHotkeys = newValue }
    }

    /// 是否把系统亮度调节键接管为显示器背光调节。
    /// 开启后 HotkeyManager 会吞掉系统亮度调节键事件，内置屏幕不再跟着变。
    package var mediaBrightnessKeysEnabled: Bool {
        get { keyboard.mediaBrightnessKeysEnabled }
        set { keyboard.mediaBrightnessKeysEnabled = newValue; guard !isConfiguring else { return };
            preferences.set(mediaBrightnessKeysEnabled, forKey: "media_brightness_keys_enabled")
            applyHotkeys()
            if mediaBrightnessKeysEnabled, !environment.system.isTrusted() {
                requestAccessibilityPrompt()
            } }
    }

    /// 亮度调节键每按一次的背光步长
    package var mediaBrightnessStep: Int {
        get { keyboard.mediaBrightnessStep }
        set { keyboard.mediaBrightnessStep = newValue; guard !isConfiguring else { return }; preferences.set(mediaBrightnessStep, forKey: "media_brightness_step") }
    }

    /// 亮度调节键是否显示 macOS 原生亮度 OSD（而不是本应用 HUD）。
    /// 走私有 OSDUIHelper，失败会自动回退到 HUD。
    package var mediaBrightnessNativeOSD: Bool {
        get { keyboard.mediaBrightnessNativeOSD }
        set { keyboard.mediaBrightnessNativeOSD = newValue; guard !isConfiguring else { return }; preferences.set(mediaBrightnessNativeOSD, forKey: "media_brightness_native_osd") }
    }

    /// 多屏时是否只在焦点位于目标显示器上才拦截亮度键；焦点不在时就交回系统。
    package var mediaBrightnessFocusOnly: Bool {
        get { keyboard.mediaBrightnessFocusOnly }
        set { keyboard.mediaBrightnessFocusOnly = newValue; guard !isConfiguring else { return }; preferences.set(mediaBrightnessFocusOnly, forKey: "media_brightness_focus_only") }
    }

    /// 目标显示器的系统名称（用于多屏焦点判断），默认按 EDID 名 "Mi Monitor"。
    package var mediaBrightnessDisplayName: String {
        get { keyboard.mediaBrightnessDisplayName }
        set { keyboard.mediaBrightnessDisplayName = newValue; guard !isConfiguring else { return }; preferences.set(mediaBrightnessDisplayName, forKey: "media_brightness_display_name") }
    }

    /// 是否把系统音量调节键接管为显示器音量。
    /// 只在「当前默认音频输出匹配目标设备」时生效，否则交回系统去调内置扬声器/AirPods。
    package var mediaVolumeKeysEnabled: Bool {
        get { keyboard.mediaVolumeKeysEnabled }
        set { keyboard.mediaVolumeKeysEnabled = newValue; guard !isConfiguring else { return };
            preferences.set(mediaVolumeKeysEnabled, forKey: "media_volume_keys_enabled")
            applyHotkeys()
            if mediaVolumeKeysEnabled {
                if !environment.system.isTrusted() { requestAccessibilityPrompt() }
                refreshMediaVolumeState()
            } }
    }

    /// 关掉原生音量 OSD 时，每按一次的音量步长
    package var mediaVolumeStep: Int {
        get { keyboard.mediaVolumeStep }
        set { keyboard.mediaVolumeStep = newValue; guard !isConfiguring else { return }; preferences.set(mediaVolumeStep, forKey: "media_volume_step") }
    }

    /// 音量键是否显示 macOS 原生音量 OSD（走私有 OSDUIHelper，失败回退本应用 HUD）。
    package var mediaVolumeNativeOSD: Bool {
        get { keyboard.mediaVolumeNativeOSD }
        set { keyboard.mediaVolumeNativeOSD = newValue; guard !isConfiguring else { return }; preferences.set(mediaVolumeNativeOSD, forKey: "media_volume_native_osd") }
    }

    /// 是否只在默认音频输出匹配指定名称时才接管音量键
    package var mediaVolumeOutputGateEnabled: Bool {
        get { keyboard.mediaVolumeOutputGateEnabled }
        set { keyboard.mediaVolumeOutputGateEnabled = newValue; guard !isConfiguring else { return }; preferences.set(mediaVolumeOutputGateEnabled, forKey: "media_volume_output_gate") }
    }

    /// 目标音频输出设备名（CoreAudio 设备名，匹配用「包含」）
    package var mediaVolumeOutputName: String {
        get { keyboard.mediaVolumeOutputName }
        set { keyboard.mediaVolumeOutputName = newValue; guard !isConfiguring else { return }; preferences.set(mediaVolumeOutputName, forKey: "media_volume_output_name") }
    }

}
