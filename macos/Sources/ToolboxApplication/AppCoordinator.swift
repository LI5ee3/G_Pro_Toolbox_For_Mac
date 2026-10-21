import ToolboxDomain
import Foundation
import SwiftUI
import AppKit
import MimonitorPresetCore

// MARK: - ADB 保活守护（AdbGuardian）

internal enum Guardian {
    package static let package = "com.example.adbguardian"
    package static let mainActivity = "\(package)/.MainActivity"
    package static let accessibility = "\(package)/\(package).AdbGuardianAccessibilityService"
}

internal struct GuardianStatus {
    package let installed: Bool
    package let pid: String
    package let accessibility: Bool
    package let adbEnabled: Bool
    package let adbWifiEnabled: Bool
    package let servicePort: String
    package let persistPort: String
    package let adbd: String
    package let mask: String
    package let stopped: Bool

    package var ok: Bool {
        installed && !pid.isEmpty && adbEnabled && adbWifiEnabled
            && servicePort == "5555" && persistPort == "5555"
            && adbd == "running" && accessibility && mask == "-134250497" && !stopped
    }

    package var summary: String {
        if ok { return "状态：✅ 正常（已安装 · 保活运行中 · 端口 5555 · 无障碍已授权）" }
        var parts: [String] = []
        if !installed { parts.append("未安装") }
        else if pid.isEmpty { parts.append("未运行") }
        if !adbEnabled { parts.append("adb_enabled≠1") }
        if !adbWifiEnabled { parts.append("adb_wifi≠1") }
        if servicePort != "5555" || persistPort != "5555" { parts.append("端口≠5555") }
        if adbd != "running" { parts.append("adbd 未运行") }
        if !accessibility { parts.append("无障碍未授权") }
        if stopped { parts.append("被停止") }
        if parts.isEmpty { return "状态：已安装（部分检查未通过）" }
        return "状态：⚠️ \(parts.joined(separator: " / "))"
    }
}

/// Migration action coordinator. Observable state belongs to narrow MainActor models, never this facade.
/// 对应原版 App 类的职责（不含 UI 控件，UI 由各 View 负责）。
@MainActor
public final class AppCoordinator {
    package let connection = ConnectionModel()
    package let picture = PictureModel()
    package let presets = PresetsModel()
    package let navigation = NavigationModel()
    package let volume = VolumeModel()
    package let tools = ToolsModel()
    package let keyboard = HotkeysModel()
    package nonisolated let adb: AdbClient
    package nonisolated let environment: AppEnvironment
    package nonisolated let preferences: any PreferencesStore
    internal nonisolated let executionLifetime = RuntimeGeneration()
    internal var isConfiguring = true
    package private(set) var isRunning = false
    internal var runtimeTasks: [RuntimeCancellation] = []
    internal var startupWork: [DispatchWorkItem] = []
    package let hotkeyManager: HotkeyManager
    internal var pageRefreshIntent = PageRefreshIntent()
    internal let connectionQueue = DispatchQueue(label: "com.mimonitor.toolbox.connection")
    package nonisolated let deviceQueue = DispatchQueue(label: "com.mimonitor.toolbox.device", qos: .userInitiated)
    package nonisolated let presetEngine: PresetEngine
    package var presetTimer: RuntimeCancellation?
    package var pendingPresetSave: DispatchWorkItem?
    package var pendingPresetSaveID: String?
    package var pendingPresetSaveDevice: String?
    package var pictureEditRevision = 0
    /// Only accessed on deviceQueue; native mode/reset commands may settle after ADB returns.
    internal nonisolated let deviceWorkState = DeviceWorkState()
    package var lastAutomaticTaskError = ""

