import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func toggleHdrMemory(_ enabled: Bool) {
        guard let enabled = presetControlPolicy.memoryPreferenceChange(requested: enabled) else { return }
        hdrMemoryEnabled = enabled
        preferences.set(enabled, forKey: "hdr_sdr_local_dimming_enabled")
        hdrLastState = nil
        log("HDR/SDR 分区控光记忆: \(enabled ? "开启" : "关闭")")
        updateHdrMemoryStatus()
        if enabled { pollHdrState(force: true) }
    }

    /// 最近一次判定 HDR 用的是哪条信号，用于界面说明
    package func pollHdrState(force: Bool = false) {
        let host = environment.system.hostHDR()
        let monitor = RegisterMap.isHDRPictureMode(currentValues["picture_mode"])
        let state = host || monitor
        hdrStateSource = host && monitor ? "主机+显示器"
            : (host ? "主机 EDR" : (monitor ? "显示器模式" : ""))
        let prev = hdrLastState
        hdrLastState = state
        updateHdrMemoryStatus()

        let changed = (prev != nil && prev != state)

        // HDR 切换后必须重读画面页：显示器侧的判据用的是缓存的 picture_mode，
        // 不重读的话它会一直停在上一次的值（实测关了 HDR 后仍显示「HDR（显示器模式）」）。
        // 同时 HDR 切换会连带换掉一整套画面参数，本来也该重新回读。
        if changed || force {
            schedulePictureRefreshAfterHdrChange()
        }

        guard hdrMemoryEnabled, !memoriesSuspendedByPreset else { return }
        if force || changed {
            applyHdrMemory(state: state)
        }
    }

    /// 移植自原版 _schedule_picture_refresh_after_hdr_change。
    /// 开了记忆时要多等一会儿 —— 精密控光的下发要 2~3 秒才落到设备上，
    /// 太早回读会读到旧值。
    internal func schedulePictureRefreshAfterHdrChange() {
        let delay = hdrMemoryEnabled ? 2.5 : 0.4
        scheduleCoalescedRefresh(delay: delay, pages: ["picture"])
    }

    internal func applyHdrMemory(state: Bool) {
        guard isConnected, !memoriesSuspendedByPreset else { return }
        let bucket = state ? "hdr" : "sdr"
        guard let value = localDimmingMemory()[bucket] else { return }

        runBackground {
            // 现读设备真实值。用缓存的 currentValues 会因 JNI 读取偶发失败而过期，
            // 导致该下发时不下发、或重复下发。
            let raw = self.adb.settingsGet("picture_local_dimming")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard Int(raw) != value else { return }
            self.publish {
                guard self.isConnected, !self.memoriesSuspendedByPreset else { return }
                let valueName = ["关", "低", "中", "高"][value]
                self.log("\(state ? "HDR" : "SDR") 精密控光记忆: \(valueName)")
                // 原版这里也会弹悬浮提示（_apply_hdr_memory_for_current_state）
                self.environment.feedback.show(title: "\(state ? "HDR" : "SDR") 精密控光", value: valueName)
                self.setLocalDimming(value)
            }
        }
    }

    internal func localDimmingMemory() -> [String: Int] {
        guard let data = preferences.data(forKey: "local_dimming_memory"),
              let m = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return m
    }

    internal func saveLocalDimmingMemory(_ m: [String: Int]) {
        if let data = try? JSONEncoder().encode(m) {
            preferences.set(data, forKey: "local_dimming_memory")
        }
        updateHdrMemoryStatus()
    }

    package func updateHdrMemoryStatus() {
        let stateText = hdrLastState == nil ? "未知" : (hdrLastState! ? "HDR" : "SDR")
        let m = localDimmingMemory()
        let sdrText = m["sdr"].map { ["关", "低", "中", "高"][$0] } ?? "--"
        let hdrText = m["hdr"].map { ["关", "低", "中", "高"][$0] } ?? "--"
        let sourceText = hdrStateSource.isEmpty ? "" : "（\(hdrStateSource)）"
        let status = memoriesSuspendedByPreset ? "已锁定（预设生效或切换中）" : (hdrMemoryEnabled ? "已开启" : "已关闭")
        let text = "分区控光记忆：\(status)，当前信号：\(stateText)\(sourceText)，记忆模式：SDR=\(sdrText) / HDR=\(hdrText)"
        // 只在内容真的变了才赋值，避免无意义的观察通知，
        // 而 HDR 状态是 3 秒轮询一次，无脑赋值等于每 3 秒全量重绘一次。
        if hdrMemoryStatusText != text { hdrMemoryStatusText = text }
    }


    package func toggleFreesyncMemory(_ enabled: Bool) {
        guard let enabled = presetControlPolicy.memoryPreferenceChange(requested: enabled) else { return }
        freesyncMemoryEnabled = enabled
        preferences.set(enabled, forKey: "freesync_mode_memory_enabled")
        log("FreeSync Pro 模式记忆: \(enabled ? "开启" : "关闭")")
        updateFreesyncMemoryStatus()
    }

    package func updateFreesyncMemoryStatus() {
        let saved = preferences.integer(forKey: "freesync_previous_mode")
        let savedText = saved == 0 ? "--" : (RegisterMap.sceneNames[saved] ?? "\(saved)")
        let status = memoriesSuspendedByPreset ? "已锁定（预设生效或切换中）" : (freesyncMemoryEnabled ? "已开启" : "已关闭")
        let text = "模式记忆：\(status)，记录模式：\(savedText)"
        if freesyncMemoryStatusText != text { freesyncMemoryStatusText = text }
    }

    //
    // front_sight_index 是设备级 settings，与 picture_mode 解耦：不主动清理的话，
    // 切到标准/电影等模式后准星依然显示。这里在离开游戏模式时记住并隐藏，
    // 回到游戏模式时还原。

    internal var crosshairMemory: Int? {
        guard preferences.object(forKey: "crosshair_memory") != nil else { return nil }
        return preferences.integer(forKey: "crosshair_memory")
    }

    internal func saveCrosshairMemory(_ value: Int) {
        preferences.set(value, forKey: "crosshair_memory")
        updateCrosshairModeStatus()
    }

    internal func clearCrosshairMemory() {
        preferences.removeObject(forKey: "crosshair_memory")
        updateCrosshairModeStatus()
    }

    package func toggleCrosshairGameModeOnly(_ enabled: Bool) {
        crosshairGameModeOnly = enabled
        preferences.set(enabled, forKey: "crosshair_game_mode_only")
        log("准星仅在游戏模式下生效: \(enabled ? "开启" : "关闭")")
        updateCrosshairModeStatus()
        if enabled { reconcileCrosshairModeState() }
    }

    internal func updateCrosshairModeStatus() {
        let text: String
        if !crosshairGameModeOnly {
            text = "已关闭，准星在所有模式下都生效"
        } else if let memory = crosshairMemory {
            text = "已开启，离开游戏模式时自动隐藏（已记忆准星 \(memory)）"
        } else {
            text = "已开启，离开游戏模式时自动隐藏（暂无记忆）"
        }
        if crosshairModeStatusText != text { crosshairModeStatusText = text }
    }

    /// 按当前画面模式纠正准星。由页面数据刷新驱动（含模式切换后的自动刷新），
    /// 没有周期轮询——用显示器遥控器改模式时，会在下次刷新数据时纠正。
    ///
    /// 隐藏是「只要在非游戏模式看到准星就清掉」；还原只在「模式跃迁进入游戏
    /// 模式」时做一次，避免用户用显示器 OSD 主动关掉准星后又被打开。
    package func reconcileCrosshairModeState() {
        guard crosshairGameModeOnly, isConnected else { return }
        guard !crosshairReconcileBusy else { return }
        guard let mode = currentValues["picture_mode"] else { return }
        guard let raw = currentValues["front_sight_index"],
              let crosshair = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        let previousMode = crosshairLastMode
        crosshairLastMode = mode

        if RegisterMap.isGamePictureMode(mode) {
            let enteringGameMode = previousMode != nil && !RegisterMap.isGamePictureMode(previousMode)
            if enteringGameMode, crosshair == 0, let memory = crosshairMemory {
                applyCrosshairModeValue(memory, message: "进入游戏模式，已恢复记忆的准星 \(memory)")
            }
            return
        }

        if crosshair != 0 {
            saveCrosshairMemory(crosshair)
            applyCrosshairModeValue(0, message: "离开游戏模式，已隐藏准星（记忆 \(crosshair)）")
        }
    }

    internal func applyCrosshairModeValue(_ value: Int, message: String) {
        crosshairReconcileBusy = true
        runBackground(onCancel: { self.crosshairReconcileBusy = false }) {
            self.adb.settingsPut("front_sight_index", String(value))
            self.adb.refreshPq()
            self.publish {
                self.log(message)
                self.mergeValues(["front_sight_index": String(value)])
                self.updateCrosshairModeStatus()
                // 重入的 reconcile 由 busy 标记挡住，结束后再放开
                self.crosshairReconcileBusy = false
            }
        }
    }


}
