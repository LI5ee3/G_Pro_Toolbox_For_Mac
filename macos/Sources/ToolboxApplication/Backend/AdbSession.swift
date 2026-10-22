import Foundation
import ToolboxConcurrency

/// Immutable submission-time target. A new connection attempt invalidates even the same IP.
package struct AdbSession: Sendable {
    let clientID: UUID
    package let targetIP: String
    package let cancellation: CommandCancellation
    package func childOperation() -> AdbSession {
        AdbSession(clientID: clientID, targetIP: targetIP, cancellation: CommandCancellation(parent: cancellation))
    }
    package var serial: String { targetIP.isEmpty ? "" : "\(targetIP):5555" }
}

/// Explicitly installed on the blocking worker, and removed before it returns. Never held across
/// await. Nested synchronous protocol helpers inherit the same target and cancellation.
package enum AdbOperationContext {
    @TaskLocal package static var current: AdbSession?
}

package enum RuntimeWorkContext {
    @TaskLocal package static var lifetime: Int?
}
