import Foundation
import AppKit
import SwiftUI
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func refreshAccessibilityStatus() {
        let trusted = environment.system.isTrusted()
        guard accessibilityTrusted != trusted else { return }
        accessibilityTrusted = trusted
        if trusted {
            log("辅助功能权限已授权，正在重新注册全局快捷键")
            applyHotkeys()
        } else {
            log("辅助功能权限已撤销，全局快捷键将失效")
        }
    }

    /// 引导授权：先弹系统框（只能弹一次），同时把设置页打开
    package func requestAccessibilityPermission() {
        _ = environment.system.promptAccessibility()
        environment.system.openAccessibility()
        log("请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选本应用，然后回到这里")
    }


    internal static func loadHotkeys(_ preferences: any PreferencesStore) -> [String: HotkeyConfig] {
        guard let data = preferences.data(forKey: "hotkeys"),
              let v = try? JSONDecoder().decode([String: HotkeyConfig].self, from: data) else { return [:] }
        return v
    }

    internal static func loadAdjustHotkeys(_ preferences: any PreferencesStore) -> [AdjustHotkeyConfig] {
        guard let data = preferences.data(forKey: "adjust_hotkeys"),
              let v = try? JSONDecoder().decode([AdjustHotkeyConfig].self, from: data) else { return [] }
        return v
    }

    package func saveHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) {
            preferences.set(data, forKey: "hotkeys")
        }
        if let data = try? JSONEncoder().encode(adjustHotkeys) {
            preferences.set(data, forKey: "adjust_hotkeys")
        }
        applyHotkeys()
        requestAccessibilityPrompt()
        log("全局快捷键已保存并重新注册（如未生效请在系统设置→隐私与安全性→辅助功能中勾选本应用）")
    }

    internal func applyHotkeys() {
        guard isRunning else { return }
        hotkeyManager.clear()
        for (action, cfg) in hotkeys where cfg.isEnabled {
            hotkeyManager.register(id: action, modifierName: cfg.modifier, keyName: cfg.key)
        }
        for (idx, rule) in adjustHotkeys.enumerated() where rule.isEnabled {
            hotkeyManager.register(id: "adjust:\(idx)", modifierName: rule.modifier, keyName: rule.key)
        }
        if mediaBrightnessKeysEnabled {
            hotkeyManager.registerMedia(id: HotkeyManager.mediaBrightnessUpID,
                                        keyType: HotkeyManager.keyTypeBrightnessUp)
            hotkeyManager.registerMedia(id: HotkeyManager.mediaBrightnessDownID,
                                        keyType: HotkeyManager.keyTypeBrightnessDown)
            // 兼容「功能键当标准功能键」的系统设置（此时亮度键发的是普通 keyDown）
            hotkeyManager.registerRaw(id: HotkeyManager.mediaBrightnessUpID,
                                      keyCode: HotkeyManager.keyCodeBrightnessUp)
            hotkeyManager.registerRaw(id: HotkeyManager.mediaBrightnessDownID,
                                      keyCode: HotkeyManager.keyCodeBrightnessDown)
        }
        if mediaVolumeKeysEnabled {
            hotkeyManager.registerMedia(id: HotkeyManager.mediaVolumeUpID,
                                        keyType: HotkeyManager.keyTypeVolumeUp)
            hotkeyManager.registerMedia(id: HotkeyManager.mediaVolumeDownID,
                                        keyType: HotkeyManager.keyTypeVolumeDown)
            hotkeyManager.registerMedia(id: HotkeyManager.mediaMuteID,
                                        keyType: HotkeyManager.keyTypeMute)
            // 兼容「功能键当标准功能键」的系统设置（此时音量键发的是普通 keyDown）
            hotkeyManager.registerRaw(id: HotkeyManager.mediaVolumeUpID,
                                      keyCode: HotkeyManager.keyCodeVolumeUp)
            hotkeyManager.registerRaw(id: HotkeyManager.mediaVolumeDownID,
                                      keyCode: HotkeyManager.keyCodeVolumeDown)
            hotkeyManager.registerRaw(id: HotkeyManager.mediaMuteID,
                                      keyCode: HotkeyManager.keyCodeMute)
        }
        let started = hotkeyManager.start()
        log("全局快捷键: 注册 \(hotkeyManager.bindingCount) 个"
            + (hotkeyManager.mediaBindingCount > 0 ? " + 媒体键 \(hotkeyManager.mediaBindingCount) 个" : "")
            + "，监听\(started ? "已启动" : "启动失败")"
            + "（辅助功能权限：\(environment.system.isTrusted() ? "已授予" : "未授予")）")
    }

    internal func handleHotkeyTrigger(_ id: String) {
        // 系统亮度调节键：固定调背光，立即反馈 + 串行化下发
        if id == HotkeyManager.mediaBrightnessUpID {
            guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
            adjustMediaBrightness(increase: true)
            return
        }
        if id == HotkeyManager.mediaBrightnessDownID {
            guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
            adjustMediaBrightness(increase: false)
            return
        }
        // 系统音量调节键：接管为显示器音量（仅当前音频输出匹配时）
        if id == HotkeyManager.mediaVolumeUpID {
            adjustMediaVolume(increase: true)
            return
        }
        if id == HotkeyManager.mediaVolumeDownID {
            adjustMediaVolume(increase: false)
            return
        }
        if id == HotkeyManager.mediaMuteID {
            toggleMediaMute()
            return
        }
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        if id.hasPrefix("adjust:"), let idx = Int(id.dropFirst("adjust:".count)),
           idx >= 0, idx < adjustHotkeys.count {
            let rule = adjustHotkeys[idx]
            adjustHotkey(param: rule.param, direction: rule.direction, step: rule.step)
            return
        }
        switch id {
        case "picture_mode_cycle": cyclePictureMode()
        case "local_dimming_cycle": cycleLocalDimming()
        case "local_dimming_toggle_off": toggleLocalDimming()
        case "color_space_cycle": cycleColorSpace()
        case "color_temp_cycle": cycleColorTemp()
        case "response_time_cycle": cycleResponseTime()
        case "freesync_toggle": toggleFreesync()
        case "input_source_cycle": cycleSource()
        default: break
        }
    }

    //
    // 对应原版 _cycle_hotkey：连按时先算出下一个值、立刻更新 HUD 预览和界面，
    // 停手 450ms 后才真正下发。否则长按会把命令堆起来 ——
    // JNI 通道单次要 0.5~1 秒，堆几条之后要好几秒才追得上。

    package var hotkeyCountdownEnabled: Bool {
        get { keyboard.hotkeyCountdownEnabled }
        set { keyboard.hotkeyCountdownEnabled = newValue; guard !isConfiguring else { return }; preferences.set(hotkeyCountdownEnabled, forKey: "hotkey_countdown_enabled") }
    }

    /// 倒计时时长（秒）。HUD 的进度条就是这个时长，两边一起变。
    package var hotkeyCountdownSeconds: Double {
        get { keyboard.hotkeyCountdownSeconds }
        set { keyboard.hotkeyCountdownSeconds = newValue; guard !isConfiguring else { return }; preferences.set(hotkeyCountdownSeconds, forKey: "hotkey_countdown_seconds") }
    }

    /// 实际生效前等待多久。0 表示不等待。下限 0.1s 是为了避免设成 0 之后
    /// 退化成"每次按键都立即下发"，那和关掉倒计时没区别了。
    package var effectiveHotkeyDelay: TimeInterval {
        hotkeyCountdownEnabled ? max(0.1, hotkeyCountdownSeconds) : 0
    }

    /// 循环切换的通用实现。
    ///
    /// **纯尾部防抖**：每次按键都重新开始一个完整的倒计时，走完才真正下发。
    /// 也就是说"松手后才生效"—— 连按时只有最后一次的值会落到显示器上。
    ///
    /// 曾经用过"前沿 + 尾部"（第一下立刻生效）：单按确实更跟手，但表现为
    /// "慢速按时倒计时根本不出现、连按时倒计时只剩几十毫秒一闪而过"，
    /// 反而让人以为功能坏了。现在统一成纯尾部，倒计时每次都完整走一遍。
    internal func cycleStep(actionId: String,
                           label: String,
                           order: [Int],
                           valueKey: String,
                           nameFor: (Int) -> String,
                           apply: @escaping (Int) -> Void) {
        guard isConnected else { return log("未连接") }

        // 基准优先取「上一次连按的预览值」，这样快速连按能连续往前推进
        let base = cyclePending[actionId]?.value ?? intValue(valueKey, default: order[0])
        let index = order.firstIndex(of: base).map { ($0 + 1) % order.count } ?? 0
        let next = order[index]

        currentValues[valueKey] = String(next)

        let delay = effectiveHotkeyDelay
        cyclePending[actionId]?.work.cancel()
        cyclePending[actionId] = nil

        // 关掉倒计时：立即下发，HUD 也不显示进度条
        guard delay > 0 else {
            environment.feedback.show(title: label, value: nameFor(next))
            apply(next)
            return
        }

        environment.feedback.show(title: label, value: nameFor(next), countdown: delay)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cyclePending[actionId] = nil
            apply(next)
            environment.feedback.endCountdown()
        }
        cyclePending[actionId] = (next, work)
        environment.scheduler.after(delay, work: work)
    }

    internal func cyclePictureMode() {
        cycleStep(actionId: "picture_mode_cycle", label: "画面模式", order: [14, 10, 9],
                  valueKey: "picture_mode",
                  nameFor: { RegisterMap.sceneNames[$0] ?? "\($0)" }) { [weak self] v in
            self?.setMode(v)
        }
    }

    internal func cycleLocalDimming() {
        let names = ["关", "低", "中", "高"]
        cycleStep(actionId: "local_dimming_cycle", label: "精密控光", order: [0, 1, 2, 3],
                  valueKey: "picture_local_dimming",
                  nameFor: { names[max(0, min(3, $0))] }) { [weak self] v in
            self?.setLocalDimming(v)
        }
    }

    internal func toggleLocalDimming() {
        guard isConnected else { return log("未连接") }
        let names = ["关", "低", "中", "高"]
        let next = intValue("picture_local_dimming", default: 3) == 0 ? 3 : 0
        environment.feedback.show(title: "精密控光", value: names[next])
        setLocalDimming(next)
    }

    internal func cycleColorSpace() {
        let names: [Int: String] = [0: "自动", 3: "sRGB", 4: "Adobe RGB",
                                    5: "BT2020", 6: "DCI-P3", 7: "BT709"]
        cycleStep(actionId: "color_space_cycle", label: "色域", order: [0, 3, 6, 4, 5, 7],
                  valueKey: "tv_picture_advanced_video_color_space",
                  nameFor: { names[$0] ?? "\($0)" }) { [weak self] v in
            self?.setGamut(v)
        }
    }

    internal func cycleColorTemp() {
        let names: [Int: String] = [0: "冷色", 1: "标准", 2: "暖色", 8: "原色", 3: "自定义"]
        cycleStep(actionId: "color_temp_cycle", label: "色温", order: [0, 1, 2, 8, 3],
                  valueKey: "picture_color_temperature",
                  nameFor: { names[$0] ?? "\($0)" }) { [weak self] v in
            self?.setColorTemp(v)
        }
    }

    internal func cycleResponseTime() {
        let names: [Int: String] = [1: "普通", 2: "快速", 3: "高速"]
        cycleStep(actionId: "response_time_cycle", label: "响应时间", order: [1, 2, 3],
                  valueKey: "picture_response_time",
                  nameFor: { names[$0] ?? "\($0)" }) { [weak self] v in
            self?.setResponseTime(v)
        }
    }

    internal func cycleSource() {
        cycleStep(actionId: "input_source_cycle", label: "信号源", order: [23, 24, 29, 30],
                  valueKey: "mitv.tvplayer.hdmi.last.source",
                  nameFor: { RegisterMap.sourceNames[$0] ?? "\($0)" }) { [weak self] v in
            self?.setSource(v)
        }
    }

    /// 各参数待下发的预览值 / 待执行任务（键都是 param）
    package nonisolated static func alignToStep(_ value: Int, step: Int, increasing: Bool) -> Int {
        guard step > 1 else { return value + (increasing ? step : -step) }
        if value % step == 0 { return value + (increasing ? step : -step) }
        return increasing ? ((value / step) + 1) * step : (value / step) * step
    }

    internal func adjustHotkey(param: String, direction: String, step: Int) {
        let delta = direction == "decrease" ? -step : step
        applyAdjustment(param: param, delta: delta, absolute: nil)
    }


    /// 亮度预览值：连按/长按时拿它当基准，必须「粘住」——中途去读设备回读值
    /// 会拿到 refreshPq 后偶发跳变的 JNI 值，导致亮度来回跳。
    /// 内部可见：预设应用在 AppCoordinator+Presets 里要清它。
    internal func adjustMediaBrightness(increase: Bool) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        // 焦点不在目标显示器上时不处理（Hook 对 144/145 已经放过事件，这里再兜一层）
        guard shouldHandleMediaBrightnessForFocus() else { return }

        let current = mediaBrightnessPreview ?? intValue("picture_backlight", default: 50)
        let next: Int
        if mediaBrightnessNativeOSD {
            // 系统 OSD 固定 16 格，按用户步长（如 10）会出现「一格 / 两格」乱跳，
            // 所以开原生 OSD 时固定每按一次移动一格。
            let chiclets = 16
            let chiclet = Int((Double(current) / 100 * Double(chiclets)).rounded())
            let target = min(max(chiclet + (increase ? 1 : -1), 0), chiclets)
            next = clamp(Int((Double(target) / Double(chiclets) * 100).rounded()), 1, 100)
        } else {
            let step = max(1, mediaBrightnessStep)
            next = clamp(AppCoordinator.alignToStep(current, step: step, increasing: increase), 1, 100)
        }
        mediaBrightnessPreview = next
        currentValues["picture_backlight"] = String(next)

        // 视觉反馈立刻跟上手（OSD/HUD 显示到目标值）
        if mediaBrightnessNativeOSD, environment.feedback.brightness(next) {
            // 原生 OSD 自带淡出，不需要收尾
        } else {
            environment.feedback.show(title: "背光", value: "\(next)")
        }

        // 首次按下立即下发：按键即响应，不等去抖。
        // 之后连按只更新预览，由收尾任务在「当前下发完成」后再补一次最终值，
        // 既不会堆积好几条渐变，也不会把第一次的响应拖到停手之后。
        if !mediaBrightnessCommitInFlight, mediaBrightnessCommit == nil {
            commitMediaBrightness()
        }
        scheduleMediaBrightnessTrailing()
    }

    /// 安排收尾提交：`mediaBrightnessCommitDelay` 内没有新按键才补；
    /// 若那时还有下发在跑，就顺延到它结束，避免和进行中的渐变抢设备队列。
    internal func scheduleMediaBrightnessTrailing() {
        mediaBrightnessCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.mediaBrightnessCommitInFlight {
                self.scheduleMediaBrightnessTrailing()
                return
            }
            self.mediaBrightnessCommit = nil
            self.commitMediaBrightness()
        }
        mediaBrightnessCommit = work
        environment.scheduler.after(mediaBrightnessCommitDelay, work: work)
    }

    /// 把当前预览值下发到显示器（渐变）。目标值和已下发值相同时跳过，避免空跑一次。
    internal func commitMediaBrightness() {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete, isConnected else { return }
        guard let value = mediaBrightnessPreview, mediaBrightnessHardware != value else { return }
        // 从「已下发到硬件的值」出发做渐变；首次没有记录时以设备当前值为起点。
        let from = mediaBrightnessHardware ?? intValue("picture_backlight", default: value)
        mediaBrightnessCommitInFlight = true
        setPictureSlider(title: "背光", value: value, jniKey: "g_disp__disp_back_light",
                         settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"],
                         jniRampFrom: from) { [weak self] in
            self?.mediaBrightnessCommitInFlight = false
        }
    }


    /// 音量预览值：连按/长按时拿它当基准；设备回读只在空闲时刷新，
    /// 不会因为中间某次回读跳变把音量带回旧值。
    internal var targetMonitorDisplayID: CGDirectDisplayID? {
        environment.system.targetDisplay(mediaBrightnessDisplayName.trimmingCharacters(in: .whitespaces))
    }
    internal func focusedDisplayID() -> CGDirectDisplayID? { environment.system.focusedDisplay() }

    /// 多屏焦点门：只有鼠标在目标显示器上才拦截亮度键；找不到目标显示器时不过滤。
    package func shouldHandleMediaBrightnessForFocus() -> Bool {
        guard mediaBrightnessFocusOnly else { return true }
        guard let target = targetMonitorDisplayID else { return true }
        return focusedDisplayID() == target
    }

    /// 菜单栏面板里的滑块松手：直接设到指定值（而不是加减一个步长）。
    package func setMenuBarItem(_ id: String, to value: Int) {
        applyAdjustment(param: id, delta: 0, absolute: value)
    }

    /// 调整可调参数的统一入口。`absolute` 非空时直接采用该值，否则按 `delta` 加减。
    internal func applyAdjustment(param: String, delta: Int, absolute: Int?) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }

        /// 暂存一次调整。与 cycleStep 一致：纯尾部，每次改动都重新开始完整倒计时，
        /// 停手后才下发。连续调整时基准取上一次的预览值，所以能连续推进而不是卡住。
        func stage(_ key: String, _ label: String, range: ClosedRange<Int>,
                   fallback: Int, alignToStep: Bool = false, apply: @escaping (Int) -> Void) {
            let base: Int
            if let absolute {
                base = absolute
            } else if alignToStep {
                // 首次调整先对齐到步长的倍数，避免出现 6 → 16 这种「半格」起始值
                let current = adjustPendingValues[param] ?? intValue(key, default: fallback)
                base = AppCoordinator.alignToStep(current, step: abs(delta), increasing: delta > 0)
            } else {
                base = (adjustPendingValues[param] ?? intValue(key, default: fallback)) + delta
            }
            let next = clamp(base, range.lowerBound, range.upperBound)
            adjustPendingValues[param] = next
            currentValues[key] = String(next)

            let delay = effectiveHotkeyDelay
            adjustPendingWork[param]?.cancel()
            adjustPendingWork[param] = nil

            guard delay > 0 else {
                environment.feedback.show(title: label, value: "\(next)")
                adjustPendingValues[param] = nil
                apply(next)
                return
            }

            environment.feedback.show(title: label, value: "\(next)", countdown: delay)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.adjustPendingWork[param] = nil
                self.adjustPendingValues[param] = nil
                apply(next)
                environment.feedback.endCountdown()
            }
            adjustPendingWork[param] = work
            environment.scheduler.after(delay, work: work)
        }

        switch param {
        case "backlight":
            stage("picture_backlight", "背光", range: 1...100, fallback: 50, alignToStep: true) { [weak self] v in
                self?.setPictureSlider(title: "背光", value: v, jniKey: "g_disp__disp_back_light",
                                       settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
            }
        case "black_level":
            stage("picture_brightness", "黑色级别", range: 0...100, fallback: 50) { [weak self] v in
                self?.setPictureSlider(title: "黑色级别", value: v, jniKey: nil,
                                       settingsKeys: ["picture_brightness"])
            }
        // 黑色级别/对比度/饱和度/色调/锐度 在原版里都只写 settings，没有 JNI 键
        case "contrast":
            stage("picture_contrast", "对比度", range: 0...100, fallback: 50) { [weak self] v in
                self?.setPictureSlider(title: "对比度", value: v, jniKey: nil,
                                       settingsKeys: ["picture_contrast"])
            }
        case "saturation":
            stage("picture_saturation", "饱和度", range: 0...100, fallback: 50) { [weak self] v in
                self?.setPictureSlider(title: "饱和度", value: v, jniKey: nil,
                                       settingsKeys: ["picture_saturation"])
            }
        case "hue":
            stage("picture_hue", "色调", range: 0...100, fallback: 50) { [weak self] v in
                self?.setPictureSlider(title: "色调", value: v, jniKey: nil,
                                       settingsKeys: ["picture_hue"])
            }
        case "sharpness":
            stage("picture_sharpness", "锐度", range: 0...100, fallback: 50) { [weak self] v in
                self?.setPictureSlider(title: "锐度", value: v, jniKey: nil,
                                       settingsKeys: ["picture_sharpness"])
            }
        case "red_gain":
            stage("picture_red_gain", "红色增益", range: 524...1524, fallback: 1024) { [weak self] v in
                self?.setColorGain(title: "红色增益", settingsKey: "picture_red_gain",
                                   jniKey: "g_video__clr_gain_r", value: v)
            }
        case "green_gain":
            stage("picture_green_gain", "绿色增益", range: 524...1524, fallback: 1024) { [weak self] v in
                self?.setColorGain(title: "绿色增益", settingsKey: "picture_green_gain",
                                   jniKey: "g_video__clr_gain_g", value: v)
            }
        case "blue_gain":
            stage("picture_blue_gain", "蓝色增益", range: 524...1524, fallback: 1024) { [weak self] v in
                self?.setColorGain(title: "蓝色增益", settingsKey: "picture_blue_gain",
                                   jniKey: "g_video__clr_gain_b", value: v)
            }
        case "atmosphere_illumination":
            // 这一项的 settings 存的是原始挡位（0~14），界面显示 +1（1~15）
            let baseUI = adjustPendingValues[param]
                ?? (intValue("atmosphere_light_illumination", default: 9) + 1)
            let nextUI = clamp(baseUI + delta, 1, 15)
            adjustPendingValues[param] = nextUI
            currentValues["atmosphere_light_illumination"] = String(nextUI - 1)

            let delay = effectiveHotkeyDelay
            adjustPendingWork[param]?.cancel()
            adjustPendingWork[param] = nil

            guard delay > 0 else {
                environment.feedback.show(title: "屏幕灯亮度", value: "\(nextUI)")
                adjustPendingValues[param] = nil
                setLightIllumination(nextUI)
                return
            }

            environment.feedback.show(title: "屏幕灯亮度", value: "\(nextUI)", countdown: delay)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.adjustPendingWork[param] = nil
                self.adjustPendingValues[param] = nil
                self.setLightIllumination(nextUI)
                environment.feedback.endCountdown()
            }
            adjustPendingWork[param] = work
            environment.scheduler.after(delay, work: work)
        default:
            break
        }
    }
}