    package let logs = LogModel()
    package var logLines: [String] { get { logs.lines } set { logs.lines = newValue } }
    /// 每写一行日志就自增。界面靠它触发自动滚动 ——
    /// 不能用 logLines.count：日志满 500 行后会 removeFirst，count 恒定不变，
    /// 于是滚动就再也不触发了。
    package var logSeq: Int { get { logs.sequence } set { logs.sequence = newValue } }
    package var logToFileEnabled: Bool { get { logs.recordsToFile } set { logs.recordsToFile = newValue } }
    internal var crosshairReconcileBusy = false
    /// 上一次对账时的画面模式，用于区分「进入游戏模式」与「一直在游戏模式」
    internal var crosshairLastMode: String?
    /// 本 app 是否已获辅助功能权限（和终端是两回事，各算各的）
    internal var hdrLastState: Bool?
    internal var sourcePollTimer: RuntimeCancellation?
    internal var sourcePollArmed = false
    internal var monitorChecking = false
    internal var monitorTick = 0
    internal var lastMonitorFailState = ""
    /// 切页时刻，用于统计刷新耗时
    internal var pageAppearTimes: [String: Date] = [:]

    internal static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    internal static let fileTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    package let settings: SettingsModel
    package var theme: String { get { settings.theme } set { settings.theme = newValue } }
    package var closeBehavior: String { get { settings.closeBehavior } set { settings.closeBehavior = newValue } }
    package var autostartEnabled: Bool { get { settings.autostartEnabled } set { settings.autostartEnabled = newValue } }

