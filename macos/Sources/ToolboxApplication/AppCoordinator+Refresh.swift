import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    internal func scheduleCoalescedRefresh(delay: TimeInterval, pages: [String]) {
        pendingRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRefreshWork = nil
            for page in pages { self.loadedPages.remove(page) }
            for page in pages { self.refreshPage(page) }
        }
        pendingRefreshWork = work
        environment.scheduler.after(delay, work: work)
    }


    /// JNI 才是硬件真实状态，settings 会漂移（比如用户用显示器自带的 OSD 改过设置，
    /// 或上一次写入只成功了一半）。下面几项一律以 JNI 回读值为准，
    /// 否则界面会显示与硬件实际不符的值。移植自 device_features.py:1381-1418。
    nonisolated internal func applyJniOverrides(_ values: inout [String: String]) {
        // 色域：MTK 值与 settings 值同域，直接覆盖主键和旧 OSD 键
        if let raw = values["g_video__vid_gamut_mapping_mode"], let v = Int(raw) {
            values["tv_picture_advanced_video_color_space"] = String(v)
            values["tv_picture_video_color_space"] = String(v)
        }
        // 色温：MTK 枚举与小米枚举不同，需要反查
        if let raw = values["g_video__clr_temp"], let v = Int(raw),
           let ui = RegisterMap.mtkToColorTemp[v] {
            values["picture_color_temperature"] = String(ui)
        }
        // 精密控光：覆盖官方主键和旧 OSD 键
        if let raw = values["g_video__vid_local_dimming"], let v = Int(raw) {
            values["picture_local_dimming"] = String(v)
            values["tv_picture_video_local_dimming"] = String(v)
        }
        // HDR 色调映射：OSD 索引与 MTK 底层枚举不同，需要反查
        if let raw = values["g_video__vid_hdr_tone_mapping_mode"], let v = Int(raw) {
            values["picture_hdr_tone_mapping"] = String(v)
            if let ui = RegisterMap.hdrToneMappingMtkToUI[v] {
                values["settings_display_hdr_color_tone"] = String(ui)
            }
        }
        // 响应时间同样以 JNI 为准（原版 query_setting_or_jni）
        if let raw = values["g_video__vid_od_response_time"], let v = Int(raw) {
            values["picture_response_time"] = String(v)
        }
        // 自动调整亮度（光感）：菜单读的是 MTK 侧，覆盖 settings 值
        if let raw = values["g_video__light_sensor_switch"], let v = Int(raw) {
            values["tv_picture_light_sensor"] = String(v)
        }
        // 背光滑条同样以 JNI 为准
        if let raw = values["g_disp__disp_back_light"], let v = Int(raw) {
            values["picture_backlight"] = String(v)
            values["xiaomi_picture_backlight"] = String(v)
        }
    }

    /// 游戏页的 320Hz / FreeSync 开关没有直接的 settings 键，要由 EDID / 自适应同步
    /// 的 JNI 值推导（移植自 device_features.py:1420-1452）。DP 和 HDMI 走不同的键。
    nonisolated internal func applyGameJniMode(_ values: inout [String: String]) {
        // Publish unknown explicitly so a failed refresh cannot preserve an old on/off value.
        values["mode_320"] = "-1"
        values["freesync"] = "-1"
        let modeKey: String, syncKey: String, modeOff: Int, modeOn: Int, syncOn: Int
        switch Int(values["mitv.tvplayer.hdmi.last.source"] ?? "") {
        case 29, 30:
            modeKey = "g_fusion_picture__dp_edid_version"; syncKey = "g_video__dp_adaptive_sync"
            modeOff = 2; modeOn = 3; syncOn = 1
        case 23, 24:
            modeKey = "g_fusion_picture__hdmi_edid_version"; syncKey = "g_video__freesync_switch"
            modeOff = 1; modeOn = 6; syncOn = 3
        default: return
        }
        // Reuse the strict existing batch contract, including complete process success.
        guard let readings = try? adb.jniBatchGetChecked(keys: [modeKey, syncKey], target: adb.serial) else { return }
        switch Int(readings[modeKey] ?? "") {
        case modeOff: values["mode_320"] = "0"
        case modeOn: values["mode_320"] = "1"
        default: break
        }
        switch Int(readings[syncKey] ?? "") {
        case 0: values["freesync"] = "0"
        case syncOn: values["freesync"] = "1"
        default: break
        }
    }

    /// HDR 色调映射只在部分画面模式下存在（原版会据此隐藏控件）
    package var showHdrToneMapping: Bool {
        RegisterMap.isHdrToneMappingPictureMode(currentValues["picture_mode"])
    }

    /// 有数据可刷的页面（对应原版 _page_data_keys）。主页/工具页没有可读寄存器。
    package func refreshPage(_ page: String) {
        guard isConnected else { return }
        guard !isPresetBusy else { return }
        guard Self.refreshablePages.contains(page) else { return }
        guard !loadedPages.contains(page) else { return }
        let connectionRequest = connectionIntent.generation
        let pageRequest = pageRefreshIntent.begin(page)
        loadedPages.insert(page)
        loadingPages.insert(page)

        let settingsKeys: [String]
        let jniKeys: [String]
        switch page {
        case "picture": settingsKeys = PageDataKeys.pictureSettings; jniKeys = PageDataKeys.pictureJni
        case "game": settingsKeys = PageDataKeys.gameSettings; jniKeys = []
        case "source": settingsKeys = PageDataKeys.sourceSettings; jniKeys = []
        case "light": settingsKeys = PageDataKeys.lightSettings; jniKeys = []
        default: settingsKeys = []; jniKeys = []
        }

        runBackground {
            // ── 第一阶段：settings（约 0.1s）──────────────────────────
            var settingsVals: [String: String] = [:]
            if !settingsKeys.isEmpty {
                settingsVals = self.adb.settingsGetBatch(settingsKeys)
            }
            if !settingsVals.isEmpty {
                self.publish {
                    guard self.isConnected,
                          self.connectionIntent.isCurrent(connectionRequest),
                          self.pageRefreshIntent.isCurrent(page, pageRequest) else { return }
                    self.mergeValues(settingsVals)
                    // 首屏数据到手就撤遮罩，不必等慢一档的 JNI
                    self.loadingPages.remove(page)
                    if let t0 = self.pageAppearTimes[page] {
                        let ms = Int(self.environment.now().timeIntervalSince(t0) * 1000)
                        if ms > 50 { self.log("⏱ \(page) 首屏数据 \(ms)ms") }
                    }
                }
            }

            // ── 第二阶段：JNI 回读（约 0.9s，瓶颈在设备端启动 app_process）──
            // 慢，所以单独一步：先把上面拿到的值显示出来，这一批到了再静默修正。
            var jniVals: [String: String] = [:]
            if !jniKeys.isEmpty {
                jniVals = self.adb.jniBatchGet(keys: jniKeys)
            }

            var merged = settingsVals
            for (k, v) in jniVals { merged[k] = v }
            self.applyJniOverrides(&merged)
            if page == "game" {
                self.applyGameJniMode(&merged)
            }

            // 只把「与 settings 不同」的键挑出来作为修正量
            var corrections: [String: String] = [:]
            for (k, v) in merged where settingsVals[k] != v {
                corrections[k] = v
            }

            self.publish {
                guard self.isConnected,
                      self.connectionIntent.isCurrent(connectionRequest),
                      self.pageRefreshIntent.isCurrent(page, pageRequest) else { return }
                if !corrections.isEmpty { self.mergeValues(corrections) }

                // 拿到新鲜的 picture_mode + front_sight_index 后按模式纠正准星
                if page == "picture" || page == "game" {
                    self.reconcileCrosshairModeState()
                }

                if page == "source",
                   let s = settingsVals["mitv.tvplayer.hdmi.last.source"],
                   let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    self.activeSource = RegisterMap.sourceNames[n] ?? s
                }
                self.loadingPages.remove(page)
                if let t0 = self.pageAppearTimes[page] {
                    let ms = Int(self.environment.now().timeIntervalSince(t0) * 1000)
                    self.pageAppearTimes[page] = nil
                    self.log("已刷新 \(page) 页面数据（合计 \(ms)ms）")
                } else {
                    self.log("已刷新 \(page) 页面数据")
                }
            }
        }
    }

    /// 合并当前读数后统一发布，避免每个键分别触发观察者。
    internal func mergeValues(_ values: [String: String]) {
        guard !values.isEmpty else { return }
        var merged = currentValues
        for (k, v) in values { merged[k] = v }
        currentValues = merged
    }

    package func forceRefreshPage(_ page: String) {
        loadedPages.remove(page)
        refreshPage(page)
    }

    package var hasPendingDeviceControls: Bool { !cyclePending.isEmpty || !adjustPendingWork.isEmpty }

    package func invalidatePictureRefreshesForPreset() {
        for page in ["picture", "game"] {
            _ = pageRefreshIntent.begin(page)
            loadedPages.remove(page)
            loadingPages.remove(page)
        }
        pendingRefreshWork?.cancel()
        pendingRefreshWork = nil
        // A countdown armed for the previous preset must never land in the new one.
        for item in cyclePending.values { item.work.cancel() }
        cyclePending.removeAll()
        for item in adjustPendingWork.values { item.cancel() }
        adjustPendingWork.removeAll()
        adjustPendingValues.removeAll()
        environment.feedback.endCountdown()
    }


}
