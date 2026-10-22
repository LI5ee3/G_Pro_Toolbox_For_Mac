import Synchronization

/// A stopped/restarted lifetime cannot execute or publish work from its predecessor.
package final class RuntimeGeneration: Sendable {
    private struct State { var revision = 0; var enabled = false }
    private let state = Mutex(State())
    package init() {}
    package func begin() { state.withLock { $0.revision &+= 1; $0.enabled = true } }
    package func resumeIfNeeded() { state.withLock { if !$0.enabled { $0.revision &+= 1; $0.enabled = true } } }
    package func end() { state.withLock { $0.revision &+= 1; $0.enabled = false } }
    package func token() -> Int { state.withLock { $0.revision } }
    package func allows(_ token: Int) -> Bool { state.withLock { $0.enabled && $0.revision == token } }
}
