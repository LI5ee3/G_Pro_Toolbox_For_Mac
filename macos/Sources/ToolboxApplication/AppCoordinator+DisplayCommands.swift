import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func setMode(_ value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        let name = RegisterMap.modeNames[value] ?? "\(value)"
        currentValues["picture_mode"] = String(value)
        log("模式: \(name)")
        reconcileCrosshairModeState()
        runPictureChange(delay: 1.5) {
            self.adb.settingsPut("picture_mode", String(value))
            self.publish {
                self.scheduleCoalescedRefresh(delay: 1.2, pages: ["picture"])
            }
        }
    }

    package func resetCurrentMode() {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        let mode = intValue("picture_mode", default: -1)
        guard let name = RegisterMap.modeNames[mode] else { log("无法获取当前模式"); return }
        log("恢复 \(name) 模式默认设置...")
        runPictureChange(delay: 3.2) {
            self.adb.jniSet(key: "g_fusion_picture__pic_reset_def_bypicmode", value: "0")
            self.adb.refreshPq()
            self.publish {
                self.scheduleCoalescedRefresh(delay: 3, pages: ["picture"])
            }
        }
    }

    /// 通用滑条：写 JNI + settings，然后 refresh_pq。
    /// `jniRampFrom` 非空时改用显示器端渐变（见 `jniRamp`）——亮度键走这条，避免大步长过冲。
    package func setPictureSlider(title: String, value: Int, jniKey: String?, settingsKeys: [String],
                          jniRampFrom: Int? = nil, completion: (() -> Void)? = nil) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { completion?(); return }
        guard isConnected else { log("未连接"); completion?(); return }
        // 背光：同步本地预览。媒体键下次拿它当基准，不会被刷新回读到的 JNI 值带偏
        // （那个值偶发会跳，表现就是亮度先冲高再回落）。同时记住已下发到硬件的值，供下次渐变当起点。
        if jniKey == "g_disp__disp_back_light" {
            mediaBrightnessPreview = value
            mediaBrightnessHardware = value
        }
        log("\(title): \(value)")
        runPictureChange(completion: completion) {
            if let jniKey, let jniRampFrom {
                // 渐变：显示器端按 step 推进；等它跑完再由设备侧写 settings。
                // settings 观察者会直接改硬件，所以必须等渐变结束再写（此时硬件已在目标值，
                // 再套用一次等于空操作），否则会先把画面拉到目标值、把渐变打断。
                // 单格亮度变化约为 6–7%，不必按 1% 拆成多次 JNI 写入；
                // 更大的变化仍保留渐变，并把总步数压到 ~16 步内。
                let delta = abs(value - jniRampFrom)
                let oneChiclet = Int(ceil(100.0 / Double(16)))
                let isOneChiclet = delta <= oneChiclet
                let step = isOneChiclet ? max(1, delta) : max(1, Int(ceil(Double(delta) / 16.0)))
                let rampFrom = isOneChiclet ? value : jniRampFrom
                self.adb.jniRamp(key: jniKey, from: rampFrom, to: value,
                                 settingsKeys: settingsKeys, step: step)
            } else {
                if let jniKey {
                    self.adb.jniSet(key: jniKey, value: String(value))
                    self.adb.refreshPq()
                }
                self.adb.settingsPutBatch(settingsKeys.map { ($0, String(value)) })
            }
        }
    }

    package func setColorTemp(_ sv: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        let jv = RegisterMap.colorTempToMtk[sv] ?? 0
        let names: [Int: String] = [0: "冷色", 1: "标准", 2: "暖色", 8: "原色", 3: "自定义"]
        currentValues["picture_color_temperature"] = String(sv)
        log("色温: \(names[sv] ?? "\(sv)")")
        runPictureChange {
            self.adb.jniSet(key: "g_video__clr_temp", value: String(jv))
            self.adb.settingsPut("picture_color_temperature", String(sv))
            self.adb.refreshPq()
        }
    }

    package func setColorGain(title: String, settingsKey: String, jniKey: String, value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        func gain(_ key: String) -> Int {
            let v = (settingsKey == key) ? value : intValue(key, default: 1024)
            return max(524, min(1524, v))
        }
        let red = gain("picture_red_gain")
        let green = gain("picture_green_gain")
        let blue = gain("picture_blue_gain")

        currentValues["picture_color_temperature"] = "3"
        currentValues["picture_red_gain"] = String(red)
        currentValues["picture_green_gain"] = String(green)
        currentValues["picture_blue_gain"] = String(blue)
        log("\(title): \(value)")

        runPictureChange {
            self.adb.jniSet(key: "g_video__clr_temp", value: String(RegisterMap.colorTempToMtk[3] ?? 0))
            self.adb.settingsPut("picture_color_temperature", "3")
            self.adb.setColorGains(red: String(red), green: String(green), blue: String(blue))
            self.adb.settingsPut("picture_red_gain", String(red))
            self.adb.settingsPut("picture_green_gain", String(green))
            self.adb.settingsPut("picture_blue_gain", String(blue))
            self.adb.refreshPq()
        }
    }

    package func setLocalDimming(_ value: Int) {
        guard let valueName = RegisterMap.localDimmingNames[value] else { return }
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        currentValues["picture_local_dimming"] = String(value)
        log("精密控光: \(valueName)")
        if hdrMemoryEnabled, !memoriesSuspendedByPreset, let state = hdrLastState {
            var m = localDimmingMemory()
            m[state ? "hdr" : "sdr"] = value
            saveLocalDimmingMemory(m)
        }
        runPictureChange {
            self.adb.jniSet(key: "g_video__vid_local_dimming", value: String(value))
            self.adb.settingsPut("picture_local_dimming", String(value))
            self.adb.settingsPut("tv_picture_video_local_dimming", String(value))
            self.adb.refreshPq()
        }
    }

    /// 自动调整亮度（光感）开关。
    ///
    /// 这个开关有**两份状态**，必须都写：`tv_picture_light_sensor` 是
    /// MiBackLightManager 真正监听的（功能立即生效），MTK 的
    /// `g_video__light_sensor_switch` 才是设置菜单显示的值。只写前者功能会生效，
    /// 但菜单显示不同步。
    ///
    /// 注意这只是**结果状态等价**，不是过程等价：照抄的是某一次拨动的写入快照，
    /// 没有走 App 层的 setLightSensor() 判断，也不触发菜单的埋点上报。
    ///
    /// 菜单手拨「开」还会顺带写三个 DBC（动态背光）的值；本机未启用那套功能
    /// （没有 mitv.settings.backlight.dbc 功能位），写入效果**未经验证**，故不写。
    ///
    /// 两处偏离本模块其他 JNI 写入的惯例，都是有意的：`upd` 传 1（其余处用默认的
    /// 3），这是实测手拨菜单抓到的值；不跟 `refreshPq()`，光感由 ContentObserver
    /// 立即生效，菜单路径里没有这一步。
    package func setLightSensor(_ on: Bool) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        let value = on ? 1 : 0
        currentValues["tv_picture_light_sensor"] = String(value)
        log("自动调整亮度: \(on ? "开" : "关")")
        runPictureChange {
            // settings put 必须由 adb shell 执行（shell 持有 WRITE_SECURE_SETTINGS）；
            // 塞进 service call TvService 会被 tvservice 的 uid 静默拒绝 —— 所以这两条
            // 是两次独立调用，不要"优化"成一条 TvService 命令。
            self.adb.jniSet(key: "g_video__light_sensor_switch", value: String(value), upd: 1)
            self.adb.settingsPut("tv_picture_light_sensor", String(value))
        }
    }

    package func setHdrToneMapping(_ uiValue: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        guard let mtk = RegisterMap.hdrToneMappingUIToMtk[uiValue] else { return }
        let names: [Int: String] = [0: "HGiG", 1: "层次", 2: "动态", 3: "明亮"]
        currentValues["settings_display_hdr_color_tone"] = String(uiValue)
        log("HDR 色调映射: \(names[uiValue] ?? "\(uiValue)")")
        runPictureChange {
            self.adb.hdrToneMapping(String(mtk))
            self.adb.settingsPut("picture_hdr_tone_mapping", String(mtk))
            self.adb.settingsPut("settings_display_hdr_color_tone", String(uiValue))
            self.adb.refreshPq()
        }
    }

    package func setDynamicDefinition(_ value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        currentValues["picture_dynamic_definition"] = String(value)
        log("动态清晰度: \(["关", "低", "中", "高"][value])")
        runPictureChange {
            self.adb.jniSet(key: "g_video__vid_insert_black", value: String(value))
            self.adb.settingsPut("picture_dynamic_definition", String(value))
            self.adb.refreshPq()
        }
    }

    package func setResponseTime(_ value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        currentValues["picture_response_time"] = String(value)
        log("响应时间: \(["", "普通", "快速", "高速"][value])")
        runPictureChange {
            self.adb.jniSet(key: "g_video__vid_od_response_time", value: String(value))
            self.adb.settingsPut("picture_response_time", String(value))
            self.adb.refreshPq()
        }
    }

    package func setGamut(_ value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        let names: [Int: String] = [0: "自动", 3: "sRGB", 6: "DCI-P3", 4: "Adobe RGB", 5: "BT2020", 7: "BT709"]
        currentValues["tv_picture_advanced_video_color_space"] = String(value)
        log("色域: \(names[value] ?? "\(value)")")
        runPictureChange {
            self.adb.jniSet(key: "g_video__vid_gamut_mapping_mode", value: String(value))
            self.adb.settingsPut("tv_picture_advanced_video_color_space", String(value))
            self.adb.settingsPut("tv_picture_video_color_space", String(value))
            self.adb.refreshPq()
        }
    }


    package func setGameFeature(key: String, value: Int, message: String) {
        guard isConnected else { return log("未连接") }
        currentValues[key] = String(value)
        log(message)
        runBackground {
            self.adb.settingsPut(key, String(value))
            self.adb.refreshPq()
        }
    }

    package func setCrosshair(_ value: Int) {
        guard isConnected else { return log("未连接") }
        // 用户在游戏模式下的主动选择同步进记忆：关掉即清记忆（避免下次回到
        // 游戏模式又被自动还原回来），选了样式则更新记忆值。
        if connection.memoryOwnershipConfirmed, connection.allowsIdentityAutomaticActions {
            if value == 0 { clearCrosshairMemory() }
            else { saveCrosshairMemory(value) }
        }
        currentValues["front_sight_index"] = String(value)
        log("准星: \(value == 0 ? "关" : "\(value)")")
        runBackground {
            self.adb.settingsPut("front_sight_index", String(value))
            // 游戏模式下重触发让准星生效（移植自 _fs -> _set_game_feature(retrigger=True)）
            let mode = self.adb.settingsGet("picture_mode")
            if RegisterMap.isGamePictureMode(mode) {
                self.adb.settingsPut("picture_mode", "14")
                guard self.adb.pause(0.5) else { return }
                self.adb.settingsPut("picture_mode", "10")
            } else {
                self.adb.refreshPq()
            }
        }
    }

    package func setMode320(_ on: Bool) {
        guard isConnected else { return log("未连接") }
        currentValues["mode_320"] = on ? "1" : "0"
        log("320Hz: \(on ? "开" : "关")")
        runBackground {
            let src = self.adb.settingsGet("mitv.tvplayer.hdmi.last.source")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if src == "29" || src == "30" {
                self.adb.jniSet(key: "g_fusion_picture__dp_edid_version", value: on ? "3" : "2")
            } else {
                self.adb.jniSet(key: "g_fusion_picture__hdmi_edid_version", value: on ? "6" : "1")
            }
            self.adb.refreshPq()
            self.refreshAfterEdidChange()
        }
    }

    /// 切换 FreeSync。当前状态从设备现读 —— 不能用缓存的 currentValues["freesync"]，
    /// 那个值来自 JNI 回读，读取偶发失败会把它留在 0，于是每次都算出"要开启"，
    /// 表现就是按了没反应。
    package func toggleFreesync() {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        runBackground {
            let src = self.adb.settingsGet("mitv.tvplayer.hdmi.last.source")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isDP = (src == "29" || src == "30")
            let key = isDP ? "g_video__dp_adaptive_sync" : "g_video__freesync_switch"
            let raw = Int(self.adb.jniBatchGet(keys: [key])[key] ?? "") ?? -1
            let isOn = isDP ? (raw == 1) : (raw == 3)
            self.publish { self.setFreesync(!isOn) }
        }
    }

    package func setFreesync(_ on: Bool) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        guard isConnected else { return log("未连接") }
        currentValues["freesync"] = on ? "1" : "0"
        log("FreeSync: \(on ? "开" : "关")")

        let useMemory = freesyncMemoryEnabled && !memoriesSuspendedByPreset
        runPictureChange(delay: 1.8) {
            // ── 先读设备真实状态，再决定要不要记录 / 还原 ──
            // 不能用缓存里的 currentValues["freesync"]：它来自 JNI 回读，
            // 而 JNI 读取偶发失败会把缓存留在 0。于是「从关到开才记录」会误判成
            // 「本来就是关的」→ 记录下已被上一次 FreeSync 改过的模式；
            // 「从开到关才还原」也会误判成「本来就是关的」→ 直接跳过还原。
            let src = self.adb.settingsGet("mitv.tvplayer.hdmi.last.source")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isDP = (src == "29" || src == "30")
            let key = isDP ? "g_video__dp_adaptive_sync" : "g_video__freesync_switch"
            let onRaw = isDP ? "1" : "3"
            let before = Int(self.adb.jniBatchGet(keys: [key])[key] ?? "") ?? -1
            let wasOn = isDP ? (before == 1) : (before == 3)

            var restoreMode: Int? = nil
            if useMemory {
                if on && !wasOn {
                    // 画面模式同样现读，避免缓存过期把游戏模式记成"开启前"
                    let mode = Int(self.adb.settingsGet("picture_mode")
                        .trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                    // 只记「标准 / 游戏 / 电影」这三个标准模式。
                    // Dolby Vision、游戏子模式（SDR 游戏 RPG 之类）这些不是用户手动选的档位，
                    // 记下来再还原会很突兀 —— 而且它们在 FreeSync 开关时本来就会被自动切换。
                    if RegisterMap.modeNames[mode] != nil {
                        self.deviceWorkState.freesyncPreviousMode = mode
                        self.publish {
                            self.preferences.set(mode, forKey: "freesync_previous_mode")
                            self.log("FreeSync 模式记忆: 记录开启前模式 \(RegisterMap.modeNames[mode] ?? "\(mode)")")
                        }
                    } else {
                        self.deviceWorkState.freesyncPreviousMode = 0
                        self.publish {
                            self.preferences.removeObject(forKey: "freesync_previous_mode")
                            self.log("FreeSync 模式记忆: 当前是 \(RegisterMap.sceneNames[mode] ?? "未知模式")，非标准模式不记录")
                        }
                    }
                } else if !on && wasOn {
                    let saved = self.deviceWorkState.freesyncPreviousMode
                    restoreMode = RegisterMap.modeNames[saved] != nil ? saved : nil
                }
            }

            self.adb.jniSet(key: key, value: on ? onRaw : "0")
            // 关闭时先切回原先的画面模式，再 refresh_pq（顺序与原版一致）
            if !on, let restoreMode {
                self.adb.settingsPut("picture_mode", String(restoreMode))
            }
            self.adb.refreshPq()

            self.publish {
                if !on, let restoreMode {
                    self.currentValues["picture_mode"] = String(restoreMode)
                    self.log("FreeSync 模式记忆: 已切回 \(RegisterMap.sceneNames[restoreMode] ?? "\(restoreMode)")")
                }
            }
            self.refreshAfterEdidChange()
        }
    }

    nonisolated internal func refreshAfterEdidChange() {
        self.publish {
            self.scheduleCoalescedRefresh(delay: 1.5, pages: ["picture", "game"])
        }
    }


    package func setSource(_ value: Int) {
        guard isConnected else { return log("未连接") }
        let name = RegisterMap.sourceNames[value] ?? "未知"
        currentValues["mitv.tvplayer.hdmi.last.source"] = String(value)
        activeSource = name
        log("信号源: \(name)")
        runBackground {
            self.adb.shell("am force-stop com.xiaomi.mitv.tvplayer")
            self.adb.shell("am start -a com.xiaomi.mitv.tvplayer.EXTSRC_PLAY -n com.xiaomi.mitv.tvplayer/.ExternalSourceActivity --ei input \(value) -f 0x10000000")
            self.adb.refreshPq()
        }
    }


    package func setLightMode(_ value: Int) {
        currentValues["atmosphere_light_switcher_pm2"] = String(value)
        commitScreenLight("屏幕灯模式: \(RegisterMap.lightModeNames[value] ?? "\(value)")")
    }

    package func setLightIllumination(_ uiValue: Int) {
        let raw = max(0, min(14, uiValue - 1))
        currentValues["atmosphere_light_illumination"] = String(raw)
        commitScreenLight("屏幕灯亮度挡位: \(uiValue)")
    }

    package func setLightColorTemp(_ value: Int) {
        currentValues["atmosphere_light_switcher_pm2"] = "0"
        currentValues["atmosphere_light_color_temp"] = String(value)
        commitScreenLight("屏幕灯色温: \(RegisterMap.lightColorTempNames[value] ?? "\(value)")")
    }

    package func setLightColor(_ value: Int) {
        currentValues["atmosphere_light_switcher_pm2"] = "2"
        currentValues["atmosphere_light_color_value"] = String(value)
        commitScreenLight("屏幕灯颜色: \(RegisterMap.lightColorNames[value] ?? "\(value)")")
    }

    internal func commitScreenLight(_ message: String) {
        guard isConnected else { return log("未连接") }
        let mode = intValue("atmosphere_light_switcher_pm2", default: 4)
        let illumination = intValue("atmosphere_light_illumination", default: 9)
        let colorTemp = intValue("atmosphere_light_color_temp", default: 1)
        let colorValue = intValue("atmosphere_light_color_value", default: 0)
        log(message)
        runBackground {
            self.adb.settingsPut("atmosphere_light_switcher_pm2", String(mode))
            self.adb.settingsPut("atmosphere_light_illumination", String(illumination))
            self.adb.settingsPut("atmosphere_light_color_temp", String(colorTemp))
            self.adb.settingsPut("atmosphere_light_color_value", String(colorValue))
            switch mode {
            case 0: self.adb.colorfulLed(action: "lighting", args: [String(illumination), String(colorTemp)])
            case 1: self.adb.colorfulLed(action: "ambient")
            case 2: self.adb.colorfulLed(action: "solid", args: [String(illumination), String(colorValue)])
            case 3: self.adb.colorfulLed(action: "cycle")
            default: self.adb.colorfulLed(action: "off")
            }
        }
    }


    package func key(_ code: String) {
        guard isConnected else { return log("未连接") }
        log("按键: \(code)")
        runBackground { self.adb.keyevent(code) }
    }


}
