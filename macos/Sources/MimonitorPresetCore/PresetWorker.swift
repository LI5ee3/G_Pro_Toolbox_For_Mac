import Foundation
import Synchronization

/// The engine and store never leave this synchronous owner. Call only from a blocking worker;
/// callbacks must not synchronously acquire MainActor. The protocol transaction remains outside
/// this lock, and neither lock is held across await. Only Sendable snapshots leave the owner.
package final class PresetWorker: Sendable {
    private let engine: Mutex<PresetEngine>
    package let initialConfiguration: PresetConfiguration
    package let loadError: String?
    package init(store: sending PresetStore) {
        initialConfiguration = store.configuration; loadError = store.loadError
        engine = Mutex(PresetEngine(store: store))
    }
    package func withEngine<Value: Sendable>(_ work: (PresetEngine) throws -> Value) rethrows -> Value {
        try engine.withLock { try work($0) }
    }
}
