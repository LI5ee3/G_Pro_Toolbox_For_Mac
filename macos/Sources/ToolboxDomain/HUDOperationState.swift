import Foundation

package enum HUDOperationResult: Equatable, Sendable {
    case success, failure, cancelled

    package static func completion(isCurrentConnection: Bool, hasError: Bool,
                           verifiedApplications: [Bool]) -> HUDOperationResult {
        guard isCurrentConnection else { return .cancelled }
        guard !hasError else { return .failure }
        guard !verifiedApplications.isEmpty else { return .cancelled }
        return verifiedApplications.allSatisfy { $0 } ? .success : .failure
    }
}

package enum HUDOperationPhase: Equatable, Sendable {
    case running
    case finished(HUDOperationResult)
}

/// Main-thread ownership and completion tokens keep an old operation from replacing a new HUD.
package struct HUDOperationState: Sendable {
    package init() {}
    package private(set) var phase: HUDOperationPhase?
    private var token: UUID?
    package var keepsVisible: Bool { phase == .running }
    package var acceptsValueHint: Bool { !keepsVisible }

    package mutating func begin() -> UUID {
        let token = UUID()
        self.token = token
        phase = .running
        return token
    }
    package mutating func finish(token: UUID, result: HUDOperationResult) -> Bool {
        guard self.token == token, phase == .running else { return false }
        phase = .finished(result)
        return true
    }
    package mutating func showValueHint() {
        guard acceptsValueHint else { return }
        token = nil
        phase = nil
    }
}
