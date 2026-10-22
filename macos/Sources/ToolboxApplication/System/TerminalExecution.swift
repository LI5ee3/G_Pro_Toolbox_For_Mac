import Foundation
import ToolboxDomain
import ToolboxConcurrency

package enum TerminalExecution {
    package static func result(_ process: ProcessResult) -> TerminalResult {
        if process.succeeded { return TerminalResult(outcome: .opened) }
        let text = process.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let denied = text.contains("-1743")
        return TerminalResult(outcome: denied ? .denied : .failed,
            detail: "\(process.outcome)（\(process.exitCode)）：\(text.prefix(2000))")
    }
    package static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
