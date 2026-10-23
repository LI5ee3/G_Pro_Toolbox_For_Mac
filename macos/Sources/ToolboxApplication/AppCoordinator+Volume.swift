import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package var dashboardVolume: Int? {
        get { volume.dashboardVolume }
        set { volume.dashboardVolume = newValue }
    }
    package var dashboardMuted: Bool? {
        get { volume.dashboardMuted }
        set { volume.dashboardMuted = newValue }
    }
    package var dashboardVolumeError: String? {
        get { volume.dashboardVolumeError }
        set { volume.dashboardVolumeError = newValue }
    }
    internal func resetMediaVolumeSession() {
        mediaVolumeCommit?.cancel(); mediaVolumeCommit = nil
        mediaVolumeCommitInFlight = false
        mediaVolumePending = false
        mediaVolumePreview = nil; mediaVolumeHardware = nil; mediaVolumeMuted = nil
        mediaVolumeNeedsUnmute = false; mediaVolumeFallbackLogged = false
        dashboardVolume = nil; dashboardMuted = nil
    }

    // Main-thread state is checked before queued work and before publishing its result.
    internal func mediaSessionIsCurrent(_ request: Int, target: String) -> Bool {
        isConnected && connectionIntent.isCurrent(request) && adb.ip == target
    }

    /// 默认音频输出是否就是目标显示器 —— 音量键接管门。
    /// 读不到输出设备时返回 false：宁可交给系统，也不要吞掉按键却没反应。
    package func shouldHandleNativeVolume() -> Bool {
        AudioOutputMonitor.shouldHandleVolumeKeys(enabled: mediaVolumeKeysEnabled,
            adbConnected: isConnected, gateEnabled: mediaVolumeOutputGateEnabled,
            configuredOutputName: mediaVolumeOutputName,
            outputName: environment.system.defaultOutput())
    }

    /// 空闲时回读一次音量/静音状态（连接后 + 每 5 秒）。
    /// 连按/待下发期间跳过，避免把预览基准带偏。
    package func refreshMediaVolumeState() {
        guard isConnected else { return }
        guard !mediaVolumePending, !mediaVolumeCommitInFlight else { return }
        guard mediaVolumePreview == nil || mediaVolumePreview == mediaVolumeHardware else { return }
        let request = connectionIntent.generation, target = adb.ip
        runBackground {
            guard !self.adb.operationCancelled else { return }
            let volume = self.adb.mediaVolume()
            let muted = self.adb.mediaMuted()
            self.publish {
                guard self.mediaSessionIsCurrent(request, target: target) else { return }
                if let volume {
                    self.mediaVolumePreview = volume
                    self.mediaVolumeHardware = volume
                    self.dashboardVolume = volume
                }
                if let muted { self.mediaVolumeMuted = muted; self.dashboardMuted = muted }
            }
        }
    }

    internal func adjustMediaVolume(increase: Bool) {
        guard shouldHandleNativeVolume() else { return }
        guard isConnected else { return }

        let base = mediaVolumePreview ?? mediaVolumeHardware ?? 50
        let next: Int
        if mediaVolumeNativeOSD {
            // 系统 OSD 固定 16 格；开原生 OSD 时每按一次移动一格（和系统音量键一致）
            let chiclets = 16
            let chiclet = Int((Double(base) / 100 * Double(chiclets)).rounded())
            let target = min(max(chiclet + (increase ? 1 : -1), 0), chiclets)
            next = clamp(Int((Double(target) / Double(chiclets) * 100).rounded()), 0, 100)
        } else {
            let step = max(1, mediaVolumeStep)
            next = clamp(ControlStep.alignToStep(base, step: step, increasing: increase), 0, 100)
        }

        // 静音时按音量键先解除静音（和 macOS/Android 原生行为一致）
        if mediaVolumeMuted == true { mediaVolumeNeedsUnmute = true }
        mediaVolumePreview = next
        mediaVolumePending = true
        dashboardVolumeError = nil
        mediaVolumeMuted = false
        dashboardVolume = next
        dashboardMuted = false
        currentValues["volume_music_speaker"] = String(next)

        if mediaVolumeNativeOSD, environment.feedback.volume(next) {
            // 原生 OSD 自带淡出，不需要收尾
        } else {
            environment.feedback.show(title: "音量", value: "\(next)")
        }

        // 首次按下立即下发；之后连按只更新预览，由收尾任务合并成最后一次
        if !mediaVolumeCommitInFlight, mediaVolumeCommit == nil {
            commitMediaVolume()
        }
        scheduleMediaVolumeTrailing()
    }

    /// 安排收尾提交；若那时还有下发在跑，就顺延到它结束。
    internal func scheduleMediaVolumeTrailing() {
        mediaVolumeCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.mediaVolumeCommitInFlight {
                self.scheduleMediaVolumeTrailing()
                return
            }
            self.mediaVolumeCommit = nil
            self.commitMediaVolume()
        }
        mediaVolumeCommit = work
        environment.scheduler.after(mediaVolumeCommitDelay, work: work)
    }

    /// 把当前预览值绝对写到设备。目标值和已下发值相同时跳过，避免空跑一次。
    internal func commitMediaVolume() {
        guard isConnected, !mediaVolumeCommitInFlight, mediaVolumePending,
              let value = mediaVolumePreview else { return }
        mediaVolumePending = false
        let unmute = mediaVolumeNeedsUnmute
        guard mediaVolumeHardware != value || unmute else { return }
        mediaVolumeNeedsUnmute = false
        mediaVolumeCommitInFlight = true
        let request = connectionIntent.generation, target = adb.ip
        let cancellation = adb.session().cancellation
        runBackground(onCancel: {
            guard self.mediaSessionIsCurrent(request, target: target),
                  self.adb.session().cancellation === cancellation else { return }
            self.failMediaVolumeCommit("音量提交已取消", restoreUnmute: unmute)
        }) {
            let result = Result { try self.adb.setMediaVolume(value, unmuteFirst: unmute) }
            self.publish {
                guard self.mediaSessionIsCurrent(request, target: target) else { return }
                self.mediaVolumeCommitInFlight = false
                switch result {
                case .success(let channel):
                    self.mediaVolumeHardware = value
                    self.dashboardVolumeError = nil
                    self.logMediaFallback(channel, control: "音量")
                case .failure(let error):
                    self.failMediaVolumeCommit(error.localizedDescription, restoreUnmute: unmute)
                }
            }
        }
    }

    private func failMediaVolumeCommit(_ detail: String, restoreUnmute: Bool) {
        mediaVolumeCommitInFlight = false
        if restoreUnmute, mediaVolumeMuted != true { mediaVolumeNeedsUnmute = true }
        // 失败命令也可能部分生效，旧缓存不再用于跳过下一次真实输入。
        mediaVolumeHardware = nil
        if !mediaVolumePending {
            mediaVolumeCommit?.cancel(); mediaVolumeCommit = nil
            mediaVolumePreview = nil
        }
        reportMediaControlFailure(detail)
    }

    private func reportMediaControlFailure(_ detail: String) {
        dashboardVolumeError = detail
        mediaVolumeMuted = nil; dashboardMuted = nil
        log("音量/静音操作失败：\(detail)")
        refreshMediaVolumeState()
    }

    private func logMediaFallback(_ channel: AdbClient.MediaControlChannel, control: String) {
        if channel == .keyevent, !mediaVolumeFallbackLogged {
            mediaVolumeFallbackLogged = true
            log("\(control): AudioService binder 不可用，input keyevent 已执行成功")
        }
    }

    internal func toggleMediaMute() {
        guard shouldHandleNativeVolume() else { return }
        guard isConnected else { return }
        if let known = mediaVolumeMuted {
            applyMediaMute(!known)
        } else {
            // 状态未知（刚连接/被外部改过）：先回读再切换
            let request = connectionIntent.generation, target = adb.ip
            runBackground {
                guard !self.adb.operationCancelled else { return }
                let current = self.adb.mediaMuted()
                self.publish {
                    guard self.mediaSessionIsCurrent(request, target: target) else { return }
                    guard let current else {
                        self.reportMediaControlFailure("无法读取显示器静音状态，未执行切换")
                        return
                    }
                    self.applyMediaMute(!current)
                }
            }
        }
    }

    internal func applyMediaMute(_ muted: Bool, writeToDevice: Bool = true) {
        dashboardVolumeError = nil
        mediaVolumeMuted = muted
        dashboardMuted = muted
        // 更新的静音动作覆盖掉「按键先解除静音」的意图，避免收尾提交把它又打开
        mediaVolumeNeedsUnmute = false
        if mediaVolumeNativeOSD, environment.feedback.mute(muted) {
            // 原生静音 OSD
        } else {
            environment.feedback.show(title: "静音", value: muted ? "开" : "关")
        }
        guard writeToDevice else { return }
        let request = connectionIntent.generation, target = adb.ip
        runBackground {
            guard !self.adb.operationCancelled else { return }
            let result = Result { try self.adb.setMediaMuted(muted) }
            self.publish {
                guard self.mediaSessionIsCurrent(request, target: target) else { return }
                switch result {
                case .success(let channel):
                    self.dashboardVolumeError = nil
                    self.mediaVolumeMuted = muted; self.dashboardMuted = muted
                    self.logMediaFallback(channel, control: "静音")
                case .failure(let error): self.reportMediaControlFailure(error.localizedDescription)
                }
            }
        }
    }

    /// Explicit on-screen controls target the display regardless of Mac's audio output.
    package var dashboardVolumeAvailable: Bool { isConnected }
    package var dashboardVolumeTransport: String { "网络 ADB" }

    package func setDashboardVolume(_ value: Int) {
        guard isConnected else { return }
        let value = clamp(value, 0, 100)
        if mediaVolumeMuted == true { mediaVolumeNeedsUnmute = true }
        dashboardVolumeError = nil
        mediaVolumeMuted = false
        dashboardMuted = false
        dashboardVolume = value
        mediaVolumePreview = value
        mediaVolumePending = true
        currentValues["volume_music_speaker"] = String(value)
        if !mediaVolumeCommitInFlight, mediaVolumeCommit == nil { commitMediaVolume() }
        scheduleMediaVolumeTrailing()
    }

    package func toggleDashboardMute() {
        guard isConnected else { return }
        let request = connectionIntent.generation
        let target = adb.ip
        dashboardVolumeError = nil
        if let known = mediaVolumeMuted {
            mediaVolumeMuted = !known; dashboardMuted = !known
            mediaVolumeNeedsUnmute = false
        }
        runBackground {
            guard !self.adb.operationCancelled else { return }
            // Keep the read and mutation together: two rapid clicks must toggle twice.
            let result = Result {
                try self.adb.transaction {
                    guard let current = self.adb.mediaMuted() else {
                        throw PresetError("无法读取显示器静音状态，未执行切换")
                    }
                    try self.adb.checkCancellation()
                    let next = !current
                    return (muted: next, channel: try self.adb.setMediaMuted(next))
                }
            }
            self.publish {
                guard self.isConnected, self.connectionIntent.isCurrent(request),
                      self.adb.ip == target else { return }
                switch result {
                case .success(let applied):
                    self.applyMediaMute(applied.muted, writeToDevice: false)
                    self.logMediaFallback(applied.channel, control: "静音控制")
                case .failure(let error): self.reportMediaControlFailure(error.localizedDescription)
                }
            }
        }
    }


    /// 目标显示器的 displayID（按系统名称匹配）
}