    package init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = SettingsModel(preferences: environment.preferences, applyTheme: environment.system.applyTheme)
        self.preferences = environment.preferences
        self.adb = environment.adb
        self.hotkeyManager = environment.hotkeys
        preferences.register(defaults: ["crosshair_game_mode_only": true])
        self.presetEngine = PresetEngine(store: PresetStore(defaults: preferences))
        self.ipInput = preferences.string(forKey: "saved_ip") ?? ""
        self.hdrMemoryEnabled = preferences.bool(forKey: "hdr_sdr_local_dimming_enabled")
        self.freesyncMemoryEnabled = preferences.bool(forKey: "freesync_mode_memory_enabled")
        self.crosshairGameModeOnly = preferences.bool(forKey: "crosshair_game_mode_only")
        self.accessibilityTrusted = false
        self.hotkeyDebugEnabled = preferences.bool(forKey: "hotkey_debug")
        self.hotkeys = Self.loadHotkeys(preferences)
        self.adjustHotkeys = Self.loadAdjustHotkeys(preferences)
        self.mediaBrightnessKeysEnabled = preferences.bool(forKey: "media_brightness_keys_enabled")
        self.mediaBrightnessStep = preferences.object(forKey: "media_brightness_step") as? Int ?? 5
        self.mediaBrightnessNativeOSD = preferences.object(forKey: "media_brightness_native_osd") as? Bool ?? true
        self.mediaBrightnessFocusOnly = preferences.object(forKey: "media_brightness_focus_only") as? Bool ?? true
        self.mediaBrightnessDisplayName = preferences.string(forKey: "media_brightness_display_name") ?? "Mi Monitor"
        self.mediaVolumeKeysEnabled = preferences.bool(forKey: "media_volume_keys_enabled")
        self.mediaVolumeStep = preferences.object(forKey: "media_volume_step") as? Int ?? 5
        self.mediaVolumeNativeOSD = preferences.object(forKey: "media_volume_native_osd") as? Bool ?? true
        self.mediaVolumeOutputGateEnabled = preferences.object(forKey: "media_volume_output_gate") as? Bool ?? true
        self.mediaVolumeOutputName = preferences.string(forKey: "media_volume_output_name") ?? "Mi Monitor"
        self.menuBarItems = Self.loadMenuBarItems(preferences)
        self.hotkeyCountdownEnabled = preferences.object(forKey: "hotkey_countdown_enabled") as? Bool ?? true
        self.hotkeyCountdownSeconds = preferences.object(forKey: "hotkey_countdown_seconds") as? Double ?? 0.8
        self.presetConfiguration = presetEngine.configuration
        self.presetError = presetEngine.loadError
        self.isConfiguring = false
        if environment.mode == .simulation { executionLifetime.begin() }
    }

    /// Fixture entry point. It cannot modify a production runtime.
    package func seedSimulationReadings(volume: Int?, muted: Bool?) {
        precondition(environment.mode == .simulation)
        dashboardVolume = volume; dashboardMuted = muted
        mediaVolumeHardware = volume; mediaVolumePreview = volume; mediaVolumeMuted = muted
    }

    /// The app lifetime owns live services; construction and previews never start them.
    package func start() {
        if environment.mode == .simulation { executionLifetime.resumeIfNeeded(); return }
        guard !isRunning else { return }
        isRunning = true
        executionLifetime.begin()
        accessibilityTrusted = environment.system.isTrusted()
        autostartEnabled = environment.system.autostartEnabled()
        environment.system.applyTheme(theme)

        startPresetFeatures()
        log("系统就绪，等待连接...")
        hotkeyManager.onTrigger = { [weak self] id in self?.handleHotkeyTrigger(id) }
        // 诊断默认关闭：每按一个不匹配的键就写一行日志，正常打字会把日志刷满。
        // 在「自定义全局快捷键」面板里按需打开。
        hotkeyManager.onKeyCodeMatch = { [weak self] code, flags, expected in
            guard let self, self.hotkeyDebugEnabled else { return }
            self.log("快捷键诊断: 按键码 \(code) 命中，但修饰键不符（实收 \(flags.rawValue) / 期望 \(expected.rawValue)）")
        }
        // 亮度/音量这类系统媒体键的诊断。用来区分「系统没发事件」和「解析没命中」。
        hotkeyManager.onMediaKeyEvent = { [weak self] keyType, isDown in
            guard let self, self.hotkeyDebugEnabled else { return }
            self.log("媒体键诊断: 类型 \(keyType) \(isDown ? "按下" : "抬起")")
        }
        // 媒体键拦截门：亮度键看多屏焦点，音量键看当前默认音频输出，其余一律放行。
        hotkeyManager.shouldHandleMediaKey = { [weak self] keyType in
            guard let self else { return true }
            if HotkeyManager.isBrightnessKeyType(keyType) {
                return self.shouldHandleMediaBrightnessForFocus()
            }
            if HotkeyManager.isVolumeKeyType(keyType) {
                return self.shouldHandleNativeVolume()
            }
            return false
        }
        hotkeyManager.onTapDisabled = { [weak self] in
            self?.log("快捷键诊断: 事件监听被系统禁用，已重新启用")
        }
        applyHotkeys()
        updateHdrMemoryStatus()
        updateFreesyncMemoryStatus()
        updateCrosshairModeStatus()
        runtimeTasks.append(environment.scheduler.repeating(every: 3, commonModes: false) { [weak self] in self?.pollHdrState() })
        // 音量缓存：显示器自带的遥控器/按键也能改音量，定期回读一次，
        // 避免下次按 Mac 音量键时从过期值起步。
        runtimeTasks.append(environment.scheduler.repeating(every: 5, commonModes: false) { [weak self] in self?.refreshMediaVolumeState() })
        refreshMediaVolumeState()
        // 配了快捷键却没授权：启动时引导一次。
        // 系统授权框每个 app 只会弹一次，之后再调用是静默的，所以只在有快捷键配置时尝试。
        if !accessibilityTrusted && !hotkeys.isEmpty {
            scheduleStartup(after: 1.5) { [weak self] in
                _ = self?.environment.system.promptAccessibility()
            }
        }

        // 先把 adb server 预热起来，省得自动连接那一步还要等它冷启动
        runConnectionTask { self.adb.warmUpServer() }

        // 启动后自动连接上次设备（原版延迟 900ms，等窗口先出来）
        scheduleStartup(after: 0.9) { [weak self] in
            self?.autoConnectOnStartup()
        }
        // adb 链路监控（对应原版 _monitor_adb_server）。
        // 每 6 秒一跳：未连接时每跳都重试（故障恢复要快），已连接时每 5 跳体检一次。
        runtimeTasks.append(environment.scheduler.repeating(every: 6, commonModes: false) { [weak self] in
            guard let self else { return }
            self.monitorTick &+= 1
            if self.isConnected && self.monitorTick % 5 != 0 { return }
            self.monitorAdbServer()
        })
        runtimeTasks.append(environment.system.observeWake({ [weak self] in
            self?.recoverAfterWake(); self?.checkAutomaticTasks()
        }, { [weak self] in self?.recoverAfterWake() }))
    }

    package func stop() {
        executionLifetime.end()
        isRunning = false
        connectionIntent.disconnect()
        runtimeTasks.forEach { $0.invalidate() }; runtimeTasks.removeAll()
        startupWork.forEach { $0.cancel() }; startupWork.removeAll()
        presetTimer?.invalidate(); presetTimer = nil
        sourcePollTimer?.invalidate(); sourcePollTimer = nil; sourcePollArmed = false
        pendingPresetSave?.cancel(); pendingPresetSave = nil
        pendingRefreshWork?.cancel(); pendingRefreshWork = nil
        cyclePending.values.forEach { $0.work.cancel() }; cyclePending.removeAll()
        adjustPendingWork.values.forEach { $0.cancel() }; adjustPendingWork.removeAll()
        mediaBrightnessCommit?.cancel(); mediaBrightnessCommit = nil
        resetMediaVolumeSession()
        hotkeyManager.stop()
        environment.feedback.stop()
        environment.system.stopLog()
    }

    deinit {
        runtimeTasks.forEach { $0.invalidate() }
        startupWork.forEach { $0.cancel() }
        presetTimer?.invalidate(); sourcePollTimer?.invalidate()
        pendingPresetSave?.cancel(); pendingRefreshWork?.cancel()
        hotkeyManager.stop()
    }

    internal func scheduleStartup(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard self?.isRunning == true else { return }; action()
        }
        startupWork.append(work)
        environment.scheduler.after(delay, work: work)
    }

    /// 探活并自愈。
    ///
    /// 两种失效都会表现为连不上：server 长时间运行后失效（报 "No route to host"），
    /// 以及 adb connect 后卡在 offline 不翻转。两者都靠 kill-server + start-server 治，
    /// 但设备侧清掉旧 transport 需要时间，所以要反复重试而不是只试一次。
    internal func monitorAdbServer(refreshState: Bool = false) {
        guard !monitorChecking else { return }
        guard connectionIntent.allowsAutomaticRecovery else { return }
        // 正在连接/扫描时不要插手：监控会重启 adb server，而重启会把
        // 进行中的连接打断，于是「越监控越连不上」。这是之前冷启动很慢的元凶。
        switch connectionStatus {
        case .connecting, .scanning: return
        case .disconnected, .connected: break
        }

        // 未连接时也要能重试，所以目标从 adb.ip 兜底到上次保存的 IP
        let target = adb.ip.isEmpty
            ? (preferences.string(forKey: "saved_ip") ?? "").trimmingCharacters(in: .whitespaces)
            : adb.ip
        guard !target.isEmpty else { return }

        let wasConnected = isConnected    // 在主线程序上读，避免后台 sync 主线程
        let request = connectionIntent.generation
        if adb.ip.isEmpty { adb.ip = target }
        monitorChecking = true
        runConnectionTask {
            defer { DispatchQueue.main.async { self.monitorChecking = false } }

            if wasConnected && self.adb.deviceState() == "device" && self.adb.transportWorks() {
                // 唤醒时连接可能仍可用，但显示器的音量和保活设置已经变化。
                if refreshState {
                    DispatchQueue.main.async {
                        guard self.connectionIntent.isCurrent(request),
                              self.connectionIntent.allowsAutomaticRecovery else { return }
                        self.refreshMediaVolumeState()
                        self.checkGuardian()
                    }
                }
                return
            }

            if !self.adb.isServerAlive() { self.adb.restartServer() }
            let (ok, state) = self.adb.ensureConnected()
            let model = ok ? self.adb.getModel() : ""

            DispatchQueue.main.async {
                guard self.connectionIntent.isCurrent(request),
                      self.connectionIntent.allowsAutomaticRecovery else { return }
                if ok {
                    let ip = target
                    self.connectionStatus = .connected(model.isEmpty ? ip : "\(model) · \(ip)")
                    if !wasConnected {
                        // 关键：恢复后必须把连接状态也置回已连接，
                        // 否则界面一直以为"未连接"，点任何页面都会被弹回主页。
                        self.log("已连接: \(ip)")
                        self.loadedPages = []
                        self.refreshPage("picture")
                        self.refreshPage("game")
                        self.pollHdrState(force: true)
                        self.checkAutomaticTasks()
                    } else {
                        self.log("ADB 链路已恢复")
                    }
                    self.lastMonitorFailState = ""
                    self.refreshMediaVolumeState()
                    self.checkGuardian()
                } else if self.isConnected {
                    self.connectionStatus = .disconnected
                    self.log("ADB 链路恢复失败: \(state)")
                } else if self.lastMonitorFailState != state {
                    // 未连接状态下只在失败原因变化时记一次，避免每 6 秒刷屏
                    self.lastMonitorFailState = state
                    self.log("自动重连失败: \(state)")
                }
            }
        }
    }


    package var gameModeHintIsWarning: Bool { gameModeState != .active }

    package var isCustomColorTemp: Bool { intValue("picture_color_temperature", default: 1) == 3 }

    internal var pendingRefreshWork: DispatchWorkItem?

    /// 合并「设置改动后回读真实值」的刷新。
    ///
    /// 不合并的话，连按快捷键每按一次就排一次全文刷新（21 个 settings + 6 个 JNI 键，
    /// 还要重绘整页），十几次堆起来会把 ADB 通道占满 —— 表现就是"按多了就卡"。
    /// 原版用 `_picture_mode_switch_seq` 做同样的事。
    package static let refreshablePages: Set<String> = ["picture", "game", "source", "light"]

    package internal(set) var hdrStateSource = ""

    internal static let menuBarKey = "menubar_items"

    internal var cyclePending: [String: (value: Int, work: DispatchWorkItem)] = [:]

    /// 是否启用「松手后生效」的倒计时。
    /// 关掉之后每次按键立即下发 —— 更跟手，但连按会把 ADB 命令堆起来。
    internal var adjustPendingValues: [String: Int] = [:]
    internal var adjustPendingWork: [String: DispatchWorkItem] = [:]

    /// 把值对齐到 `step` 的倍数：不在格点上时朝调整方向跳到最近的格点，
    /// 已经在格点上就正常加减一个 step。例：值 6、步长 10、调亮 → 10；再按 → 20。
    package var mediaBrightnessPreview: Int?
    /// 最近一次真正下发到硬件的背光值；渐变以它为起点，连按时从设备真实位置平滑推进，
    /// 不会因为「预览已加到 60、硬件还停在 50」而在起点先跳一大步。
    package var mediaBrightnessHardware: Int?
    /// 待下发的收尾任务（尾部去抖）
    internal var mediaBrightnessCommit: DispatchWorkItem?
    /// 是否有一次下发正在跑（设备队列里跑渐变 + 等完成信号，约 0.4s）
    internal var mediaBrightnessCommitInFlight = false

    /// 收尾提交延迟：一段连按结束后多久补上最终值。首次按下是立即下发的，
    /// 这个延迟只决定「连按过程中的中间值什么时候被合并掉」。
    internal let mediaBrightnessCommitDelay: TimeInterval = 0.12

    internal var mediaVolumePreview: Int?
    /// 最近一次真正下发到设备的音量
    internal var mediaVolumeHardware: Int?
    /// 设备当前是否静音（nil = 未知）
    internal var mediaVolumeMuted: Bool?
    /// 连按期间出现过「静音状态下按音量键」，收尾时需要先解除静音
    internal var mediaVolumeNeedsUnmute = false
    /// 待下发的收尾任务（尾部去抖）
    internal var mediaVolumeCommit: DispatchWorkItem?
    /// 是否有一次下发正在跑
    internal var mediaVolumeCommitInFlight = false
    /// 回退通道只提示一次，避免连按刷屏
    internal var mediaVolumeFallbackLogged = false

    /// 收尾提交延迟：首次按下立即下发，这个延迟只决定连按中间值何时被合并。
    internal let mediaVolumeCommitDelay: TimeInterval = 0.12

}
