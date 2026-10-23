import Foundation
import ToolboxConcurrency
import ToolboxDomain

/// Immutable submission-time target. A new attempt invalidates even the same endpoint.
package struct AdbSession: Sendable {
    let clientID: UUID
    package let endpoint: AdbEndpoint?
    package let cancellation: CommandCancellation
    package let sessionID: UUID
    package init(clientID: UUID, endpoint: AdbEndpoint?, cancellation: CommandCancellation, sessionID: UUID = UUID()) {
        self.clientID = clientID
        self.endpoint = endpoint
        self.cancellation = cancellation
        self.sessionID = sessionID
    }
    package func childOperation() -> AdbSession {
        AdbSession(clientID: clientID, endpoint: endpoint, cancellation: CommandCancellation(parent: cancellation), sessionID: sessionID)
    }
    package var serial: String { endpoint?.serial ?? "" }
}

/// Explicitly installed on the blocking worker, and removed before it returns. Never held across
/// await. Nested synchronous protocol helpers inherit the same target and cancellation.
package enum AdbOperationContext {
    @TaskLocal package static var current: AdbSession?
}

package enum RuntimeWorkContext {
    @TaskLocal package static var lifetime: Int?
}
