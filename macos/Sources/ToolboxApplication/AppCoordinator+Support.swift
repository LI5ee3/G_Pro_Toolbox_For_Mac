import ToolboxConcurrency
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
        self.publish {
            let line = "[\(Self.timeFormatter.string(from: self.environment.now()))] \(message)"
            self.logs.append(line)
            if self.logToFileEnabled { self.environment.system.appendLog(line + "\n") }
        }
    }

    package func runBackground(onCancel: @escaping @MainActor () -> Void = {}, _ work: @escaping @Sendable () -> Void) {
        submitOperation(on: deviceQueue, work: work, onCancel: onCancel) { _ in }
    }

    internal func runConnectionTask(onCancel: @escaping @MainActor () -> Void = {}, _ work: @escaping @Sendable () -> Void) {
        submitOperation(on: connectionQueue, work: work, onCancel: onCancel) { _ in }
    }

    /// Snapshot on MainActor, run the entire synchronous transaction on its worker, then await a
    /// typed result. The recursive protocol lock never crosses await or a task suspension point.
    internal func submitOperation<Value: Sendable>(on queue: DispatchQueue,
            work: @escaping @Sendable () -> Value,
            onCancel: @escaping @MainActor () -> Void = {},
            completion: @escaping @MainActor (Value) -> Void) {
        guard isRunning || environment.mode == .simulation else { return }
        let lifetime = executionLifetime.token(), session = adb.session().childOperation()
        let job = BlockingExecutor(queue: queue).submit(cancellation: session.cancellation) { [adb, executionLifetime] in
            try RuntimeWorkContext.$lifetime.withValue(lifetime) {
                try adb.withSession(session) {
                    guard executionLifetime.allows(lifetime), !session.cancellation.isCancelled else { throw CancellationError() }
                    return work()
                }
            }
        }
        workTasks.observe(job) { [weak self, executionLifetime] result in
            guard self != nil, executionLifetime.allows(lifetime) else { return }
            guard !session.cancellation.isCancelled else { onCancel(); return }
            switch result {
            case .success(let value): completion(value)
            case .failure: onCancel()
            }
        }
    }

    /// System mutations have their own owner; switching ADB targets cannot cancel login changes.
    internal func submitSystemOperation<Value: Sendable>(
        work: @escaping @Sendable (CommandCancellation) -> Value,
        completion: @escaping @MainActor (Value) -> Void) {
        guard isRunning || environment.mode == .simulation else { return }
        let lifetime = executionLifetime.token(), token = CommandCancellation(parent: systemCancellation)
        let job = BlockingExecutor(queue: systemQueue).submit(cancellation: token) { [executionLifetime] in
            guard executionLifetime.allows(lifetime), !token.isCancelled else { throw CancellationError() }
            return work(token)
        }
        workTasks.observe(job) { [weak self, executionLifetime] result in
            guard self != nil, executionLifetime.allows(lifetime), !token.isCancelled else { return }
            if case .success(let value) = result { completion(value) }
        }
    }

    /// Deterministic test/readiness barrier for typed async completions; never blocks MainActor.
    package func waitForPendingWork() async { await workTasks.waitForAll() }

    /// Drop callbacks queued by a replaced session or a stopped/restarted app lifetime.
    nonisolated internal func publish(_ work: @escaping @MainActor () -> Void) {
        let cancellation = adb.operationSession?.cancellation
        let lifetime = RuntimeWorkContext.lifetime ?? executionLifetime.token()
        DispatchQueue.main.async { [executionLifetime] in
            guard executionLifetime.allows(lifetime), cancellation?.isCancelled != true else { return }
            work()
        }
    }

    /// Completion bookkeeping must finish even when the target changed. Feature values still use publish.
    nonisolated internal func publishCompletion(_ work: @escaping @MainActor () -> Void) {
        let lifetime = RuntimeWorkContext.lifetime ?? executionLifetime.token()
        DispatchQueue.main.async { [executionLifetime] in
            guard executionLifetime.allows(lifetime) else { return }; work()
        }
    }

    internal func setValue(_ key: String, _ value: String) {
        self.publish { self.currentValues[key] = value }
    }


    /// 启动时自动连接上次设备；没记录就扫描内网（对应原版 _auto_connect_on_startup）。
}
