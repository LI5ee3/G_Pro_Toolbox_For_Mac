import Foundation
import AppKit
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

    package var pictureModeHint: String { picture.pictureModeHint }
    package var gameModeState: PictureModel.GameModeState { picture.gameModeState }
    package var gameModeHintText: String { picture.gameModeHintText }
    package var gameModeHintIsWarning: Bool { picture.gameModeHintIsWarning }
    package var isCustomColorTemp: Bool { picture.isCustomColorTemp }
    package func intValue(_ key: String, default fallback: Int) -> Int { picture.intValue(key, default: fallback) }

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
