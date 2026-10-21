import Foundation
import AppKit
import SwiftUI
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func recoverAfterWake() {
        guard connectionIntent.allowsAutomaticRecovery else { return }
        let request = connectionIntent.generation
        scheduleStartup(after: 1.5) { [weak self] in
            guard let self, self.connectionIntent.isCurrent(request) else { return }
            self.monitorAdbServer(refreshState: true)
        }
    }

    package var isConnected: Bool { connection.isConnected }
    package var statusText: String { connection.statusText }

    package var pictureModeHint: String {
        let raw = currentValues["picture_mode"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, let mode = Int(raw) else {
            return "当前场景：未知（\(raw ?? "无")）"
        }
        if let group = RegisterMap.pictureModeGroupName(mode) {
            return "当前场景：\(group)（\(mode)）"
        }
        let scene = RegisterMap.sceneNames[mode] ?? "未知场景"
        return "当前场景：\(scene)（\(mode)），不匹配上方模式按钮"
    }

    /// 游戏模式提示的三态（移植自 _update_game_mode_hint）
    package enum GameModeState { case unknown, active, inactive }

    package var gameModeState: GameModeState {
        // 两个键任一有有效值就算"已知"；原版还会容忍 "null"/"N/A"
        let keys = ["picture_mode", "picture_preset_scenario"]
        let known = keys.contains { key in
            guard let v = currentValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !v.isEmpty && v != "null" && v != "N/A"
        }
        guard known else { return .unknown }
        let isGame = keys.contains { RegisterMap.isGamePictureMode(currentValues[$0]) }
        return isGame ? .active : .inactive
    }

    package var gameModeHintText: String {
        switch gameModeState {
        case .unknown: return "当前画面模式未知；高亮值尚未确认是否生效。"
        case .active: return "当前为游戏模式；下方高亮为当前生效值。"
        case .inactive: return "当前不是游戏模式；下方高亮为记忆值，功能当前未生效。"
        }
    }

    /// 未知 / 非游戏模式用琥珀色警示，游戏模式用常规色
    package func intValue(_ key: String, default fallback: Int) -> Int {
        guard let s = currentValues[key],
              let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return fallback }
        return v
    }

    internal func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

    package nonisolated func log(_ message: String) {
        DispatchQueue.main.async {
            let line = "[\(Self.timeFormatter.string(from: self.environment.now()))] \(message)"
            self.logs.append(line)
            if self.logToFileEnabled { self.environment.system.appendLog(line + "\n") }
        }
    }

    package func runBackground(_ work: @escaping @Sendable () -> Void) {
        guard isRunning || environment.mode == .simulation else { return }
        let token = executionLifetime.token()
        deviceQueue.async { [executionLifetime] in
            guard executionLifetime.allows(token) else { return }; work()
        }
    }

    internal func runConnectionTask(_ work: @escaping @Sendable () -> Void) {
        guard isRunning || environment.mode == .simulation else { return }
        let token = executionLifetime.token()
        connectionQueue.async { [executionLifetime] in
            guard executionLifetime.allows(token) else { return }; work()
        }
    }

    internal func setValue(_ key: String, _ value: String) {
        DispatchQueue.main.async { self.currentValues[key] = value }
    }


    /// 启动时自动连接上次设备；没记录就扫描内网（对应原版 _auto_connect_on_startup）。
}
