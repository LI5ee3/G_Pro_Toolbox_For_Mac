import Foundation
import Synchronization

/// One-way, lock-protected cancellation shared by a task and its blocking subprocess.
package final class CommandCancellation: Sendable {
    private let cancelled = Mutex(false)
    package init() {}
    package var isCancelled: Bool { cancelled.withLock { $0 } }
    package func cancel() { cancelled.withLock { $0 = true } }
    /// Only for dedicated blocking workers, never the MainActor or a cooperative executor.
    @discardableResult package func sleep(for interval: TimeInterval) -> Bool {
        let end = ContinuousClock.now.advanced(by: .seconds(max(0, interval)))
        while !isCancelled, ContinuousClock.now < end {
            Thread.sleep(forTimeInterval: min(0.02, max(0, interval)))
        }
        return !isCancelled
    }
}

package struct CommandRequest: Sendable {
    package let executable: String
    package let arguments: [String]
    package let serverPort: String
    package let timeout: TimeInterval
    package let cancellation: CommandCancellation
    package init(executable: String, arguments: [String], serverPort: String, timeout: TimeInterval,
                 cancellation: CommandCancellation = CommandCancellation()) {
        self.executable = executable; self.arguments = arguments; self.serverPort = serverPort
        self.timeout = timeout; self.cancellation = cancellation
    }
}

package struct ProcessResult: Sendable {
    package enum Outcome: Sendable, Equatable {
        case exited, signalled(Int32), timedOut, cancelled, launchFailed(Int32), ioFailure(Int32)
    }
    package let standardOutput: String
    package let standardError: String
    package let exitCode: Int32
    package let outcome: Outcome
    package let outputTruncated: Bool
    package var output: String { standardOutput + standardError }
    package var succeeded: Bool { outcome == .exited && exitCode == 0 && !outputTruncated }
    package init(output: String, exitCode: Int32) {
        self.init(standardOutput: output, standardError: "", exitCode: exitCode, outcome: .exited)
    }
    package init(standardOutput: String = "", standardError: String = "", exitCode: Int32,
                 outcome: Outcome, outputTruncated: Bool = false) {
        self.standardOutput = standardOutput; self.standardError = standardError
        self.exitCode = exitCode; self.outcome = outcome; self.outputTruncated = outputTruncated
    }
    package static var cancelled: Self {
        Self(standardError: "ADB 命令已取消", exitCode: -1, outcome: .cancelled)
    }
}
