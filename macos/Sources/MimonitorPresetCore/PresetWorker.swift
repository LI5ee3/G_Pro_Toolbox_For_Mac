import Foundation
import Synchronization
import ToolboxDomain

/// The engine and store never leave this synchronous owner. Call only from a blocking worker;
/// callbacks must not synchronously acquire MainActor. The protocol transaction remains outside
/// this lock, and neither lock is held across await. Only Sendable snapshots leave the owner.
package final class PresetWorker: Sendable {
    private struct State {
        let engine: PresetEngine
        let profile: ConnectionProfileStore
    }
    private let state: Mutex<State>
    package let initialConfiguration: PresetConfiguration
    package let loadError: String?
    package init(store: sending PresetStore) {
        initialConfiguration = store.configuration; loadError = store.loadError
        state = Mutex(State(engine: PresetEngine(store: store),
                            profile: ConnectionProfileStore(preferences: store.defaults)))
    }
    package func withEngine<Value: Sendable>(_ work: (PresetEngine) throws -> Value) rethrows -> Value {
        try state.withLock { try work($0.engine) }
    }
    /// Capture the post-operation profile under the same non-recursive owner lock.
    package func withEngineAndProfileSnapshot<Value: Sendable>(_ work: (PresetEngine) throws -> Value) rethrows
        -> (Value, ConnectionProfileSnapshot) {
        try state.withLock { state in
            let value = try work(state.engine)
            return (value, state.profile.snapshot())
        }
    }
    package func connectionProfileSnapshot() -> ConnectionProfileSnapshot {
        state.withLock { $0.profile.snapshot() }
    }
    private func withProfile<Value: Sendable>(_ work: (ConnectionProfileStore) throws -> Value) rethrows -> Value {
        try state.withLock { try work($0.profile) }
    }
    package func saveConnectionPreference(endpoint: AdbEndpoint, expected: ConnectionProfileSnapshot,
        backup: (Data, String) throws -> Void, validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        try withProfile { try $0.savePreference(endpoint: endpoint, expected: expected,
            backup: backup, validateCurrent: validateCurrent) }
    }
    package func bindConnectionIdentity(evidence: IdentityEvidence, expected: ConnectionProfileSnapshot,
        confirmLegacyOwnership: Bool, confirmMemories: Bool = false,
        backup: (Data, String) throws -> Void, validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        try withProfile { try $0.bind(evidence: evidence, expected: expected,
            confirmLegacyOwnership: confirmLegacyOwnership, confirmMemories: confirmMemories,
            backup: backup, validateCurrent: validateCurrent) }
    }
    package func restoreConnectionProfile(backupData: Data, expected: ConnectionProfileSnapshot,
        backup: (Data, String) throws -> Void, validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        try withProfile { try $0.restore(backupData: backupData, expected: expected,
            backup: backup, validateCurrent: validateCurrent) }
    }
}
