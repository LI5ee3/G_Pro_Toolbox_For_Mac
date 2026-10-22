import Foundation

package enum HotkeyListenerStatus: Sendable { case stopped, permissionRequired, running, failed }
package enum TerminalOutcome: Sendable { case opened, denied, failed }
package struct TerminalResult: Sendable, Equatable {
    package let outcome: TerminalOutcome
    package let detail: String
    package init(outcome: TerminalOutcome, detail: String = "") { self.outcome = outcome; self.detail = detail }
}

package enum FileActionResult: Sendable, Equatable { case success, failure(String) }
